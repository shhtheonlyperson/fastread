package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.data.LocalEpubFile
import com.shhtheonlyperson.fastread.spike.data.RecentSource

@Composable
fun PasteScreen(
    input: String,
    onInputChange: (String) -> Unit,
    onSubmit: () -> Unit,
    isLoading: Boolean,
    status: String,
    recentSources: List<RecentSource>,
    onRecentSource: (RecentSource) -> Unit,
    localEpubs: List<LocalEpubFile>,
    onRefreshLocalEpubs: () -> Unit,
    onPickEpub: () -> Unit,
    onImportLocalEpub: (LocalEpubFile) -> Unit,
) {
    LaunchedEffect(Unit) {
        onRefreshLocalEpubs()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(JRColor.paper)
            .padding(horizontal = 16.dp)
            .padding(top = 60.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        SectionLabel("NEW READING")
        Text(
            "Capture\nyour next read.",
            color = JRColor.ink,
            fontSize = 32.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = JRFont.serif,
            lineHeight = 35.sp,
        )

        SectionLabel("TEXT OR URL")
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(240.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong)
                .padding(14.dp),
        ) {
            BasicTextField(
                value = input,
                onValueChange = onInputChange,
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("paste-text-field"),
                textStyle = TextStyle(
                    color = JRColor.ink,
                    fontSize = 16.sp,
                    fontFamily = JRFont.serif,
                    lineHeight = 22.sp,
                ),
                cursorBrush = SolidColor(JRColor.terracotta),
            )
            if (input.isBlank()) {
                Text(
                    "Paste article text or a URL.",
                    color = JRColor.inkQuiet,
                    fontSize = 15.sp,
                    fontFamily = JRFont.serif,
                )
            }
        }

        PrimaryButton(
            label = if (isLoading) "LOADING" else "ADD TO LIBRARY",
            onTap = { if (!isLoading) onSubmit() },
            testTag = "read-button",
        )

        SectionLabel("EPUB BOOK")
        SecondaryButton(label = "Pick EPUB", onTap = { if (!isLoading) onPickEpub() }, testTag = "pick-epub-button")

        if (status.isNotBlank()) {
            Text(
                status.uppercase(),
                color = if (status.startsWith("Loaded")) JRColor.terracotta else JRColor.inkQuiet,
                fontSize = 11.sp,
                fontFamily = JRFont.mono,
                letterSpacing = 0.66.sp,
            )
        }

        if (recentSources.isNotEmpty()) {
            SectionLabel("RECENT SOURCES")
            recentSources.forEach { source ->
                RecentSourceButton(source = source, onTap = { onRecentSource(source) })
            }
        }

        if (localEpubs.isNotEmpty()) {
            SectionLabel("FILES FOLDER")
            localEpubs.forEach { file ->
                LocalEpubButton(file = file, onTap = { if (!isLoading) onImportLocalEpub(file) })
            }
        }

        Spacer(Modifier.height(96.dp))
    }
}

@Composable
private fun RecentSourceButton(source: RecentSource, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .clickable(onClick = onTap)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        contentAlignment = Alignment.CenterStart,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                source.label,
                color = JRColor.ink,
                fontSize = 17.sp,
                fontFamily = JRFont.serif,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                source.date.uppercase(),
                color = JRColor.inkQuiet,
                fontSize = 10.sp,
                fontFamily = JRFont.mono,
                letterSpacing = 0.6.sp,
            )
        }
    }
}
