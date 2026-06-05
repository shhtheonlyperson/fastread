// Direct unit tests for the ChunkShaper passes. Unlike RSVPEngineParityTest
// these feed pre-segmented token lists, so they DON'T depend on the JVM's
// non-ICU BreakIterator and run on the desktop JVM. The cases mirror the
// worked examples documented in Sources/FastReadCore/ChunkShaper.swift — the
// contract both platforms must satisfy.

package com.shhtheonlyperson.fastread.spike.core

import org.junit.Assert.assertEquals
import org.junit.Test

class ChunkShaperTest {
    private fun chars(s: String): List<String> = s.map { it.toString() }

    // k=4 peel is guarded: a verb-like 4th char peels forward...
    @Test
    fun k4RunPeelsForwardWhenFourthCharIsVerb() {
        // 黃 士 旗 去 + 吃飯 → 黃士旗 | 去吃飯
        val input = chars("黃士旗去") + "吃飯"
        assertEquals(listOf("黃士旗", "去吃飯"), ChunkShaper.shape(input))
    }

    // ...but a complement marker (得) must NOT trigger the peel.
    @Test
    fun k4RunDoesNotPeelWhenFourthCharIsNotVerb() {
        // 阿 娜 擦 得 + 發光 → 阿娜 | 擦得 | 發光 (groupSizes(4) = [2,2])
        val input = chars("阿娜擦得") + "發光"
        assertEquals(listOf("阿娜", "擦得", "發光"), ChunkShaper.shape(input))
    }

    // k=2 run keeps a name together when next is multi-CJK and neither is a
    // pronoun.
    @Test
    fun k2RunMergesNameWhenNeitherIsPronoun() {
        // 怡 婷 + 常常 → 怡婷 | 常常
        val input = chars("怡婷") + "常常"
        assertEquals(listOf("怡婷", "常常"), ChunkShaper.shape(input))
    }

    // k=2 pronoun guard keeps S + VP rhythm.
    @Test
    fun k2RunKeepsPronounSeparateBeforeMultiCjk() {
        // 我 去 + 吃飯了 → 我 | 去吃飯了 (去 absorbs forward in pass 5)
        val input = chars("我去") + "吃飯了"
        assertEquals(listOf("我", "去吃飯了"), ChunkShaper.shape(input))
    }

    // Stray-singleton backward absorption must not cross a hard clause ending.
    @Test
    fun straySingletonDoesNotAbsorbAcrossHardPunct() {
        // 說謊。 也 好 → 說謊。| 也好  (也 cannot fuse back onto 說謊。)
        val input = listOf("說謊。", "也", "好")
        val shaped = ChunkShaper.shape(input)
        assertEquals("說謊。", shaped.first())
    }
}
