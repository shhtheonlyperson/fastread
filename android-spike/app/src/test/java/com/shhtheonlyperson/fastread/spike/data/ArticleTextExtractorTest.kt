package com.shhtheonlyperson.fastread.spike.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ArticleTextExtractorTest {
    @Test
    fun extractsReadableArticleTextAndTitle() {
        val html = """
            <html>
              <head><title>JustRead Test</title><style>.x{display:none}</style></head>
              <body>
                <nav>Skip me</nav>
                <article>
                  <h1>Headline</h1>
                  <p>First&nbsp;paragraph &amp; value.</p>
                  <p>第二段文字。</p>
                </article>
              </body>
            </html>
        """.trimIndent()

        assertEquals("JustRead Test", ArticleTextExtractor.extractTitle(html))
        val text = ArticleTextExtractor.readableText(html)
        assertTrue(text.contains("Headline"))
        assertTrue(text.contains("First paragraph & value."))
        assertTrue(text.contains("第二段文字。"))
        assertTrue(!text.contains("Skip me"))
    }
}
