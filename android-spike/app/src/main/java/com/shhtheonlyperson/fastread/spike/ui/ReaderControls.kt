package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.data.LocalEpubFile

@Composable
fun SectionLabel(text: String, color: Color = JRColor.inkQuiet) {
    Text(
        text,
        color = color,
        fontSize = 11.sp,
        fontWeight = FontWeight.SemiBold,
        fontFamily = JRFont.sans,
        letterSpacing = 0.66.sp,
    )
}

@Composable
fun StagePlayButton(compact: Boolean, onTap: () -> Unit) {
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
fun LocalEpubButton(file: LocalEpubFile, onTap: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(4.dp))
            .background(JRColor.paperStrong)
            .clickable(onClick = onTap)
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .testTag("local-epub-${file.displayName}"),
    ) {
        Column {
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
fun PacePill(value: Int, selected: Boolean, onTap: () -> Unit) {
    val bg = if (selected) JRColor.ink else JRColor.paperStrong
    val fg = if (selected) JRColor.paper else JRColor.inkMid
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(3.dp))
            .background(bg)
            .clickable(onClick = onTap)
            .padding(horizontal = 10.dp, vertical = 10.dp)
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
fun PrimaryButton(label: String, onTap: () -> Unit, testTag: String) {
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
fun SecondaryButton(label: String, onTap: () -> Unit, testTag: String) {
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
