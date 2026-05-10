// Replays Tests/Fixtures/parity-corpus.json against the Kotlin port of
// RSVPEngine. Same fixture the Swift ParityTests in
// Tests/FastReadCoreTests/ParityTests.swift uses, so any divergence
// between platforms shows up here as a failed assertion.

package com.shhtheonlyperson.fastread.spike.core

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Ignore
import org.junit.Test
import java.io.File

class RSVPEngineParityTest {
    private val corpusFile = File("../../Tests/Fixtures/parity-corpus.json")

    // The JVM's java.text.BreakIterator is NOT ICU-backed; only Android's
    // runtime is. So this same engine produces Swift-equivalent tokens on
    // a Pixel 8 emulator but coarser tokens on the desktop JVM. To run
    // parity here, move the test to androidTest (instrumented) — leaving
    // it Ignored on the JVM path so the rest of the build stays green.
    @Ignore("Run as androidTest — JVM BreakIterator is non-ICU")
    @Test
    fun parityCorpusMatchesKotlinEngine() {
        val data = corpusFile.readText()
        val root = JSONObject(data)
        val entries = root.getJSONArray("entries")
        var checked = 0
        for (i in 0 until entries.length()) {
            val entry = entries.getJSONObject(i)
            val id = entry.getString("id")
            val input = entry.getString("input")
            val expectedTokens = entry.getJSONArray("tokens").toStringList()
            val expectedFocus = entry.getJSONArray("focusSplits").toFocusList()
            val expectedDurations = entry.getJSONArray("durations").toIntList()
            val wpm = entry.getDouble("wpm")
            val pause = entry.getBoolean("punctuationPause")

            val tokens = RSVPEngine.tokenize(input)
            assertEquals("$id tokens", expectedTokens, tokens)

            val splits = tokens.map { RSVPEngine.splitForFocus(it) }
                .map { Triple(it.before, it.focus, it.after) }
            assertEquals("$id focusSplits", expectedFocus, splits)

            val durations = tokens.map { RSVPEngine.duration(it, wpm, pause) }
            assertEquals("$id durations", expectedDurations, durations)
            checked += 1
        }
        println("✅ parity OK across $checked entries")
    }

    private fun JSONArray.toStringList(): List<String> = (0 until length()).map { getString(it) }
    private fun JSONArray.toIntList(): List<Int> = (0 until length()).map { getInt(it) }
    private fun JSONArray.toFocusList(): List<Triple<String, String, String>> =
        (0 until length()).map {
            val o = getJSONObject(it)
            Triple(o.getString("before"), o.getString("focus"), o.getString("after"))
        }
}
