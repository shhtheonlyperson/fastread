// JustRead Android v0.1 — minimum viable RSVP reader for Play Console
// internal testing. Three screens: Paste (textarea + Read), Reader
// (current token + pace + pause/play + back), Settings (user dictionary
// editor). Auto-sweep mode preserved for performance verification when
// launched with `--ei sweep_seconds N`.
//
// Visuals follow design_handoff_justread/README.md (cream paper bg,
// terracotta focus letter, Fraunces serif word stage, Inter sans
// chrome). Persistence is SharedPreferences for v1 — DataStore +
// proper KMP layout comes with the full Path A migration.

package com.shhtheonlyperson.fastread.spike

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.toMutableStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.core.RSVPEngine
import com.shhtheonlyperson.fastread.spike.data.Persistence
import com.shhtheonlyperson.fastread.spike.ui.FocusIndicatorStyle
import com.shhtheonlyperson.fastread.spike.ui.JRColor
import com.shhtheonlyperson.fastread.spike.ui.JRFont
import com.shhtheonlyperson.fastread.spike.ui.RSVPStage
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.util.zip.ZipFile
import kotlin.math.abs

private const val TAG = "FastReadSpike"

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
                store.article = article
                if (store.article != article) {
                    // text changed — start over
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

// ---- Paste screen ---------------------------------------------------

@Composable
private fun PasteScreen(
    article: String,
    onArticleChange: (String) -> Unit,
    onRead: () -> Unit,
    onSettings: () -> Unit,
    status: String,
    localEpubs: List<LocalEpubFile>,
    onRefreshLocalEpubs: () -> Unit,
    onPickEpub: () -> Unit,
    onImportLocalEpub: (LocalEpubFile) -> Unit,
) {
    LaunchedEffect(Unit) {
        onRefreshLocalEpubs()
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(top = 60.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        SectionLabel("JUSTREAD")
        Text(
            "Capture\nyour next read.",
            color = JRColor.ink,
            fontSize = 30.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = JRFont.serif,
            lineHeight = 34.sp,
        )

        SectionLabel("PASTE TEXT")
        BasicTextField(
            value = article,
            onValueChange = onArticleChange,
            modifier = Modifier
                .fillMaxWidth()
                .height(280.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong)
                .padding(14.dp)
                .testTag("paste-text-field"),
            textStyle = TextStyle(
                color = JRColor.ink,
                fontSize = 16.sp,
                fontFamily = JRFont.serif,
                lineHeight = 22.sp,
            ),
            cursorBrush = SolidColor(JRColor.terracotta),
        )

        SectionLabel("EPUB BOOK")
        SecondaryButton(label = "Pick EPUB", onTap = onPickEpub, testTag = "pick-epub-button")

        if (status.isNotBlank()) {
            Text(
                status.uppercase(),
                color = JRColor.inkQuiet,
                fontSize = 11.sp,
                fontFamily = JRFont.mono,
                letterSpacing = 0.66.sp,
            )
        }

        if (localEpubs.isNotEmpty()) {
            SectionLabel("FILES FOLDER")
            localEpubs.forEach { file ->
                LocalEpubButton(file = file, onTap = { onImportLocalEpub(file) })
            }
        }

        PrimaryButton(label = "READ", onTap = onRead, testTag = "read-button")
        SecondaryButton(label = "Custom words", onTap = onSettings, testTag = "settings-button")
        Spacer(Modifier.height(48.dp))
    }
}

// ---- Reader screen --------------------------------------------------

@Composable
private fun ReaderScreen(
    article: String,
    initialWpm: Int,
    initialIndex: Int,
    dictionary: List<String>,
    store: Persistence,
    onWpmChange: (Int) -> Unit,
    onIndexChange: (Int) -> Unit,
    onBack: () -> Unit,
    autoSweepSeconds: Int? = null,
) {
    val tokens = remember(article, dictionary.toList()) {
        // Fast path: SharedPreferences carries tokens from a previous
        // launch, and the tokenizer version still matches. Persistence
        // already wiped the cache when the article or dictionary
        // changed, so a hit here is safe to trust.
        val cached = store.tokens
        if (cached != null && store.tokenizerVersion == RSVPEngine.VERSION) {
            cached
        } else {
            val fresh = RSVPEngine.tokenize(article, userDictionary = dictionary)
            store.tokens = fresh
            store.tokenizerVersion = RSVPEngine.VERSION
            fresh
        }
    }
    var wpm by remember { mutableIntStateOf(initialWpm) }
    var index by remember { mutableIntStateOf(initialIndex.coerceIn(0, (tokens.size - 1).coerceAtLeast(0))) }
    var isPlaying by remember { mutableStateOf(autoSweepSeconds != null) }
    var jitterAvg by remember { mutableStateOf(0.0) }
    var jitterMax by remember { mutableLongStateOf(0L) }
    var samples by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }

    fun stop() {
        job?.cancel()
        job = null
        isPlaying = false
        onIndexChange(index)
    }

    fun start(resetMetrics: Boolean = false) {
        job?.cancel()
        if (resetMetrics) {
            jitterAvg = 0.0
            jitterMax = 0L
            samples = 0
        }
        isPlaying = true
        if (autoSweepSeconds != null) Log.i(TAG, "RUN_START wpm=$wpm tokens=${tokens.size}")
        job = scope.launch {
            var lastSwap = System.nanoTime()
            while (index < tokens.size - 1) {
                val token = tokens[index]
                val targetMs = RSVPEngine.duration(token, wpm.toDouble()).toLong()
                delay(targetMs)
                val now = System.nanoTime()
                val actualMs = (now - lastSwap) / 1_000_000.0
                lastSwap = now
                val jitter = abs(actualMs - targetMs).toLong()
                if (samples > 5) {
                    val warmup = samples - 5
                    jitterAvg = (jitterAvg * (warmup - 1) + jitter) / warmup
                    if (jitter > jitterMax) jitterMax = jitter
                }
                if (autoSweepSeconds != null) {
                    Log.i(
                        TAG,
                        "TOK i=$index target=${targetMs}ms actual=${"%.2f".format(actualMs)}ms " +
                            "jitter=${jitter}ms tok=\"$token\"",
                    )
                }
                index += 1
                samples += 1
            }
            isPlaying = false
            if (autoSweepSeconds != null) {
                Log.i(TAG, "RUN_END wpm=$wpm samples=$samples avgJitter=${"%.2f".format(jitterAvg)} maxJitter=$jitterMax")
            }
        }
    }

    fun playFromCurrent() {
        if (index >= tokens.size - 1) {
            index = 0
            onIndexChange(0)
        }
        start()
    }

    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    var wasLandscape by remember { mutableStateOf(false) }
    val scrollState = rememberScrollState()

    LaunchedEffect(isLandscape) {
        if (wasLandscape && !isLandscape) {
            stop()
        }
        wasLandscape = isLandscape
    }

    DisposableEffect(Unit) {
        onDispose {
            stop()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp)
            .padding(top = if (isLandscape) 24.dp else 60.dp)
            .then(if (isLandscape) Modifier else Modifier.verticalScroll(scrollState)),
        verticalArrangement = Arrangement.spacedBy(if (isLandscape) 8.dp else 14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                modifier = Modifier.clickable { stop(); onBack() }.testTag("back-button"),
            ) {
                SectionLabel("‹ EDIT")
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong)
                .padding(if (isLandscape) 10.dp else 20.dp),
            contentAlignment = Alignment.Center,
        ) {
            RSVPStage(
                token = tokens.getOrElse(index) { "" },
                focusStyle = FocusIndicatorStyle.Dot,
                minHeight = if (isLandscape) 112.dp else 180.dp,
                modifier = Modifier.blur(if (isPlaying) 0.dp else 1.2.dp),
            )

            if (!isPlaying) {
                StagePlayButton(compact = isLandscape, onTap = ::playFromCurrent)
            }
        }

        Text(
            "${index + 1} / ${tokens.size}",
            color = JRColor.inkQuiet,
            fontSize = 11.sp,
            fontFamily = JRFont.mono,
            letterSpacing = 0.66.sp,
        )

        SectionLabel("PACE")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (target in listOf(300, 450, 600, 800, 1000)) {
                PacePill(value = target, selected = wpm == target) {
                    wpm = target
                    onWpmChange(target)
                    if (isPlaying) start()
                }
            }
        }

        Spacer(Modifier.height(4.dp))
        PrimaryButton(
            label = if (isPlaying) "PAUSE" else if (index >= tokens.size - 1) "RESTART" else "PLAY",
            onTap = {
                if (isPlaying) stop()
                else playFromCurrent()
            },
            testTag = if (isPlaying) "pause-button" else "play-button",
        )

        if (autoSweepSeconds != null) {
            Text(
                "auto-sweep · samples=$samples · avg jitter=${"%.2f".format(jitterAvg)}ms · max=${jitterMax}ms",
                color = JRColor.inkQuiet,
                fontSize = 11.sp,
                fontFamily = JRFont.mono,
                modifier = Modifier.testTag("stats"),
            )
        }
    }

    if (autoSweepSeconds != null) {
        LaunchedEffect(Unit) {
            for (target in listOf(600, 800, 1000, 1200)) {
                wpm = target
                onWpmChange(target)
                index = 0
                onIndexChange(0)
                Log.i(TAG, "AUTO_SWEEP_BEGIN wpm=$target seconds=$autoSweepSeconds")
                start(resetMetrics = true)
                delay(autoSweepSeconds * 1000L)
                stop()
                Log.i(TAG, "AUTO_SWEEP_END wpm=$target")
                delay(500)
            }
            Log.i(TAG, "AUTO_SWEEP_DONE")
        }
    }
}

