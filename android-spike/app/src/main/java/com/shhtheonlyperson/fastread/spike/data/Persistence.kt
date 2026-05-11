// Lightweight SharedPreferences wrapper. Standing in for what would be
// a DataStore-backed ReadingStore once we lift the engine into the KMP
// shared module. For the v1 testable build, we persist:
//   - last pasted article text
//   - target wpm
//   - playhead index
//   - user dictionary entries
//   - tokens (cached chunking of the article) + tokenizerVersion so we
//     can skip RSVPEngine.tokenize on relaunch when the rules haven't
//     changed underneath us
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
        set(value) {
            // When the article text changes, the cached tokens belong to
            // the previous article and must be discarded.
            val previous = prefs.getString("article", "") ?: ""
            val editor = prefs.edit().putString("article", value)
            if (previous != value) {
                editor.remove("tokens")
                editor.remove("tokenizerVersion")
            }
            editor.apply()
        }

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
        set(value) {
            // Dictionary entries influence the token boundaries the
            // engine produces, so any edit invalidates the cache.
            prefs.edit()
                .putString("dictionary", value.joinToString("\n"))
                .remove("tokens")
                .remove("tokenizerVersion")
                .apply()
        }

    // U+0001 (Start Of Heading) sits below the printable range and never
    // appears in user text — safer separator than \n, which could legitimately
    // show up inside a token in pathological inputs.
    private val tokenSeparator = ''

    var tokens: List<String>?
        get() {
            val raw = prefs.getString("tokens", null) ?: return null
            if (raw.isEmpty()) return emptyList()
            return raw.split(tokenSeparator)
        }
        set(value) {
            val editor = prefs.edit()
            if (value == null) editor.remove("tokens")
            else editor.putString("tokens", value.joinToString(tokenSeparator.toString()))
            editor.apply()
        }

    var tokenizerVersion: Int?
        get() = if (prefs.contains("tokenizerVersion")) prefs.getInt("tokenizerVersion", -1) else null
        set(value) {
            val editor = prefs.edit()
            if (value == null) editor.remove("tokenizerVersion")
            else editor.putInt("tokenizerVersion", value)
            editor.apply()
        }

    fun reset() {
        prefs.edit().clear().apply()
    }
}
