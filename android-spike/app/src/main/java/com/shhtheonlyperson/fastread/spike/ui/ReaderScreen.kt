package com.shhtheonlyperson.fastread.spike.ui

import android.content.res.Configuration
import android.util.Log
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.core.ReaderPlaybackState
import com.shhtheonlyperson.fastread.spike.core.RSVPEngine
import com.shhtheonlyperson.fastread.spike.data.Persistence
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

private const val TAG = "FastReadSpike"

@Composable
fun ReaderScreen(
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
    var index by remember { mutableIntStateOf(ReaderPlaybackState(initialIndex, tokens.size).normalizedIndex) }
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
            while (ReaderPlaybackState(index, tokens.size).nextIndex() != null) {
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
                index = ReaderPlaybackState(index, tokens.size).nextIndex() ?: index
                samples += 1
            }
            isPlaying = false
            if (autoSweepSeconds != null) {
                Log.i(TAG, "RUN_END wpm=$wpm samples=$samples avgJitter=${"%.2f".format(jitterAvg)} maxJitter=$jitterMax")
            }
        }
    }

    fun playFromCurrent() {
        if (ReaderPlaybackState(index, tokens.size).isAtEnd) {
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
            for (target in listOf(300, 450, 600, 900, 1200, 1500)) {
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
            for (target in listOf(600, 800, 1000, 1200, 1500)) {
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
