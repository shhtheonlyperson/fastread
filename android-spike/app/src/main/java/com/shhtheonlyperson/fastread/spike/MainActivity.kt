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
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.data.ArticleFetcher
import com.shhtheonlyperson.fastread.spike.data.FetchException
import com.shhtheonlyperson.fastread.spike.data.Persistence
import com.shhtheonlyperson.fastread.spike.data.SourceInputClassifier
import com.shhtheonlyperson.fastread.spike.data.displayName
import com.shhtheonlyperson.fastread.spike.data.findLocalEpubFiles
import com.shhtheonlyperson.fastread.spike.data.EpubTextExtractor
import com.shhtheonlyperson.fastread.spike.ui.JRColor
import com.shhtheonlyperson.fastread.spike.ui.JRFont
import com.shhtheonlyperson.fastread.spike.ui.LibraryScreen
import com.shhtheonlyperson.fastread.spike.ui.PasteScreen
import com.shhtheonlyperson.fastread.spike.ui.ReaderScreen
import com.shhtheonlyperson.fastread.spike.ui.SettingsScreen
import com.shhtheonlyperson.fastread.spike.ui.StatsScreen
import kotlinx.coroutines.launch

private const val DEFAULT_SAMPLE = """黃士旗去吃飯與星巴克碰面。中華民國總統蔡英文今天宣布，可口可樂與百事可樂的競爭依然激烈。Apple 在 2025 年發表新 MacBook Pro，價格 1999 美元起。我用 VS Code 寫 iOS app，效率提升 30%。今天氣溫 25°C 大約華氏 77°F，成長率達 12.5% 創新高。可參考 RFC-7231 (HTTP/1.1)。Dr. Smith 在 NTU 教 AI 課程，他說「Hello, world」就走了。重量 100 公斤、長度 3 公尺。詳情請見 https://example.com/docs 頁面。張三、李四和王五一起去陽明山健行，海拔 1120 公尺。快速閱讀，眼睛更輕鬆。"""

