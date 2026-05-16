package com.shhtheonlyperson.fastread.spike.data

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class EpubTextExtractorTest {
    @Test
    fun extractsReadableTextFromHtmlEntriesInOrder() {
        val epub = zipBytes(
            "OEBPS/chapter2.xhtml" to "<h1>Second&nbsp;Chapter</h1><p>Keep &amp; read.</p>",
            "OEBPS/chapter1.xhtml" to "<p>First <strong>chapter</strong>.</p>",
            "OEBPS/image.png" to "not text",
        )

        assertEquals(
            "First chapter.\n\nSecond Chapter Keep & read.",
            EpubTextExtractor.extract(epub),
        )
    }

    private fun zipBytes(vararg entries: Pair<String, String>): ByteArray {
        val output = ByteArrayOutputStream()
        ZipOutputStream(output).use { zip ->
            entries.forEach { (path, text) ->
                zip.putNextEntry(ZipEntry(path))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
        }
        return output.toByteArray()
    }
}