// ---- Settings screen ------------------------------------------------

@Composable
private fun SettingsScreen(
    dictionary: SnapshotStateList<String>,
    onAdd: (String) -> Unit,
    onRemove: (String) -> Unit,
    onBack: () -> Unit,
) {
    var draft by remember { mutableStateOf("") }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(top = 60.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(modifier = Modifier.clickable(onClick = onBack).testTag("back-button")) {
            SectionLabel("‹ EDIT")
        }
        Text(
            "Custom words",
            color = JRColor.ink,
            fontSize = 26.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = JRFont.serif,
        )
        Text(
            "Names and terms here stay together when reading. Especially helpful for Chinese names that get split.",
            color = JRColor.inkMid,
            fontSize = 13.sp,
            fontFamily = JRFont.sans,
            lineHeight = 19.sp,
        )

        SectionLabel("WORDS (${dictionary.size})")
        for (entry in dictionary) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(4.dp))
                    .background(JRColor.paperStrong)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    entry,
                    color = JRColor.ink,
                    fontSize = 16.sp,
                    fontFamily = JRFont.serif,
                    modifier = Modifier
                        .testTag("dict-entry-$entry")
                        .weight(1f, fill = true),
                )
                Box(
                    modifier = Modifier
                        .clickable { onRemove(entry) }
                        .padding(horizontal = 6.dp)
                        .testTag("dict-remove-$entry"),
                ) {
                    Text(
                        "REMOVE",
                        color = JRColor.terracotta,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = JRFont.sans,
                        letterSpacing = 0.66.sp,
                    )
                }
            }
        }

        SectionLabel("ADD")
        BasicTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong)
                .padding(14.dp)
                .testTag("dict-add-text-field"),
            textStyle = TextStyle(
                color = JRColor.ink,
                fontSize = 18.sp,
                fontFamily = JRFont.serif,
            ),
            cursorBrush = SolidColor(JRColor.terracotta),
        )
        PrimaryButton(label = "ADD", testTag = "dict-add-confirm", onTap = {
            if (draft.isNotBlank()) {
                onAdd(draft)
                draft = ""
            }
        })
        Spacer(Modifier.height(48.dp))
    }
}

