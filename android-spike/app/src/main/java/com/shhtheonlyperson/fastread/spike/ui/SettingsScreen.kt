package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.shhtheonlyperson.fastread.spike.data.FocusIndicatorStyle

@Composable
fun SettingsScreen(
    wpm: Int,
    minimumWpm: Int,
    punctuationPause: Boolean,
    focusIndicator: FocusIndicatorStyle,
    dictionary: List<String>,
    appVersion: String,
    onWpmChange: (Int) -> Unit,
    onPunctuationPauseChange: (Boolean) -> Unit,
    onFocusIndicatorChange: (FocusIndicatorStyle) -> Unit,
    onAdd: (String) -> Unit,
    onRemove: (String) -> Unit,
) {
    var draft by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(JRColor.paper)
            .padding(horizontal = 16.dp)
            .padding(top = 60.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        SectionLabel("SETTINGS")
        Text(
            "The shape\nof your read.",
            color = JRColor.ink,
            fontSize = 32.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = JRFont.serif,
            lineHeight = 35.sp,
        )

        SettingsGroup("PACE") {
            SettingsRow {
                Text("Words per minute", modifier = Modifier.weight(1f))
                Text(
                    wpm.toString(),
                    color = JRColor.ink,
                    fontSize = 18.sp,
                    fontFamily = JRFont.serif,
                    fontWeight = FontWeight.SemiBold,
                )
            }
            Slider(
                value = wpm.toFloat().coerceIn(minimumWpm.toFloat(), 1500f),
                onValueChange = { onWpmChange(it.toInt()) },
                valueRange = minimumWpm.toFloat()..1500f,
                steps = ((1500 - minimumWpm) / 50 - 1).coerceAtLeast(0),
                colors = justReadSliderColors(),
                modifier = Modifier.padding(horizontal = 16.dp),
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .padding(bottom = 14.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                SectionLabel("SLOW · $minimumWpm")
                SectionLabel("FAST · 900")
                SectionLabel("SPRINT · 1500")
            }
            SettingsRow {
                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Pause on punctuation")
                    Text(
                        "Slows down at periods, commas, and semicolons.",
                        color = JRColor.inkQuiet,
                        fontSize = 12.sp,
                        fontFamily = JRFont.sans,
                    )
                }
                Switch(
                    checked = punctuationPause,
                    onCheckedChange = onPunctuationPauseChange,
                    colors = justReadSwitchColors(),
                )
            }
        }

        SettingsGroup("FOCUS INDICATOR") {
            Row(
                modifier = Modifier.fillMaxWidth().padding(12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FocusIndicatorStyle.entries.forEach { option ->
                    FocusPill(
                        label = option.label,
                        selected = option == focusIndicator,
                        onTap = { onFocusIndicatorChange(option) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        SettingsGroup("CUSTOM WORDS") {
            SettingsRow {
                Text(
                    "Keep names, brands, and terms together. Especially helpful for Chinese names.",
                    color = JRColor.inkMid,
                    fontSize = 13.sp,
                    fontFamily = JRFont.sans,
                    lineHeight = 18.sp,
                )
            }

            dictionary.forEach { entry ->
                SettingsRow {
                    Text(
                        entry,
                        color = JRColor.ink,
                        fontSize = 16.sp,
                        fontFamily = JRFont.serif,
                        modifier = Modifier.weight(1f).testTag("dict-entry-$entry"),
                    )
                    Text(
                        "REMOVE",
                        color = JRColor.terracotta,
                        fontSize = 11.sp,
                        fontFamily = JRFont.mono,
                        letterSpacing = 0.66.sp,
                        modifier = Modifier
                            .clickable { onRemove(entry) }
                            .testTag("dict-remove-$entry"),
                    )
                }
            }

            SettingsRow {
                BasicTextField(
                    value = draft,
                    onValueChange = { draft = it },
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(4.dp))
                        .background(JRColor.paper)
                        .padding(12.dp)
                        .testTag("dict-add-text-field"),
                    textStyle = TextStyle(
                        color = JRColor.ink,
                        fontSize = 17.sp,
                        fontFamily = JRFont.serif,
                    ),
                    cursorBrush = SolidColor(JRColor.terracotta),
                )
                Text(
                    "ADD",
                    color = JRColor.terracotta,
                    fontSize = 12.sp,
                    fontFamily = JRFont.mono,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp,
                    modifier = Modifier
                        .clickable {
                            if (draft.isNotBlank()) {
                                onAdd(draft)
                                draft = ""
                            }
                        }
                        .padding(start = 10.dp)
                        .testTag("dict-add-confirm"),
                )
            }
        }

        SettingsGroup("ABOUT") {
            SettingsRow {
                Text("Version", modifier = Modifier.weight(1f))
                Text(
                    appVersion,
                    color = JRColor.inkQuiet,
                    fontSize = 13.sp,
                    fontFamily = JRFont.mono,
                )
            }
            SettingsRow {
                Text("Privacy policy", modifier = Modifier.weight(1f))
                Text(
                    "Local data only",
                    color = JRColor.inkQuiet,
                    fontSize = 13.sp,
                    fontFamily = JRFont.mono,
                )
            }
            SettingsRow {
                Text("Feedback", modifier = Modifier.weight(1f))
                Text(
                    "shh@theonlyperson.com",
                    color = JRColor.inkQuiet,
                    fontSize = 13.sp,
                    fontFamily = JRFont.mono,
                )
            }
        }

        Spacer(Modifier.height(112.dp))
    }
}

@Composable
private fun SettingsGroup(label: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel(label)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong),
            content = content,
        )
    }
}

@Composable
private fun SettingsRow(content: @Composable RowScope.() -> Unit) {
    ProvideTextStyle(
        value = TextStyle(
            color = JRColor.ink,
            fontSize = 15.sp,
            fontFamily = JRFont.sans,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            content = content,
        )
    }
}

@Composable
private fun FocusPill(label: String, selected: Boolean, onTap: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(4.dp))
            .background(if (selected) JRColor.ink else JRColor.paper)
            .clickable(onClick = onTap)
            .padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            color = if (selected) JRColor.paper else JRColor.inkMid,
            fontSize = 13.sp,
            fontFamily = JRFont.sans,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
        )
    }
}
