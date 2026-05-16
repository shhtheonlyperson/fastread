package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.data.LocalEpubFile

@Composable
fun PasteScreen(
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
