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
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.core.ReaderPlaybackState
import com.shhtheonlyperson.fastread.spike.core.RSVPEngine
import com.shhtheonlyperson.fastread.spike.data.Persistence
import com.shhtheonlyperson.fastread.spike.data.ReadingArticle
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.ceil

private const val TAG = "FastReadSpike"

@Composable
fun ReaderScreen(
    article: ReadingArticle?,
    store: Persistence,
    onBack: () -> Unit,
    autoSweepSeconds: Int? = null,
) {
    if (article == null) {
        EmptyReader(onBack = onBack)
        return
    }

    val tokens = remember(article.id, article.tokens, article.tokenizerVersion, store.dictionary) {
        store.tokensFor(article)
    }
    var index by remember(article.id, tokens.size) {
        mutableIntStateOf(ReaderPlaybackState(article.wordIndex, tokens.size).normalizedIndex)
    }
    var isPlaying by remember(article.id) { mutableStateOf(autoSweepSeconds != null) }
    var jitterAvg by remember { mutableDoubleStateOf(0.0) }
    var jitterMax by remember { mutableLongStateOf(0L) }
    var samples by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }

    fun stop() {
        job?.cancel()
        job = null
        isPlaying = false
        store.setCurrentIndex(index)
    }

    fun start(resetMetrics: Boolean = false) {
        job?.cancel()
        if (resetMetrics) {
            jitterAvg = 0.0
            jitterMax = 0L
            samples = 0
        }
        if (tokens.size <= 1) return
        isPlaying = true
        if (autoSweepSeconds != null) Log.i(TAG, "RUN_START wpm=${store.wpm} tokens=${tokens.size}")
        job = scope.launch {
            var lastSwap = System.nanoTime()
            while (ReaderPlaybackState(index, tokens.size).nextIndex() != null) {
                val token = tokens[index]
                val targetMs = RSVPEngine.duration(
                    token,
                    store.wpm.toDouble(),
                    punctuationPause = store.punctuationPause,
                ).toLong()
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
                val next = ReaderPlaybackState(index, tokens.size).nextIndex() ?: index
                index = next
                store.setCurrentIndex(next, recordReadWord = true)
                samples += 1
            }
            isPlaying = false
            if (autoSweepSeconds != null) {
                Log.i(TAG, "RUN_END wpm=${store.wpm} samples=$samples avgJitter=${"%.2f".format(jitterAvg)} maxJitter=$jitterMax")
            }
        }
    }

    fun playFromCurrent() {
        if (ReaderPlaybackState(index, tokens.size).isAtEnd) {
            index = 0
            store.setCurrentIndex(0)
        }
        start()
    }

    val isLandscape = LocalConfiguration.current.orientation == Configuration.ORIENTATION_LANDSCAPE
    var wasLandscape by remember { mutableStateOf(false) }

    LaunchedEffect(isLandscape) {
        if (wasLandscape && !isLandscape) stop()
        wasLandscape = isLandscape
    }

    DisposableEffect(article.id) {
        onDispose { stop() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(JRColor.paper)
            .padding(horizontal = 16.dp)
            .padding(top = if (isLandscape) 24.dp else 60.dp)
            .then(if (isLandscape) Modifier else Modifier.verticalScroll(rememberScrollState())),
        verticalArrangement = Arrangement.spacedBy(if (isLandscape) 8.dp else 14.dp),
    ) {
        Header(article = article, compact = isLandscape, onBack = { stop(); onBack() })

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
                focusStyle = store.focusIndicator,
                minHeight = if (isLandscape) 112.dp else 180.dp,
                modifier = Modifier.blur(if (isPlaying) 0.dp else 1.2.dp),
            )

            if (!isPlaying) {
                StagePlayButton(compact = isLandscape, onTap = ::playFromCurrent)
            }
        }

        ProgressScrubber(
            index = index,
            tokenCount = tokens.size,
            minutesLeft = minutesRemaining(tokens.size, index, store.wpm),
            onScrub = { progress ->
                stop()
                index = store.scrubTo(progress)
            },
        )

        SectionLabel("PACE")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (target in listOf(300, 450, 600, 900, 1200, 1500)) {
                PacePill(value = target, selected = store.wpm == target) {
                    store.setWPM(target)
                    if (isPlaying) start()
                }
            }
        }

        PrimaryButton(
            label = if (isPlaying) "PAUSE" else if (index >= tokens.size - 1) "RESTART" else "PLAY",
            onTap = {
                if (isPlaying) stop()
                else playFromCurrent()
            },
            testTag = if (isPlaying) "pause-button" else "play-button",
        )

        if (index >= tokens.size - 1 && tokens.isNotEmpty()) {
            DoneStrip(tokenCount = tokens.size, wpm = store.wpm) {
                stop()
                store.markRead()
                index = tokens.lastIndex
            }
        }

        if (autoSweepSeconds != null) {
            Text(
                "auto-sweep · samples=$samples · avg jitter=${"%.2f".format(jitterAvg)}ms · max=${jitterMax}ms",
                color = JRColor.inkQuiet,
                fontSize = 11.sp,
                fontFamily = JRFont.mono,
                modifier = Modifier.testTag("stats"),
            )
        }

        Spacer(Modifier.height(96.dp))
    }

    if (autoSweepSeconds != null) {
        LaunchedEffect(article.id) {
            for (target in listOf(600, 800, 1000, 1200, 1500)) {
                store.setWPM(target)
                index = 0
                store.setCurrentIndex(0)
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

@Composable
private fun Header(article: ReadingArticle, compact: Boolean, onBack: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(if (compact) 3.dp else 8.dp)) {
        Box(modifier = Modifier.clickable(onClick = onBack).testTag("back-button")) {
            SectionLabel("‹ LIBRARY")
        }
        Text(
            article.title,
            color = JRColor.ink,
            fontSize = if (compact) 18.sp else 22.sp,
            fontFamily = JRFont.serif,
            fontWeight = FontWeight.Medium,
            lineHeight = if (compact) 21.sp else 26.sp,
            maxLines = if (compact) 1 else 2,
        )
        Text(
            "${article.source} · ${article.author} · ${article.date}",
            color = JRColor.inkQuiet,
            fontSize = 12.sp,
            fontFamily = JRFont.sans,
            maxLines = 1,
        )
    }
}

@Composable
private fun ProgressScrubber(
    index: Int,
    tokenCount: Int,
    minutesLeft: Double,
    onScrub: (Float) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Slider(
            value = if (tokenCount <= 1) 0f else index.toFloat() / (tokenCount - 1).toFloat(),
            onValueChange = onScrub,
            valueRange = 0f..1f,
            colors = justReadSliderColors(),
        )
        Row {
            Text(
                "${index + 1} / ${maxOf(tokenCount, 1)}",
                color = JRColor.inkQuiet,
                fontSize = 11.sp,
                fontFamily = JRFont.mono,
                letterSpacing = 0.66.sp,
            )
            Spacer(Modifier.weight(1f))
            Text(
                if (minutesLeft < 1) "${ceil(minutesLeft * 60).toInt()}s left" else "${"%.1f".format(minutesLeft)}m left",
                color = JRColor.inkQuiet,
                fontSize = 11.sp,
                fontFamily = JRFont.mono,
                letterSpacing = 0.66.sp,
            )
        }
    }
}

@Composable
private fun DoneStrip(tokenCount: Int, wpm: Int, onMarkRead: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperDeep.copy(alpha = 0.72f))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "Done · $tokenCount words in ${ceil(tokenCount.toDouble() / wpm.toDouble()).toInt()} minutes",
            color = JRColor.inkQuiet,
            fontSize = 11.sp,
            fontFamily = JRFont.mono,
            letterSpacing = 0.66.sp,
            modifier = Modifier.weight(1f),
        )
        Text(
            "Mark read",
            color = JRColor.paper,
            fontSize = 13.sp,
            fontFamily = JRFont.sans,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier
                .clip(RoundedCornerShape(18.dp))
                .background(JRColor.terracotta)
                .clickable(onClick = onMarkRead)
                .padding(horizontal = 12.dp, vertical = 7.dp),
        )
    }
}

@Composable
private fun EmptyReader(onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(JRColor.paper)
            .padding(top = 60.dp, start = 24.dp, end = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SectionLabel("READER")
        Text(
            "Nothing queued.",
            color = JRColor.ink,
            fontSize = 36.sp,
            fontFamily = JRFont.serif,
            fontWeight = FontWeight.Medium,
        )
        Text(
            "Add text, fetch a URL, or import an EPUB first. The reader preserves saved article progress locally.",
            color = JRColor.inkMid,
            fontSize = 14.sp,
            fontFamily = JRFont.sans,
            lineHeight = 20.sp,
        )
        SecondaryButton(label = "Back to library", onTap = onBack, testTag = "back-empty-reader")
    }
}

private fun minutesRemaining(tokenCount: Int, index: Int, wpm: Int): Double =
    maxOf(tokenCount - index, 0).toDouble() / wpm.toDouble()