private enum class Screen(val label: String) {
    Library("Library"),
    Add("Add"),
    Reader("Read"),
    Stats("Stats"),
    Settings("Settings"),
}

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
    val scope = rememberCoroutineScope()
    var screen by remember { mutableStateOf(if (autoSweepSeconds != null) Screen.Reader else Screen.Library) }
    var sourceInput by remember { mutableStateOf("") }
    var sourceStatus by remember { mutableStateOf("") }
    var isLoading by remember { mutableStateOf(false) }
    var localEpubs by remember { mutableStateOf(findLocalEpubFiles(context)) }
    val activity = context.findActivity()

    LaunchedEffect(Unit) {
        if (autoSweepSeconds != null && store.articles.isEmpty()) {
            store.addTextArticle(DEFAULT_SAMPLE, title = "Performance sample", source = "Sweep")
        }
    }

    LaunchedEffect(screen) {
        activity?.requestedOrientation = when (screen) {
            Screen.Reader -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
            else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
    }

    fun openReaderForCurrent() {
        screen = if (store.currentArticle == null) Screen.Add else Screen.Reader
    }

    fun submitSource() {
        val input = sourceInput.trim()
        if (input.isBlank()) {
            sourceStatus = "Nothing to add."
            return
        }
        isLoading = true
        sourceStatus = if (SourceInputClassifier.isLikelySingleUrl(input)) "Fetching URL." else "Loading text."
        scope.launch {
            if (SourceInputClassifier.isLikelySingleUrl(input)) {
                val result = ArticleFetcher.fetch(input)
                result.onSuccess { fetched ->
                    if (fetched.wordCount < 20) {
                        sourceStatus = "Could not find enough readable text on that page."
                    } else {
                        store.addFetchedArticle(fetched)
                        sourceInput = ""
                        sourceStatus = "Loaded · ${fetched.wordCount} words"
                        screen = Screen.Reader
                    }
                }.onFailure { error ->
                    sourceStatus = (error as? FetchException)?.message ?: "Could not fetch that URL."
                }
            } else {
                val article = store.addTextArticle(input)
                if (article == null) {
                    sourceStatus = "Could not read that text."
                } else {
                    sourceInput = ""
                    sourceStatus = "Loaded · ${store.wordCount(article)} words"
                    screen = Screen.Reader
                }
            }
            isLoading = false
        }
    }

    val epubPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val name = context.displayName(uri) ?: "EPUB"
        isLoading = true
        sourceStatus = "Loading EPUB."
        scope.launch {
            runCatching {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    EpubTextExtractor.extract(input.readBytes())
                }.orEmpty()
            }.onSuccess { text ->
                val article = store.addEpubArticle(name, text)
                if (article == null) {
                    sourceStatus = "Could not read that EPUB."
                } else {
                    sourceStatus = "Loaded · ${store.wordCount(article)} words"
                    localEpubs = findLocalEpubFiles(context)
                    screen = Screen.Reader
                }
            }.onFailure {
                sourceStatus = "Could not read that EPUB."
            }
            isLoading = false
        }
    }

    Box(Modifier.fillMaxSize().background(JRColor.paper)) {
        when (screen) {
            Screen.Library -> LibraryScreen(
                store = store,
                onResume = {
                    store.currentArticle?.let { store.openArticle(it.id, resume = true) }
                    openReaderForCurrent()
                },
                onOpenArticle = { article ->
                    store.openArticle(article.id, resume = article.progress > 0)
                    screen = Screen.Reader
                },
                onDeleteArticle = { store.deleteArticle(it.id) },
            )

            Screen.Add -> PasteScreen(
                input = sourceInput,
                onInputChange = { sourceInput = it },
                onSubmit = ::submitSource,
                isLoading = isLoading,
                status = sourceStatus,
                recentSources = store.recentSources,
                onRecentSource = { source ->
                    source.url?.let {
                        sourceInput = it
                        submitSource()
                    }
                },
                localEpubs = localEpubs,
                onRefreshLocalEpubs = { localEpubs = findLocalEpubFiles(context) },
                onPickEpub = {
                    localEpubs = findLocalEpubFiles(context)
                    epubPicker.launch(arrayOf("application/epub+zip", "application/octet-stream", "*/*"))
                },
                onImportLocalEpub = { file ->
                    isLoading = true
                    sourceStatus = "Loading EPUB."
                    scope.launch {
                        runCatching {
                            EpubTextExtractor.extract(file.file.readBytes())
                        }.onSuccess { text ->
                            val article = store.addEpubArticle(file.displayName, text)
                            if (article == null) {
                                sourceStatus = "Could not read that EPUB."
                            } else {
                                sourceStatus = "Loaded · ${store.wordCount(article)} words"
                                localEpubs = findLocalEpubFiles(context)
                                screen = Screen.Reader
                            }
                        }.onFailure {
                            sourceStatus = "Could not read that EPUB."
                        }
                        isLoading = false
                    }
                },
            )

            Screen.Reader -> ReaderScreen(
                article = store.currentArticle,
                store = store,
                onBack = { screen = Screen.Library },
                autoSweepSeconds = autoSweepSeconds,
            )

            Screen.Stats -> StatsScreen(stats = store.stats, currentWpm = store.wpm)

            Screen.Settings -> SettingsScreen(
                wpm = store.wpm,
                minimumWpm = store.currentMinimumWpm,
                punctuationPause = store.punctuationPause,
                focusIndicator = store.focusIndicator,
                dictionary = store.dictionary,
                appVersion = context.appVersionName(),
                onWpmChange = store::setWPM,
                onPunctuationPauseChange = store::updatePunctuationPause,
                onFocusIndicatorChange = store::updateFocusIndicator,
                onAdd = store::addToUserDictionary,
                onRemove = store::removeFromUserDictionary,
            )
        }

        if (screen != Screen.Reader || store.currentArticle == null) {
            BottomTabs(
                selected = screen,
                modifier = Modifier.align(Alignment.BottomCenter),
                onSelect = { next ->
                    screen = if (next == Screen.Reader && store.currentArticle == null) Screen.Add else next
                },
            )
        }
    }
}

@Composable
private fun BottomTabs(selected: Screen, modifier: Modifier = Modifier, onSelect: (Screen) -> Unit) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(JRColor.paper)
            .padding(horizontal = 12.dp)
            .padding(top = 10.dp, bottom = 28.dp)
            .testTag("bottom-tabs"),
        horizontalArrangement = Arrangement.SpaceAround,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Screen.entries.forEach { screen ->
            Column(
                modifier = Modifier
                    .weight(1f)
                    .clickable { onSelect(screen) }
                    .padding(vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Text(
                    glyph(screen),
                    color = if (screen == selected) JRColor.terracotta else JRColor.inkQuiet,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    screen.label.uppercase(),
                    color = if (screen == selected) JRColor.terracotta else JRColor.inkQuiet,
                    fontSize = 10.sp,
                    fontFamily = JRFont.mono,
                    letterSpacing = 0.6.sp,
                )
            }
        }
    }
}

private fun glyph(screen: Screen): String = when (screen) {
    Screen.Library -> "⌂"
    Screen.Add -> "+"
    Screen.Reader -> "▶"
    Screen.Stats -> "▥"
    Screen.Settings -> "⚙"
}

private fun Context.appVersionName(): String =
    runCatching { packageManager.getPackageInfo(packageName, 0).versionName ?: "0.2.3" }
        .getOrDefault("0.2.3")

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
