// Direct port of Sources/FastReadCore/RSVPEngine.swift to Kotlin.
// Same hybrid pipeline: script-split → ICU BreakIterator on CJK runs →
// whitespace split on Latin runs → user-dictionary post-merge → glue
// punctuation to the previous token. Behaviour and output should match
// the Swift parity-corpus.json fixture for any input.

package com.shhtheonlyperson.fastread.spike.core

import java.text.BreakIterator
import java.util.Locale

object RSVPEngine {
    /// Bump when the tokenizer or shaper produces a materially different
    /// chunking for the same input. Persistence drops cached tokens whose
    /// stored `tokenizerVersion` no longer matches this value. Kept in
    /// lock-step with Sources/FastReadCore/RSVPEngine.swift.
    // Constants & rule tables are single-sourced from Tools/rsvp-spec.json via
    // the generated RsvpSpec (see RsvpSpec.generated.kt). Don't inline new
    // literals here — add them to the spec so all three platforms stay in sync.
    const val VERSION: Int = RsvpSpec.VERSION
    const val DEFAULT_WPM: Double = RsvpSpec.Wpm.DEFAULT
    const val MINIMUM_SAFE_WPM: Double = RsvpSpec.Wpm.MINIMUM_SAFE
    const val MAXIMUM_WPM: Double = RsvpSpec.Wpm.MAXIMUM

    data class FocusSplit(val before: String, val focus: String, val after: String)

    data class ContextWindow(
        val lowerBound: Int,
        val upperBound: Int,
        val hasLeadingOverflow: Boolean,
        val hasTrailingOverflow: Boolean,
    ) {
        val range: IntRange get() = lowerBound until upperBound
        val count: Int get() = (upperBound - lowerBound).coerceAtLeast(0)
    }

    fun countReadingUnits(input: String?): Int =
        tokenize(input).count { token -> token.any { isFocusable(it) || isCJKCharacter(it) } }

    fun containsCJK(input: String?): Boolean = input != null && hasCJK(input)

    fun tokenize(input: String?, userDictionary: List<String> = emptyList()): List<String> {
        if (input == null) return emptyList()
        val normalized = input.replace(' ', ' ')
        if (!hasCJK(normalized)) {
            return normalized.split(Regex("\\s+")).filter { it.isNotEmpty() }
        }
        return tokenizeMixed(normalized, userDictionary)
    }

    fun focusIndex(token: String?): Int {
        val chars = token?.toCharArray() ?: charArrayOf()
        if (chars.isEmpty()) return 0

        val focusable = chars.indices.filter { isFocusable(chars[it]) }
        if (focusable.isEmpty()) return chars.size / 2

        val target = when (focusable.size) {
            in 0..1 -> 0
            in 2..5 -> 1
            in 6..9 -> 2
            in 10..13 -> 3
            else -> 4
        }
        return focusable[minOf(target, focusable.lastIndex)]
    }

    fun splitForFocus(token: String?): FocusSplit {
        val chars = token?.toCharArray() ?: charArrayOf()
        if (chars.isEmpty()) return FocusSplit("", "", "")
        val idx = focusIndex(token)
        return FocusSplit(
            before = String(chars, 0, idx),
            focus = chars[idx].toString(),
            after = String(chars, idx + 1, chars.size - idx - 1),
        )
    }

    fun duration(token: String?, wpm: Double, punctuationPause: Boolean = true): Int {
        val safeWpm = safeWPM(wpm)
        val base = RsvpSpec.Duration.BASE_MILLIS_PER_MINUTE / safeWpm
        val raw = token ?: ""
        val isCJK = hasCJK(raw)
        val focusableCount = raw.toCharArray().count { isFocusable(it) || isCJKCharacter(it) }
        val cjkMultiplier = if (isCJK) RsvpSpec.Duration.CJK_MULTIPLIER else 1.0
        val threshold = RsvpSpec.Duration.LENGTH_THRESHOLD
        val lengthMultiplier = if (focusableCount > threshold)
            1.0 + minOf((focusableCount - threshold) * RsvpSpec.Duration.LENGTH_PER_CHAR_INCREMENT, RsvpSpec.Duration.LENGTH_MAX_INCREMENT)
        else 1.0
        val pauseMultiplier = if (punctuationPause && endsWithPunctuationPause(raw)) RsvpSpec.Duration.PAUSE_MULTIPLIER else 1.0
        return (base * cjkMultiplier * lengthMultiplier * pauseMultiplier).toInt()
    }

