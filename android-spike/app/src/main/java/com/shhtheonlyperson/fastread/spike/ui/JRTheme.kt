// Design tokens for the Android port. Exact 1:1 mirror of the iOS
// JRColor/JRFont enums in FastReadApp/DesignSystem.swift, sourced from
// the design-handoff README (the cream-paper editorial palette is the
// product personality, not a placeholder).

package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.shhtheonlyperson.fastread.spike.R

object JRColor {
    val paper = Color(0xFFF5EFE2)
    val paperStrong = Color(0xFFFAF6EC)
    val paperDeep = Color(0xFFECE4D2)
    val ink = Color(0xFF1F1A17)
    val inkMid = Color(0xFF4A3F37)
    val inkQuiet = Color(0xFF8A7A6A)
    val rule = Color(0x14_1F_1A_17.toInt())          // rgba(0x1F1A17, 0.08)
    val ruleStrong = Color(0x2E_1F_1A_17.toInt())    // rgba(0x1F1A17, 0.18)
    val terracotta = Color(0xFFC96442)
    val focusDark = Color(0xFF1C1714)
}

object JRFont {
    val serif = FontFamily(
        Font(R.font.fraunces, FontWeight.Normal),
        Font(R.font.fraunces, FontWeight.Medium),
        Font(R.font.fraunces, FontWeight.SemiBold),
        Font(R.font.fraunces, FontWeight.Bold),
    )
    val sans = FontFamily(
        Font(R.font.inter, FontWeight.Normal),
        Font(R.font.inter, FontWeight.Medium),
        Font(R.font.inter, FontWeight.SemiBold),
        Font(R.font.inter, FontWeight.Bold),
    )
    val mono = FontFamily(
        Font(R.font.jetbrains_mono, FontWeight.Normal),
        Font(R.font.jetbrains_mono, FontWeight.Medium),
    )
}
