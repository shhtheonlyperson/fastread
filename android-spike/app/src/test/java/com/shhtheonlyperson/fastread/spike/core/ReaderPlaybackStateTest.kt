package com.shhtheonlyperson.fastread.spike.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderPlaybackStateTest {
    @Test
    fun normalizesIndexIntoTokenRange() {
        assertEquals(0, ReaderPlaybackState(index = -3, tokenCount = 4).normalizedIndex)
        assertEquals(3, ReaderPlaybackState(index = 9, tokenCount = 4).normalizedIndex)
        assertEquals(0, ReaderPlaybackState(index = 9, tokenCount = 0).normalizedIndex)
    }

    @Test
    fun nextIndexStopsAtEnd() {
        assertEquals(1, ReaderPlaybackState(index = 0, tokenCount = 3).nextIndex())
        assertNull(ReaderPlaybackState(index = 2, tokenCount = 3).nextIndex())
        assertNull(ReaderPlaybackState(index = 0, tokenCount = 0).nextIndex())
    }

    @Test
    fun atEndUsesNormalizedIndex() {
        assertFalse(ReaderPlaybackState(index = -1, tokenCount = 3).isAtEnd)
        assertTrue(ReaderPlaybackState(index = 99, tokenCount = 3).isAtEnd)
    }
}