    fun estimateMinutes(wordCount: Int, wpm: Double): Double {
        val safeWpm = safeWPM(wpm)
        return wordCount / safeWpm
    }

    fun contextWindow(
        tokenCount: Int,
        currentIndex: Int,
        before: Int = 18,
        after: Int = 36,
    ): ContextWindow {
        if (tokenCount <= 0) return ContextWindow(0, 0, false, false)
        val safeBefore = before.coerceAtLeast(0)
        val safeAfter = after.coerceAtLeast(0)
        val clampedIndex = currentIndex.coerceIn(0, tokenCount - 1)
        val lower = maxOf(0, clampedIndex - safeBefore)
        val upper = minOf(tokenCount, clampedIndex + safeAfter + 1)
        return ContextWindow(lower, upper, lower > 0, upper < tokenCount)
    }

    // -- internals -----------------------------------------------------

    private fun tokenizeMixed(input: String, userDictionary: List<String>): List<String> {
        val tokens = mutableListOf<String>()
        for ((segment, isCJK) in splitByScript(input)) {
            if (isCJK) {
                tokens += tokenizeCJKSegment(segment, userDictionary)
            } else {
                tokens += segment.split(Regex("\\s+")).filter { it.isNotEmpty() }
            }
        }
        // ICU + script-split alone over-segments — names, particles, and
        // number+measure-word pairs come out as single Han chars. The
        // ChunkShaper post-pass merges those back into rhythmic 2–4 char
        // chunks that match how the eye-brain pipeline actually reads.
        // The Swift side runs the same five passes against the same
        // gold corpus (Tests/Fixtures/rsvp-gold-corpus.tsv).
        return ChunkShaper.shape(tokens)
    }

    private fun splitByScript(input: String): List<Pair<String, Boolean>> {
        val result = mutableListOf<Pair<String, Boolean>>()
        val buffer = StringBuilder()
        var bufferIsCJK: Boolean? = null
        for (ch in input) {
            val cjk = isCJKCharacter(ch) || isCJKPunctuation(ch)
            if (bufferIsCJK != null && bufferIsCJK != cjk) {
                result += buffer.toString() to bufferIsCJK!!
                buffer.setLength(0)
            }
            buffer.append(ch)
            bufferIsCJK = cjk
        }
        if (buffer.isNotEmpty() && bufferIsCJK != null) {
            result += buffer.toString() to bufferIsCJK!!
        }
        return result
    }

    private data class Span(val text: String, val lo: Int, val hi: Int)

    private fun tokenizeCJKSegment(text: String, userDictionary: List<String>): List<String> {
        // Java's BreakIterator on Android (API 24+) is ICU-backed. Apple's
        // NLTokenizer wraps the same ICU dictionary, so word boundaries
        // are effectively identical.
        val iterator = BreakIterator.getWordInstance(detectCJKLocale(text))
        iterator.setText(text)

        val raw = mutableListOf<Span>()
        var start = iterator.first()
        var end = iterator.next()
        while (end != BreakIterator.DONE) {
            val slice = text.substring(start, end)
            // BreakIterator emits whitespace-only / punctuation-only chunks
            // between word tokens. Drop them — punctuation gets glued back
            // at the end, whitespace just disappears.
            if (slice.any { isFocusable(it) || isCJKCharacter(it) }) {
                raw += Span(slice, start, end)
            }
            start = end
            end = iterator.next()
        }

        val merged = applyUserDictionary(raw, text, userDictionary)

        val tokens = mutableListOf<String>()
        // Punctuation in the gap BEFORE the first token (e.g., an opening
        // 「) buffers and prepends to the first word — same fix as the
        // Swift version, so quoted phrases keep their opening mark.
        var leadingPunct = StringBuilder()
        var lastEnd = 0
        for (span in merged) {
            if (lastEnd < span.lo) {
                val gap = text.substring(lastEnd, span.lo)
                for (ch in gap) {
                    if (!(isCJKPunctuation(ch) || isASCIIPunctuationPause(ch))) continue
                    if (tokens.isEmpty()) {
                        leadingPunct.append(ch)
                    } else {
                        tokens[tokens.lastIndex] = tokens.last() + ch
                    }
                }
            }
            if (tokens.isEmpty() && leadingPunct.isNotEmpty()) {
                tokens += leadingPunct.toString() + span.text
                leadingPunct = StringBuilder()
            } else {
                tokens += span.text
            }
            lastEnd = span.hi
        }
        if (lastEnd < text.length) {
            attachInterstitialPunctuation(text.substring(lastEnd, text.length), tokens)
        }
        return tokens
    }

