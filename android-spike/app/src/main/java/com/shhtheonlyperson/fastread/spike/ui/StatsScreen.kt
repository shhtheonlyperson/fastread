package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.data.ReadingStats

@Composable
fun StatsScreen(stats: ReadingStats, currentWpm: Int) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(JRColor.paper)
            .verticalScroll(rememberScrollState())
            .padding(top = 60.dp, start = 16.dp, end = 16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        SectionLabel("THIS WEEK")
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                stats.weekTotal.toString(),
                color = JRColor.ink,
                fontSize = 36.sp,
                fontFamily = JRFont.serif,
                fontWeight = FontWeight.Medium,
            )
            Text(
                " words",
                color = JRColor.inkQuiet,
                fontSize = 34.sp,
                fontFamily = JRFont.serif,
            )
        }
        Text(
            summaryLine(stats, currentWpm),
            color = JRColor.inkMid,
            fontSize = 14.sp,
            fontFamily = JRFont.sans,
            lineHeight = 20.sp,
        )

        TodayCard(stats)
        WeeklyChart(stats)

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatCard("STREAK", stats.streak.toString(), "days", Modifier.weight(1f))
            StatCard("AVG PACE", if (stats.avgWPM > 0) stats.avgWPM.toString() else "—", "wpm", Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatCard("BEST PACE", if (stats.bestWPM > 0) stats.bestWPM.toString() else "—", "wpm", Modifier.weight(1f))
            StatCard("ARTICLES READ", stats.totalArticles.toString(), "total", Modifier.weight(1f))
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong)
                .padding(18.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel("THIS WEEK'S NOTE")
                Text(
                    weeklyNote(stats),
                    color = JRColor.ink,
                    fontSize = 16.sp,
                    fontFamily = JRFont.serif,
                    lineHeight = 22.sp,
                )
            }
        }

        Spacer(Modifier.height(112.dp))
    }
}

@Composable
private fun TodayCard(stats: ReadingStats) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .padding(vertical = 18.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        TodayMetric(stats.today.words.toString(), "WORDS")
        TodayMetric(stats.today.minutes.toString(), "MINUTES")
        TodayMetric(stats.today.articles.toString(), "ARTICLES")
    }
}

@Composable
private fun TodayMetric(value: String, label: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            value,
            color = JRColor.ink,
            fontSize = 26.sp,
            fontFamily = JRFont.serif,
            fontWeight = FontWeight.Medium,
        )
        Text(
            label,
            color = JRColor.inkQuiet,
            fontSize = 10.sp,
            fontFamily = JRFont.mono,
            letterSpacing = 1.0.sp,
        )
    }
}

@Composable
private fun WeeklyChart(stats: ReadingStats) {
    val maxWords = maxOf(stats.week.maxOfOrNull { it.words } ?: 1, 1)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .heightIn(min = 160.dp)
            .padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        stats.week.forEachIndexed { index, day ->
            val isToday = index == stats.week.lastIndex
            Column(
                modifier = Modifier.weight(1f),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Box(
                    modifier = Modifier
                        .width(18.dp)
                        .height(maxOf(5, (day.words.toFloat() / maxWords.toFloat() * 112).toInt()).dp)
                        .clip(RoundedCornerShape(1.dp))
                        .background(if (isToday) JRColor.terracotta else JRColor.ink.copy(alpha = 0.78f)),
                )
                Text(
                    day.day.take(3),
                    color = if (isToday) JRColor.terracotta else JRColor.inkQuiet,
                    fontSize = 10.sp,
                    fontFamily = JRFont.mono,
                    letterSpacing = 0.6.sp,
                )
            }
        }
    }
}

@Composable
private fun StatCard(label: String, value: String, unit: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .padding(horizontal = 14.dp, vertical = 16.dp),
    ) {
        SectionLabel(label)
        Text(
            value,
            color = JRColor.ink,
            fontSize = 30.sp,
            fontFamily = JRFont.serif,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.padding(top = 10.dp),
        )
        Text(
            unit.uppercase(),
            color = JRColor.inkQuiet,
            fontSize = 10.sp,
            fontFamily = JRFont.mono,
            letterSpacing = 1.0.sp,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

private fun summaryLine(stats: ReadingStats, currentWpm: Int): String {
    if (stats.weekTotal <= 0) return "Start reading to build a real weekly trend."
    val pace = if (stats.avgWPM > 0) stats.avgWPM else currentWpm
    return "That's roughly ${"%.2f".format(stats.weekTotal.toDouble() / 60_000)} novellas at $pace wpm."
}

private fun weeklyNote(stats: ReadingStats): String {
    if (stats.weekTotal <= 0) {
        return "No reading activity yet this week. Paste an article, fetch a URL, or import an EPUB and your real pace, streak, and article counts will appear here."
    }
    val activeDays = stats.week.count { it.words > 0 }
    val bestDay = stats.week.maxByOrNull { it.words }
    return if (bestDay != null && bestDay.words > 0) {
        "You read on $activeDays day${if (activeDays == 1) "" else "s"} this week. Your strongest day was ${bestDay.day} with ${bestDay.words} words."
    } else {
        "Your weekly trend is based only on words you actually read in JustRead."
    }
}
