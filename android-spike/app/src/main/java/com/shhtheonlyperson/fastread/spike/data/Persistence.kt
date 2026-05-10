// Lightweight SharedPreferences wrapper. Standing in for what would be
// a DataStore-backed ReadingStore once we lift the engine into the KMP
// shared module. For the v1 testable build, all we persist is:
//   - last pasted article text
//   - target wpm
//   - playhead index
//   - user dictionary entries
// Anything more (full library, stats, focus indicator) waits until the
// real port.

package com.shhtheonlyperson.fastread.spike.data

import android.content.Context
import android.content.SharedPreferences

class Persistence(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("justread_v1", Context.MODE_PRIVATE)

    var article: String
        get() = prefs.getString("article", "") ?: ""
        set(value) = prefs.edit().putString("article", value).apply()

    var wpm: Int
        get() = prefs.getInt("wpm", 450)
        set(value) = prefs.edit().putInt("wpm", value).apply()

    var index: Int
        get() = prefs.getInt("index", 0)
        set(value) = prefs.edit().putInt("index", value).apply()

    // Newline-separated. Dictionary entries are short noun phrases — a
    // raw newline character won't appear inside one in practice, and
    // SharedPreferences doesn't support set/list types portably.
    var dictionary: List<String>
        get() = prefs.getString("dictionary", "")
            ?.split('\n')
            ?.filter { it.isNotEmpty() }
            ?: emptyList()
        set(value) = prefs.edit().putString("dictionary", value.joinToString("\n")).apply()

    fun reset() {
        prefs.edit().clear().apply()
    }
}