    private fun attachInterstitialPunctuation(slice: String, tokens: MutableList<String>) {
        for (ch in slice) {
            if (!(isCJKPunctuation(ch) || isASCIIPunctuationPause(ch))) continue
            if (tokens.isNotEmpty()) {
                tokens[tokens.lastIndex] = tokens.last() + ch
            }
        }
    }

    private fun applyUserDictionary(
        spans: List<Span>,
        source: String,
        dictionary: List<String>,
    ): List<Span> {
        val entries = dictionary.filter { it.isNotEmpty() }.toSet()
        if (entries.isEmpty() || spans.isEmpty()) return spans
        val maxLen = entries.maxOf { it.length }

        val result = mutableListOf<Span>()
        var index = 0
        while (index < spans.size) {
            var bestEnd: Int? = null
            val concat = StringBuilder()
            var probe = index
            while (probe < spans.size) {
                concat.append(spans[probe].text)
                if (concat.length > maxLen) break
                if (entries.contains(concat.toString())) bestEnd = probe
                probe += 1
            }
            if (bestEnd != null) {
                val first = spans[index]
                val last = spans[bestEnd]
                result += Span(source.substring(first.lo, last.hi), first.lo, last.hi)
                index = bestEnd + 1
            } else {
                result += spans[index]
                index += 1
            }
        }
        return result
    }

    private fun detectCJKLocale(text: String): Locale {
        val scalars = text.codePoints().toArray()
        if (scalars.any { it in 0xAC00..0xD7AF }) return Locale.KOREAN
        if (scalars.any { it in 0x3040..0x30FF }) return Locale.JAPANESE
        return Locale.TRADITIONAL_CHINESE
    }

    private fun hasCJK(s: String): Boolean = s.any(::isCJKCharacter)

    private fun isCJKCharacter(c: Char): Boolean = RsvpSpec.cjkRanges.any { c.code in it }

    private fun isCJKPunctuation(c: Char): Boolean = RsvpSpec.cjkPunctuationRanges.any { c.code in it }

    private fun isFocusable(c: Char): Boolean {
        if (c.isLetter() || c.isDigit()) return true
        return false
    }

    private fun isASCIIPunctuationPause(c: Char): Boolean = c in RsvpSpec.asciiPause

    private fun safeWPM(wpm: Double): Double {
        val raw = if (wpm.isFinite() && wpm != 0.0) wpm else DEFAULT_WPM
        return raw.coerceIn(MINIMUM_SAFE_WPM, MAXIMUM_WPM)
    }

    private fun endsWithPunctuationPause(token: String): Boolean {
        if (token.isEmpty()) return false
        if (hasCJK(token)) {
            val last = token.last()
            return isCJKPunctuation(last) || isASCIIPunctuationPause(last)
        }
        val punctuation = RsvpSpec.latinSentenceEnd
        val trailingClosers = RsvpSpec.latinTrailingClosers
        for (i in token.indices.reversed()) {
            if (punctuation.contains(token[i])) {
                val tail = token.substring(i + 1)
                return tail.all { trailingClosers.contains(it) }
            }
            if (!trailingClosers.contains(token[i])) return false
        }
        return false
    }
}
