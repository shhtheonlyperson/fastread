// 1:1 Kotlin port of Sources/FastReadCore/ChunkShaper.swift. Keep the
// rule set, set membership, and ordering byte-for-byte matched with
// the iOS version — the gold corpus (Tests/Fixtures/rsvp-gold-corpus.tsv)
// is the contract both platforms must satisfy.
//
// Five passes:
//   1. mergeCrossScriptUnits     — digit + CJK measure word (5公里)
//   2. mergePrepDigitNoun        — 在 + 101 + 大樓 → 在101大樓
//   3. coalesceSingleCharRuns    — 3+ adjacent single-Han runs group
//      into 2-3 char clusters; k=2 merges when next is non-multi-CJK;
//      pronoun-in-run / k=4 + multi-char next triggers peel-forward
//   4. glueFunctionParticles     — 的 shorter-side, 了/著/過/之/etc.
//      backward, 在/從/對/是 forward (only into multi-char)
//   5. absorbStraySingletons     — leftover 1-Han chunks: backward cap
//      3, forward cap 4, only into multi-char neighbours

package com.shhtheonlyperson.fastread.spike.core

object ChunkShaper {
    fun shape(tokens: List<String>): List<String> {
        var result = mergeCrossScriptUnits(tokens)
        result = mergePrepDigitNoun(result)
        result = coalesceSingleCharRuns(result)
        result = glueFunctionParticles(result)
        result = absorbStraySingletons(result)
        return result
    }

    private const val MAX_MERGED_CJK = 4

    // ---- Pass 1: cross-script number + measure word -----------------

    private val measureWords = setOf(
        "個", "位", "件", "種", "名", "次", "回", "張", "把", "條", "場", "份",
        "年", "月", "日", "時", "分", "秒", "週", "季", "點", "天",
        "小時", "分鐘", "秒鐘",
        "公斤", "公克", "公尺", "公里", "公分", "公升",
        "元", "塊", "毛", "億", "萬",
        "度",
        "個月", "個人", "歲",
    )

    private fun mergeCrossScriptUnits(tokens: List<String>): List<String> {
        val result = mutableListOf<String>()
        var i = 0
        while (i < tokens.size) {
            val cur = tokens[i]
            if (isDigitRun(cur) && i + 1 < tokens.size && tokens[i + 1] in measureWords) {
                result += cur + tokens[i + 1]
                i += 2
                continue
            }
            result += cur
            i += 1
        }
        return result
    }

    private fun isDigitRun(s: String): Boolean {
        if (s.isEmpty()) return false
        for (c in s) {
            if (!c.isAscii) return false
            if (c.isDigit() || c == '.' || c == ',') continue
            return false
        }
        return true
    }

    private val Char.isAscii: Boolean get() = code in 0..127

    // ---- Pass 2: preposition + digit + Han noun ---------------------

    private val prepositionsForCompound = setOf('在', '從', '到', '向', '於')

    private fun mergePrepDigitNoun(tokens: List<String>): List<String> {
        val result = mutableListOf<String>()
        var i = 0
        while (i < tokens.size) {
            val cur = tokens[i]
            if (cur.length == 1
                && cur.first() in prepositionsForCompound
                && i + 2 < tokens.size
                && isDigitRun(tokens[i + 1])
                && cjkCount(tokens[i + 2]) >= 2
            ) {
                result += cur + tokens[i + 1] + tokens[i + 2]
                i += 3
                continue
            }
            result += cur
            i += 1
        }
        return result
    }

    // ---- Pass 3: single-Han run coalesce ----------------------------

    private val pronouns = setOf('我', '你', '他', '她', '它', '您', '咱')

    private fun coalesceSingleCharRuns(tokens: List<String>): List<String> {
        val result = mutableListOf<String>()
        var i = 0
        while (i < tokens.size) {
            var j = i
            while (j < tokens.size
                && isPureSingleHan(tokens[j])
                && !isAnyParticle(tokens[j])
            ) {
                j += 1
            }
            val runLen = j - i
            if (runLen >= 3) {
                val nextHasRoom = j < tokens.size
                    && cjkCount(tokens[j]) > 0
                    && cjkCount(tokens[j]) <= 2
                val runHasPronoun = (i until j).any {
                    tokens[it].firstOrNull() in pronouns
                }

                if (runLen == 3 && runHasPronoun && nextHasRoom) {
                    result += tokens.subList(i, i + 2).joinToString("")
                    result += tokens[i + 2] + tokens[j]
                    i = j + 1
                    continue
                }
                if (runLen == 4 && nextHasRoom) {
                    result += tokens.subList(i, i + 3).joinToString("")
                    result += tokens[i + 3] + tokens[j]
                    i = j + 1
                    continue
                }
                if (runLen == 5 && nextHasRoom && cjkCount(tokens[j]) == 1) {
                    result += tokens.subList(i, i + 3).joinToString("")
                    result += tokens[i + 3] + tokens[i + 4] + tokens[j]
                    i = j + 1
                    continue
                }

                var offset = i
                for (size in groupSizes(runLen)) {
                    result += tokens.subList(offset, offset + size).joinToString("")
                    offset += size
                }
                i = j
            } else if (runLen == 2) {
                val nextNotMultiCJK = j >= tokens.size || cjkCount(tokens[j]) < 2
                if (nextNotMultiCJK) {
                    result += tokens.subList(i, j).joinToString("")
                    i = j
                } else {
                    result += tokens[i]
                    i += 1
                }
            } else {
                result += tokens[i]
                i += 1
            }
        }
        return result
    }

