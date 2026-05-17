package com.shhtheonlyperson.fastread.spike.data

object ArticleTextExtractor {
    private val scriptBlockRegex = Regex("<(script|style|noscript|svg)\\b[\\s\\S]*?</\\1>", RegexOption.IGNORE_CASE)
    private val hiddenBlockRegex = Regex("<(nav|footer|aside|form|button)\\b[\\s\\S]*?</\\1>", RegexOption.IGNORE_CASE)
    private val blockTagRegex = Regex("</?(article|section|main|div|p|br|h[1-6]|li|blockquote|pre|tr|td|th)\\b[^>]*>", RegexOption.IGNORE_CASE)
    private val tagRegex = Regex("<[^>]+>")
    private val whitespaceRegex = Regex("[ \\t\\x0B\\f\\r]+")
    private val blankLineRegex = Regex("\\n{3,}")
    private val titleRegex = Regex("<title\\b[^>]*>([\\s\\S]*?)</title>", RegexOption.IGNORE_CASE)
    private val numericEntityRegex = Regex("&#(x?[0-9A-Fa-f]+);")

    fun readableText(input: String): String {
        val body = input
            .replace(scriptBlockRegex, " ")
            .replace(hiddenBlockRegex, " ")
            .replace(blockTagRegex, "\n")
            .replace(tagRegex, " ")
        return normalize(decodeEntities(body))
    }

    fun extractTitle(input: String): String? {
        val match = titleRegex.find(input) ?: return null
        return normalize(decodeEntities(match.groupValues[1])).takeIf { it.isNotBlank() }
    }

    fun normalize(input: String): String = input
        .replace('\u00A0', ' ')
        .replace('\u3000', ' ')
        .lineSequence()
        .map { it.replace(whitespaceRegex, " ").trim() }
        .filter { it.isNotEmpty() }
        .joinToString("\n")
        .replace(blankLineRegex, "\n\n")
        .trim()

    fun makeLede(text: String, tokens: List<String>): String {
        val limit = if (containsCJK(text)) 42 else 18
        val selected = tokens.take(limit)
        return if (containsCJK(text)) selected.joinToString("") else selected.joinToString(" ")
    }

    fun containsCJK(text: String): Boolean = text.any { ch ->
        val code = ch.code
        code in 0x3040..0x30ff ||
            code in 0x3400..0x4dbf ||
            code in 0x4e00..0x9fff ||
            code in 0xf900..0xfaff ||
            code in 0xac00..0xd7af
    }

    private fun decodeEntities(input: String): String {
        val named = input
            .replace("&nbsp;", " ")
            .replace("&amp;", "&")
            .replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&#39;", "'")
            .replace("&apos;", "'")
        return numericEntityRegex.replace(named) { match ->
            val raw = match.groupValues[1]
            val code = if (raw.startsWith("x", ignoreCase = true)) {
                raw.drop(1).toIntOrNull(16)
            } else {
                raw.toIntOrNull()
            }
            code?.takeIf { Character.isValidCodePoint(it) }?.let {
                String(Character.toChars(it))
            } ?: match.value
        }
    }
}
