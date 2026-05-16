package com.shhtheonlyperson.fastread.spike.core

data class ReaderPlaybackState(
    val index: Int,
    val tokenCount: Int,
) {
    val normalizedIndex: Int
        get() = index.coerceIn(0, (tokenCount - 1).coerceAtLeast(0))

    val isAtEnd: Boolean
        get() = tokenCount <= 0 || normalizedIndex >= tokenCount - 1

    fun nextIndex(): Int? {
        if (isAtEnd) return null
        return normalizedIndex + 1
    }
}