    private fun groupSizes(n: Int): List<Int> = when (n) {
        0 -> emptyList()
        1 -> listOf(1)
        2 -> listOf(1, 1)
        3 -> listOf(3)
        4 -> listOf(2, 2)
        5 -> listOf(2, 3)
        6 -> listOf(3, 3)
        7 -> listOf(3, 2, 2)
        8 -> listOf(3, 3, 2)
        9 -> listOf(3, 3, 3)
        else -> {
            val sizes = mutableListOf<Int>()
            var remaining = n
            while (remaining > 4) {
                sizes += 3
                remaining -= 3
            }
            sizes += groupSizes(remaining)
            sizes
        }
    }

    // ---- Pass 4: particle gluing ------------------------------------

    private val particlesBackward = setOf(
        '了', '著', '過',
        '之', '矣', '哉', '焉', '乎', '而',
        '嗎', '呢', '吧', '啊', '喔', '耶', '呀', '嘛', '呵',
    )

    private val particlesForward = setOf(
        '在', '從', '對', '向', '把', '被', '給',
        '及', '或',
        '是', '為',
        '也', '又', '都', '還', '才', '就', '便',
        '很', '更', '最', '太',
        '不', '沒', '未', '別',
        '新', '舊',
    )

    private const val POSSESSIVE_DE = '的'

    private fun glueFunctionParticles(tokens: List<String>): List<String> {
        val result = mutableListOf<String>()
        var i = 0
        while (i < tokens.size) {
            val cur = tokens[i]
            val particle = singleCJKParticle(cur)
            if (particle != null) {
                val leftLen = cjkCount(result.lastOrNull() ?: "")
                val rightLen = if (i + 1 < tokens.size) cjkCount(tokens[i + 1]) else 0

                if (particle == POSSESSIVE_DE) {
                    val preferBackward = leftLen in 1..rightLen
                    if (preferBackward && leftLen + 1 <= MAX_MERGED_CJK) {
                        result[result.lastIndex] = result.last() + cur
                        i += 1
                        continue
                    }
                    if (rightLen >= 1 && rightLen + 1 <= MAX_MERGED_CJK) {
                        result += cur + tokens[i + 1]
                        i += 2
                        continue
                    }
                    if (leftLen >= 1 && leftLen + 1 <= MAX_MERGED_CJK) {
                        result[result.lastIndex] = result.last() + cur
                        i += 1
                        continue
                    }
                    result += cur
                    i += 1
                    continue
                }

                if (particle in particlesBackward
                    && leftLen >= 1
                    && leftLen + 1 <= MAX_MERGED_CJK
                ) {
                    result[result.lastIndex] = result.last() + cur
                    i += 1
                    continue
                }
                if (particle in particlesForward
                    && rightLen >= 2
                    && rightLen + 1 <= MAX_MERGED_CJK
                ) {
                    result += cur + tokens[i + 1]
                    i += 2
                    continue
                }
            }
            result += cur
            i += 1
        }
        return result
    }

    private fun singleCJKParticle(chunk: String): Char? {
        val cjk = chunk.filter(::isHanCharacter)
        return if (cjk.length == 1) cjk.first() else null
    }

    // ---- Pass 5: absorb stray singletons -----------------------------

    private fun absorbStraySingletons(tokens: List<String>): List<String> {
        val result = mutableListOf<String>()
        var i = 0
        while (i < tokens.size) {
            val cur = tokens[i]
            if (cur.length != 1 || !cur.all(::isHanCharacter)) {
                result += cur
                i += 1
                continue
            }
            // Backward into multi-char prev (cap 3).
            val last = result.lastOrNull()
            if (last != null && cjkCount(last) >= 2 && cjkCount(last) + 1 <= 3) {
                result[result.lastIndex] = last + cur
                i += 1
                continue
            }
            // Forward into multi-char next (cap 4).
            if (i + 1 < tokens.size
                && cjkCount(tokens[i + 1]) >= 2
                && cjkCount(tokens[i + 1]) + 1 <= 4
            ) {
                result += cur + tokens[i + 1]
                i += 2
                continue
            }
            result += cur
            i += 1
        }
        return result
    }

    // ---- helpers -----------------------------------------------------

    private fun isPureSingleHan(chunk: String): Boolean =
        chunk.length == 1 && chunk.all(::isHanCharacter)

    private fun isAnyParticle(chunk: String): Boolean {
        if (chunk.length != 1) return false
        val c = chunk.first()
        return c == POSSESSIVE_DE
            || c in particlesForward
            || c in particlesBackward
    }

    private fun cjkCount(chunk: String): Int = chunk.count(::isHanCharacter)

    private fun isHanCharacter(c: Char): Boolean {
        val v = c.code
        return (v in 0x3400..0x4dbf)
            || (v in 0x4e00..0x9fff)
            || (v in 0xf900..0xfaff)
    }
}
