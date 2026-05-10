// Spike harness: a stripped-down Reader screen that loops through the
// seeded sample at a chosen WPM and logs each token swap with the
// wall-clock interval since the previous swap. The delta from the
// engine-prescribed duration is the runtime jitter — that's what we
// want to compare against iOS to decide whether KMP holds up at
// 1000+ wpm on Pixel 8 hardware.
//
// Logs land in adb logcat under tag FastReadSpike. The companion
// scripts/spike-perf-report.py turns a captured log into a verdict.
//
// Visuals follow the design handoff (FastReadApp/DesignSystem.swift +
// design_handoff_justread/README.md): cream paper background, ink/ink-
// mid/ink-quiet text, terracotta accent, Fraunces serif for the word
// stage, Inter sans for chrome, JetBrains Mono for the stats strip.

package com.shhtheonlyperson.fastread.spike

import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.core.RSVPEngine
import com.shhtheonlyperson.fastread.spike.ui.FocusIndicatorStyle
import com.shhtheonlyperson.fastread.spike.ui.JRColor
import com.shhtheonlyperson.fastread.spike.ui.JRFont
import com.shhtheonlyperson.fastread.spike.ui.RSVPStage
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

private const val TAG = "FastReadSpike"

// Mixed Trad-Chinese + Latin sample, repeated so the spike has enough
// tokens (~700) to run for ~30s at each tested WPM.
private val SAMPLE = """
    黃士旗去吃飯與星巴克碰面。中華民國總統蔡英文今天宣布，可口可樂與百事可樂的競爭依然激烈。
    Apple在2025年發表新MacBook Pro，價格 1999 美元起。我用VS Code寫iOS app，效率提升 30%。
    今天氣溫 25°C 大約華氏 77°F，成長率達 12.5% 創新高。可參考 RFC-7231 (HTTP/1.1)。
    Dr. Smith 在 NTU 教 AI 課程，他說「Hello, world」就走了。重量100公斤、長度3公尺。
    詳情請見 https://example.com/docs 頁面，寄信到 hello@example.com 報名。
    張三、李四和王五一起去陽明山健行，海拔 1120 公尺。快速閱讀，眼睛更輕鬆。
""".trimIndent().repeat(6)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            Surface(
                modifier = Modifier.fillMaxSize(),
                color = JRColor.paper,
            ) { SpikeScreen() }
        }
    }
}

@Composable
private fun SpikeScreen() {
    val tokens = remember {
        RSVPEngine.tokenize(
            SAMPLE,
            userDictionary = listOf("黃士旗", "蔡英文", "星巴克", "陽明山"),
        )
    }
    var wpm by remember { mutableIntStateOf(450) }
    var index by remember { mutableIntStateOf(0) }
    var isPlaying by remember { mutableStateOf(false) }
    var jitterAvg by remember { mutableStateOf(0.0) }
    var jitterMax by remember { mutableLongStateOf(0L) }
    var sampleCount by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    var job by remember { mutableStateOf<Job?>(null) }

    fun stop() {
        job?.cancel()
        job = null
        isPlaying = false
    }

    fun start() {
        stop()
        index = 0
        jitterAvg = 0.0
        jitterMax = 0L
        sampleCount = 0
        isPlaying = true
        Log.i(TAG, "RUN_START wpm=$wpm tokens=${tokens.size}")
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
                if (sampleCount > 5) {
                    val warmup = sampleCount - 5
                    jitterAvg = (jitterAvg * (warmup - 1) + jitter) / warmup
                    if (jitter > jitterMax) jitterMax = jitter
                }
                Log.i(
                    TAG,
                    "TOK i=$index target=${targetMs}ms actual=${"%.2f".format(actualMs)}ms " +
                        "jitter=${jitter}ms tok=\"$token\"",
                )
                index += 1
                sampleCount += 1
            }
            isPlaying = false
            Log.i(
                TAG,
                "RUN_END wpm=$wpm samples=$sampleCount avgJitter=${"%.2f".format(jitterAvg)} " +
                    "maxJitter=$jitterMax",
            )
        }
    }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(top = 60.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        // Masthead — small caps label per handoff README
        Text(
            "PERF SPIKE",
            color = JRColor.inkQuiet,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = JRFont.sans,
            letterSpacing = 0.66.sp,
        )
        Text(
            "Pixel 8\nframe-timing run.",
            color = JRColor.ink,
            fontSize = 30.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = JRFont.serif,
            lineHeight = 34.sp,
        )

        // Stats strip in mono per handoff
        Text(
            "${tokens.size} tokens · WPM=$wpm · samples=$sampleCount · " +
                "avg jitter=${"%.2f".format(jitterAvg)}ms · max=${jitterMax}ms",
            color = JRColor.inkQuiet,
            fontSize = 11.sp,
            fontFamily = JRFont.mono,
            modifier = Modifier.testTag("stats"),
        )

        // Card-style RSVP stage
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong)
                .padding(16.dp),
        ) {
            RSVPStage(
                token = tokens.getOrElse(index) { "" },
                focusStyle = FocusIndicatorStyle.Dot,
            )
        }

        Text(
            "${index + 1} / ${tokens.size}",
            color = JRColor.inkQuiet,
            fontSize = 11.sp,
            fontFamily = JRFont.mono,
            letterSpacing = 0.66.sp,
        )

        // Pace pills row
        Text(
            "PACE",
            color = JRColor.inkQuiet,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = JRFont.sans,
            letterSpacing = 0.66.sp,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (target in listOf(450, 600, 800, 1000, 1200)) {
                PacePill(value = target, selected = wpm == target) {
                    wpm = target
                    if (isPlaying) start()
                }
            }
        }

        Spacer(Modifier.height(4.dp))
        StartStopButton(isPlaying = isPlaying) { if (isPlaying) stop() else start() }
    }
}

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
private fun StartStopButton(isPlaying: Boolean, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.terracotta)
            .clickable(onClick = onTap)
            .padding(vertical = 14.dp)
            .testTag(if (isPlaying) "stop-button" else "start-button"),
    ) {
        Text(
            if (isPlaying) "STOP" else "START",
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
private fun ColumnTap(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    content()
}
