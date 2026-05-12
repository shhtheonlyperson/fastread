// Compose port of FastReadApp/ReaderView.swift's RSVPStage. Renders a
// single token with the ORP focus letter highlighted in terracotta and
// a focus indicator (Dot / Line / Crosshair) above and below — matches
// the iOS spec in the handoff README §3 "Focus indicator".

package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.core.RSVPEngine

enum class FocusIndicatorStyle { Dot, Line, Crosshair }

@Composable
fun RSVPStage(
    token: String,
    focusStyle: FocusIndicatorStyle = FocusIndicatorStyle.Dot,
    isDark: Boolean = false,
    minHeight: Dp = 180.dp,
    modifier: Modifier = Modifier,
) {
    val split = RSVPEngine.splitForFocus(token)
    val wordColor = if (isDark) JRColor.paper else JRColor.ink
    val bg = if (isDark) JRColor.focusDark else JRColor.paperStrong

    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = minHeight)
            .background(bg)
            .semantics {
                contentDescription = token
            }
            .testTag("rsvp-current-token"),
        contentAlignment = Alignment.Center,
    ) {
        // Top focus indicator
        Box(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .height(if (focusStyle == FocusIndicatorStyle.Dot) 8.dp else 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            when (focusStyle) {
                FocusIndicatorStyle.Dot -> Box(
                    Modifier.size(4.dp).background(JRColor.terracotta, CircleShape),
                )
                FocusIndicatorStyle.Line -> Box(
                    Modifier.width(18.dp).height(1.dp).background(JRColor.terracotta),
                )
                FocusIndicatorStyle.Crosshair -> Box(
                    Modifier.width(0.5.dp).height(180.dp).background(JRColor.terracotta),
                )
            }
        }

        // The token itself with focus letter highlighted. Font scaling per
        // handoff README: 36pt ≤6 chars, 32pt 7-9, 28pt 10+.
        val size = stageFontSize(token)
        Text(
            buildAnnotatedString {
                withStyle(SpanStyle(color = wordColor)) { append(split.before) }
                withStyle(
                    SpanStyle(color = JRColor.terracotta, fontWeight = FontWeight.SemiBold),
                ) { append(split.focus) }
                withStyle(SpanStyle(color = wordColor)) { append(split.after) }
            },
            fontSize = size,
            fontFamily = JRFont.serif,
            fontWeight = FontWeight.Medium,
        )

        // Bottom focus indicator (mirror of top)
        Box(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .height(if (focusStyle == FocusIndicatorStyle.Dot) 8.dp else 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            when (focusStyle) {
                FocusIndicatorStyle.Dot -> Box(
                    Modifier.size(4.dp).background(JRColor.terracotta, CircleShape),
                )
                FocusIndicatorStyle.Line -> Box(
                    Modifier.width(18.dp).height(1.dp).background(JRColor.terracotta),
                )
                FocusIndicatorStyle.Crosshair -> Box(Modifier.size(0.dp))
            }
        }
    }
}

private fun stageFontSize(token: String) = when {
    token.length <= 6 -> 56.sp  // bigger than handoff 36pt because Compose
                                // .sp scales with system font size; the
                                // Reader screen on iOS settles around
                                // 54-56pt at default Dynamic Type.
    token.length <= 9 -> 48.sp
    else -> 40.sp
}
