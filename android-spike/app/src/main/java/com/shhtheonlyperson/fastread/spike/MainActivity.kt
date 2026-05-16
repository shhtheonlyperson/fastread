// JustRead Android v0.1 — minimum viable RSVP reader for Play Console
// internal testing. MainActivity owns app-level routing and launchers;
// screen UI, persistence, and EPUB import live in dedicated modules.

package com.shhtheonlyperson.fastread.spike

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.shhtheonlyperson.fastread.spike.data.EpubTextExtractor
import com.shhtheonlyperson.fastread.spike.data.Persistence
import com.shhtheonlyperson.fastread.spike.data.displayName
import com.shhtheonlyperson.fastread.spike.data.findLocalEpubFiles
import com.shhtheonlyperson.fastread.spike.ui.JRColor
import com.shhtheonlyperson.fastread.spike.ui.PasteScreen
import com.shhtheonlyperson.fastread.spike.ui.ReaderScreen
import com.shhtheonlyperson.fastread.spike.ui.SettingsScreen

// Used by the auto-sweep mode and as a default if the user has nothing
// pasted yet. Gives them something to read on first launch.
private const val DEFAULT_SAMPLE = """黃士旗去吃飯與星巴克碰面。中華民國總統蔡英文今天宣布，可口可樂與百事可樂的競爭依然激烈。Apple 在 2025 年發表新 MacBook Pro，價格 1999 美元起。我用 VS Code 寫 iOS app，效率提升 30%。今天氣溫 25°C 大約華氏 77°F，成長率達 12.5% 創新高。可參考 RFC-7231 (HTTP/1.1)。Dr. Smith 在 NTU 教 AI 課程，他說「Hello, world」就走了。重量 100 公斤、長度 3 公尺。詳情請見 https://example.com/docs 頁面。張三、李四和王五一起去陽明山健行，海拔 1120 公尺。快速閱讀，眼睛更輕鬆。"""

private enum class Screen { Paste, Reader, Settings }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sweepSeconds = intent.getIntExtra("sweep_seconds", 0).takeIf { it > 0 }
        setContent {
            Surface(modifier = Modifier.fillMaxSize(), color = JRColor.paper) {
                JustReadApp(autoSweepSeconds = sweepSeconds)
            }
        }
    }
}

@Composable
private fun JustReadApp(autoSweepSeconds: Int? = null) {
    val context = LocalContext.current
    val store = remember { Persistence(context) }
    var screen by remember { mutableStateOf(if (autoSweepSeconds != null) Screen.Reader else Screen.Paste) }
    var article by remember { mutableStateOf(store.article.ifEmpty { DEFAULT_SAMPLE }) }
    var wpm by remember { mutableIntStateOf(store.wpm) }
    var index by remember { mutableIntStateOf(store.index) }
    var importStatus by remember { mutableStateOf("") }
    var localEpubs by remember { mutableStateOf(findLocalEpubFiles(context)) }
    val dictionary = remember { store.dictionary.toMutableStateList() }
    val activity = context.findActivity()

    LaunchedEffect(screen) {
        activity?.requestedOrientation = when (screen) {
            Screen.Reader -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
            Screen.Paste, Screen.Settings -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    fun loadArticleFromEpub(name: String, text: String) {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) {
            importStatus = "Could not read that EPUB."
            return
        }
        article = trimmed
        store.article = trimmed
        index = 0
        store.index = 0
        importStatus = "Loaded $name"
        screen = Screen.Reader
    }

    val epubPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val name = context.displayName(uri) ?: "EPUB"
        runCatching {
            context.contentResolver.openInputStream(uri)?.use { input ->
                EpubTextExtractor.extract(input.readBytes())
            }.orEmpty()
        }.onSuccess { text ->
            loadArticleFromEpub(name, text)
        }.onFailure {
            importStatus = "Could not read that EPUB."
        }
    }

    when (screen) {
        Screen.Paste -> PasteScreen(
            article = article,
            onArticleChange = { article = it },
            onRead = {
                val previous = store.article
                store.article = article
                if (previous != article) {
                    index = 0
                    store.index = 0
                }
                screen = Screen.Reader
            },
            onSettings = { screen = Screen.Settings },
            status = importStatus,
            localEpubs = localEpubs,
            onRefreshLocalEpubs = { localEpubs = findLocalEpubFiles(context) },
            onPickEpub = {
                localEpubs = findLocalEpubFiles(context)
                epubPicker.launch(arrayOf("application/epub+zip", "application/octet-stream", "*/*"))
            },
            onImportLocalEpub = { file ->
                runCatching {
                    EpubTextExtractor.extract(file.file.readBytes())
                }.onSuccess { text ->
                    loadArticleFromEpub(file.displayName, text)
                    localEpubs = findLocalEpubFiles(context)
                }.onFailure {
                    importStatus = "Could not read that EPUB."
                }
            },
        )
        Screen.Reader -> ReaderScreen(
            article = article,
            initialWpm = wpm,
            initialIndex = index,
            dictionary = dictionary,
            store = store,
            onWpmChange = { wpm = it; store.wpm = it },
            onIndexChange = { index = it; store.index = it },
            onBack = { screen = Screen.Paste },
            autoSweepSeconds = autoSweepSeconds,
        )
        Screen.Settings -> SettingsScreen(
            dictionary = dictionary,
            onAdd = { entry ->
                val trimmed = entry.trim()
                if (trimmed.isNotEmpty() && !dictionary.contains(trimmed)) {
                    dictionary.add(trimmed)
                    store.dictionary = dictionary.toList()
                }
            },
            onRemove = {
                dictionary.remove(it)
                store.dictionary = dictionary.toList()
            },
            onBack = { screen = Screen.Paste },
        )
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
