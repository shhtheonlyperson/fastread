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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SettingsScreen(
    dictionary: SnapshotStateList<String>,
    onAdd: (String) -> Unit,
    onRemove: (String) -> Unit,
    onBack: () -> Unit,
) {
    var draft by remember { mutableStateOf("") }

    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp).padding(top = 60.dp).verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(modifier = Modifier.clickable(onClick = onBack).testTag("back-button")) {
            SectionLabel("‹ EDIT")
        }
        Text(
            "Custom words",
            color = JRColor.ink,
            fontSize = 26.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = JRFont.serif,
        )
        Text(
            "Names and terms here stay together when reading. Especially helpful for Chinese names that get split.",
            color = JRColor.inkMid,
            fontSize = 13.sp,
            fontFamily = JRFont.sans,
            lineHeight = 19.sp,
        )

        SectionLabel("WORDS (${dictionary.size})")
        for (entry in dictionary) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(4.dp))
                    .background(JRColor.paperStrong)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    entry,
                    color = JRColor.ink,
                    fontSize = 16.sp,
                    fontFamily = JRFont.serif,
                    modifier = Modifier
                        .testTag("dict-entry-$entry")
                        .weight(1f, fill = true),
                )
                Box(
                    modifier = Modifier
                        .clickable { onRemove(entry) }
                        .padding(horizontal = 6.dp)
                        .testTag("dict-remove-$entry"),
                ) {
                    Text(
                        "REMOVE",
                        color = JRColor.terracotta,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = JRFont.sans,
                        letterSpacing = 0.66.sp,
                    )
                }
            }
        }

        SectionLabel("ADD")
        BasicTextField(
            value = draft,
            onValueChange = { draft = it },
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(4.dp))
                .background(JRColor.paperStrong)
                .padding(14.dp)
                .testTag("dict-add-text-field"),
            textStyle = TextStyle(
                color = JRColor.ink,
                fontSize = 18.sp,
                fontFamily = JRFont.serif,
            ),
            cursorBrush = SolidColor(JRColor.terracotta),
        )
        PrimaryButton(label = "ADD", testTag = "dict-add-confirm", onTap = {
            if (draft.isNotBlank()) {
                onAdd(draft)
                draft = ""
            }
        })
        Spacer(Modifier.height(48.dp))
    }
}
