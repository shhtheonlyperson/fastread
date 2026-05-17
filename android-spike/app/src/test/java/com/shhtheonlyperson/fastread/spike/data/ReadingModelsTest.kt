package com.shhtheonlyperson.fastread.spike.data

import org.junit.Assert.assertEquals
import org.junit.Test

class ReadingModelsTest {
    @Test
    fun articleJsonRoundTripsTokensAndReleaseMetadata() {
        val article = ReadingArticle(
            id = "a1",
            title = "Title",
            source = "example.com",
            sourceUrl = "https://example.com/a",
            author = "Web",
            date = "May 17, 2026",
            createdAt = 1_000,
            lastOpenedAt = 2_000,
            finishedAt = null,
            readTime = "3 min",
            lede = "lede",
            tag = "Reading now",
            text = "Hello world",
            progress = 0.5,
            wordIndex = 1,
            timesOpened = 2,
            isFinished = false,
            tokens = listOf("Hello", "world"),
            tokenizerVersion = 1,
        )

        assertEquals(article, ReadingArticle.fromJson(article.toJson()))
    }

    @Test
    fun statsJsonRoundTripsWeekTotals() {
        val stats = ReadingStats(
            today = TodayStats(words = 10, minutes = 1, articles = 1),
            week = listOf(DayWords(date = "2026-05-17", day = "Sun", words = 10)),
            streak = 3,
            avgWPM = 550,
            bestWPM = 650,
            totalArticles = 7,
            lastActiveDay = "2026-05-17",
        )

        val roundTrip = ReadingStats.fromJson(stats.toJson())
        assertEquals(10, roundTrip.weekTotal)
        assertEquals(stats, roundTrip)
    }
}
