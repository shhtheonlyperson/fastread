package com.shhtheonlyperson.fastread.spike.ui

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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.data.Persistence
import com.shhtheonlyperson.fastread.spike.data.ReadingArticle

@Composable
fun LibraryScreen(
    store: Persistence,
    onResume: () -> Unit,
    onOpenArticle: (ReadingArticle) -> Unit,
    onDeleteArticle: (ReadingArticle) -> Unit,
) {
    val articles = store.articles
    val current = store.currentArticle ?: articles.firstOrNull { !it.isFinished } ?: articles.firstOrNull()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(JRColor.paper)
            .verticalScroll(rememberScrollState())
            .padding(top = 60.dp, start = 16.dp, end = 16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Masthead(store)

        if (current != null) {
            ContinueCard(store = store, article = current, onTap = onResume)
        } else {
            EmptyContinueCard()
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            SectionLabel("LIBRARY")
            Spacer(Modifier.weight(1f))
            SectionLabel("${articles.size} ITEMS", color = JRColor.inkQuiet.copy(alpha = 0.55f))
        }

        if (articles.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(4.dp))
                    .background(JRColor.paperStrong)
                    .padding(16.dp),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "No saved articles yet.",
                        color = JRColor.ink,
                        fontSize = 17.sp,
                        fontFamily = JRFont.serif,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        "Use Add to paste text, fetch a URL, or import an EPUB.",
                        color = JRColor.inkQuiet,
                        fontSize = 13.sp,
                        fontFamily = JRFont.sans,
                        lineHeight = 18.sp,
                    )
                }
            }
        } else {
            Column(
                modifier = Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .background(JRColor.paperStrong),
            ) {
                articles.forEach { article ->
                    ArticleRow(
                        article = article,
                        onTap = { onOpenArticle(article) },
                        onDelete = { onDeleteArticle(article) },
                    )
                }
            }
        }

        Spacer(Modifier.height(112.dp))
    }
}

@Composable
private fun Masthead(store: Persistence) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "JustRead",
                color = JRColor.ink,
                fontSize = 20.sp,
                fontFamily = JRFont.serif,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.weight(1f))
            SectionLabel(java.time.LocalDate.now().dayOfWeek.name.take(3))
        }
        Text(
            "Today you've read",
            color = JRColor.ink,
            fontSize = 36.sp,
            fontFamily = JRFont.serif,
            fontWeight = FontWeight.Medium,
            lineHeight = 38.sp,
        )
        Text(
            "${store.stats.today.words} words.",
            color = JRColor.terracotta,
            fontSize = 36.sp,
            fontFamily = JRFont.serif,
            fontWeight = FontWeight.Medium,
            lineHeight = 38.sp,
        )
        Text(
            "${store.stats.today.minutes} minutes across ${store.stats.today.articles} articles. Streak: ${store.stats.streak} days.",
            color = JRColor.inkQuiet,
            fontSize = 14.sp,
            fontFamily = JRFont.sans,
            lineHeight = 20.sp,
        )
    }
}

@Composable
private fun ContinueCard(store: Persistence, article: ReadingArticle, onTap: () -> Unit) {
    val wordCount = store.wordCount(article)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .clickable(onClick = onTap)
            .padding(16.dp)
            .testTag("continue-card"),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel("CONTINUE READING")
                Spacer(Modifier.weight(1f))
                SectionLabel("${(wordCount * article.progress).toInt()} OF $wordCount", color = JRColor.terracotta)
            }
            Text(
                article.title,
                color = JRColor.ink,
                fontSize = 22.sp,
                fontFamily = JRFont.serif,
                fontWeight = FontWeight.Medium,
                lineHeight = 25.sp,
            )
            ProgressBar(progress = article.progress.toFloat())
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${article.source} · ${article.readTime}",
                    color = JRColor.inkMid,
                    fontSize = 13.sp,
                    fontFamily = JRFont.sans,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    "Resume",
                    color = JRColor.paper,
                    fontSize = 13.sp,
                    fontFamily = JRFont.sans,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(20.dp))
                        .background(JRColor.terracotta)
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                )
            }
        }
    }
}

@Composable
private fun EmptyContinueCard() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .padding(16.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            SectionLabel("START READING")
            Text(
                "Add your first article.",
                color = JRColor.ink,
                fontSize = 22.sp,
                fontFamily = JRFont.serif,
                fontWeight = FontWeight.Medium,
            )
            Text(
                "Paste text, fetch a page, or import an EPUB to build a real reading library.",
                color = JRColor.inkMid,
                fontSize = 13.sp,
                fontFamily = JRFont.sans,
                lineHeight = 18.sp,
            )
        }
    }
}

@Composable
private fun ArticleRow(article: ReadingArticle, onTap: () -> Unit, onDelete: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onTap)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                SectionLabel(article.tag.uppercase(), color = if (article.progress > 0 && !article.isFinished) JRColor.terracotta else JRColor.inkQuiet)
                Spacer(Modifier.weight(1f))
                Text(
                    article.readTime,
                    color = JRColor.inkQuiet,
                    fontSize = 11.sp,
                    fontFamily = JRFont.mono,
                    letterSpacing = 0.66.sp,
                )
            }
            Text(
                article.title,
                color = JRColor.ink,
                fontSize = 17.sp,
                fontFamily = JRFont.serif,
                fontWeight = FontWeight.Medium,
                lineHeight = 21.sp,
            )
            Text(
                article.lede,
                color = JRColor.inkMid,
                fontSize = 13.sp,
                fontFamily = JRFont.sans,
                lineHeight = 18.sp,
                maxLines = 2,
            )
        }
        Text(
            "DELETE",
            color = JRColor.terracotta,
            fontSize = 10.sp,
            fontFamily = JRFont.mono,
            letterSpacing = 0.8.sp,
            modifier = Modifier
                .padding(start = 12.dp)
                .clickable(onClick = onDelete)
                .testTag("delete-${article.id}"),
        )
    }
}

@Composable
fun ProgressBar(progress: Float, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(5.dp)
            .clip(RoundedCornerShape(2.dp))
            .background(JRColor.ruleStrong),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(progress.coerceIn(0f, 1f))
                .height(5.dp)
                .background(JRColor.terracotta),
        )
    }
}