// ---- Shared bits ----------------------------------------------------

private val Modifier.weightTest: Modifier get() = this

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

private data class LocalEpubFile(
    val file: File,
    val displayName: String,
    val locationName: String,
)

private fun findLocalEpubFiles(context: Context): List<LocalEpubFile> {
    val roots = listOfNotNull(
        context.filesDir,
        context.getExternalFilesDir(null),
        context.getExternalFilesDir(android.os.Environment.DIRECTORY_DOCUMENTS),
    )

    return roots
        .distinctBy { it.absolutePath }
        .flatMap { root ->
            root.walkTopDown()
                .maxDepth(2)
                .filter { it.isFile && it.extension.equals("epub", ignoreCase = true) }
                .map {
                    LocalEpubFile(
                        file = it,
                        displayName = it.nameWithoutExtension,
                        locationName = it.parentFile?.name?.uppercase() ?: "APP FILES",
                    )
                }
                .toList()
        }
        .sortedBy { it.displayName.lowercase() }
}

private fun Context.displayName(uri: Uri): String? {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0) return cursor.getString(index)
        }
    }
    return uri.lastPathSegment
}

private object EpubTextExtractor {
    private val tagRegex = Regex("<[^>]+>")
    private val whitespaceRegex = Regex("\\s+")

    fun extract(bytes: ByteArray): String {
        val temp = File.createTempFile("justread-", ".epub")
        return try {
            temp.writeBytes(bytes)
            ZipFile(temp).use { zip ->
                zip.entries().asSequence()
                    .filter { !it.isDirectory }
                    .filter { entry ->
                        val name = entry.name.lowercase()
                        name.endsWith(".xhtml") || name.endsWith(".html") || name.endsWith(".htm")
                    }
                    .sortedBy { it.name }
                    .joinToString("\n\n") { entry ->
                        zip.getInputStream(entry).bufferedReader().use { reader ->
                            reader.readText()
                                .replace(tagRegex, " ")
                                .replace("&nbsp;", " ")
                                .replace("&amp;", "&")
                                .replace("&lt;", "<")
                                .replace("&gt;", ">")
                                .replace("&quot;", "\"")
                                .replace("&#39;", "'")
                                .replace(whitespaceRegex, " ")
                                .trim()
                        }
                    }
                    .trim()
            }
        } finally {
            temp.delete()
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        color = JRColor.inkQuiet,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        fontFamily = JRFont.sans,
        letterSpacing = 0.66.sp,
    )
}

@Composable
private fun StagePlayButton(compact: Boolean, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .size(if (compact) 58.dp else 70.dp)
            .clip(CircleShape)
            .background(JRColor.terracotta)
            .clickable(onClick = onTap)
            .testTag("stage-play-button"),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "▶",
            color = JRColor.paper,
            fontSize = if (compact) 24.sp else 30.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(start = 3.dp),
        )
    }
}

