package com.shhtheonlyperson.fastread.spike.data

import java.io.File
import java.util.zip.ZipFile

object EpubTextExtractor {
    private val tagRegex = Regex("<[^>]+>")
    private val whitespaceRegex = Regex("\\s+")
    private val punctuationSpaceRegex = Regex("\\s+([.,!?;:，。！？；：])")

    fun extract(bytes: ByteArray): String {
        val temp = File.createTempFile("justread-", ".epub")
        return try {
            temp.writeBytes(bytes)
            ZipFile(temp).use { zip ->
                zip.entries().asSequence()
                    .filter { !it.isDirectory }
                    .filter { entry ->
                        val name = entry.name.lowercase()
                        name.endsWith(".xhtml") || name.endsWith(".html") || name.endsWith(".htm")
                    }
                    .sortedBy { it.name }
                    .joinToString("\n\n") { entry ->
                        zip.getInputStream(entry).bufferedReader().use { reader ->
                            reader.readText()
                                .replace(tagRegex, " ")
                                .replace("&nbsp;", " ")
                                .replace("&amp;", "&")
                                .replace("&lt;", "<")
                                .replace("&gt;", ">")
                                .replace("&quot;", "\"")
                                .replace("&#39;", "'")
                                .replace(whitespaceRegex, " ")
                                .replace(punctuationSpaceRegex, "$1")
                                .trim()
                        }
                    }
                    .trim()
            }
        } finally {
            temp.delete()
        }
    }
}