@Composable
private fun LocalEpubButton(file: LocalEpubFile, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .clickable(onClick = onTap)
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .testTag("local-epub-${file.displayName}"),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                file.displayName,
                color = JRColor.ink,
                fontSize = 17.sp,
                fontFamily = JRFont.serif,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                locationText(file.locationName),
                color = JRColor.inkQuiet,
                fontSize = 10.sp,
                fontFamily = JRFont.mono,
                letterSpacing = 0.6.sp,
            )
        }
    }
}

private fun locationText(locationName: String): String = "ANDROID FILES / $locationName"

@Composable
private fun PacePill(value: Int, selected: Boolean, onTap: () -> Unit) {
    val bg = if (selected) JRColor.ink else JRColor.paperStrong
    val fg = if (selected) JRColor.paper else JRColor.inkMid
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(3.dp))
            .background(bg)
            .clickable(onClick = onTap)
            .padding(horizontal = 14.dp, vertical = 10.dp)
            .testTag("pace-$value"),
    ) {
        Text(
            value.toString(),
            color = fg,
            fontSize = 13.sp,
            fontFamily = JRFont.sans,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}

@Composable
private fun PrimaryButton(label: String, onTap: () -> Unit, testTag: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.terracotta)
            .clickable(onClick = onTap)
            .padding(vertical = 14.dp)
            .testTag(testTag),
    ) {
        Text(
            label,
            color = JRColor.paper,
            fontSize = 13.sp,
            fontFamily = JRFont.sans,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.66.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun SecondaryButton(label: String, onTap: () -> Unit, testTag: String) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .clickable(onClick = onTap)
            .padding(vertical = 14.dp)
            .testTag(testTag),
    ) {
        Text(
            label,
            color = JRColor.inkMid,
            fontSize = 14.sp,
            fontFamily = JRFont.sans,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}
