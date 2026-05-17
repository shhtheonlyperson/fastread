// Design tokens for the Android port. Colors are sourced from ~/DESIGN.md,
// with compatibility aliases kept for the first Android implementation names.

package com.shhtheonlyperson.fastread.spike.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.shhtheonlyperson.fastread.spike.R

object JRColor {
    val primary = Color(0xFFCC785C)
    val primaryActive = Color(0xFFA9583E)
    val primaryDisabled = Color(0xFFE6DFD8)
    val ink = Color(0xFF141413)
    val body = Color(0xFF3D3D3A)
    val bodyStrong = Color(0xFF252523)
    val muted = Color(0xFF6C6A64)
    val mutedSoft = Color(0xFF8E8B82)
    val hairline = Color(0xFFE6DFD8)
    val hairlineSoft = Color(0xFFEBE6DF)
    val canvas = Color(0xFFFAF9F5)
    val surfaceSoft = Color(0xFFF5F0E8)
    val surfaceCard = Color(0xFFEFE9DE)
    val surfaceCreamStrong = Color(0xFFE8E0D2)
    val surfaceDark = Color(0xFF181715)
    val surfaceDarkElevated = Color(0xFF252320)
    val surfaceDarkSoft = Color(0xFF1F1E1B)
    val onPrimary = Color(0xFFFFFFFF)
    val onDark = Color(0xFFFAF9F5)
    val onDarkSoft = Color(0xFFA09D96)
    val accentTeal = Color(0xFF5DB8A6)
    val accentAmber = Color(0xFFE8A55A)
    val success = Color(0xFF5DB872)
    val warning = Color(0xFFD4A017)
    val error = Color(0xFFC64545)

    val paper = canvas
    val paperStrong = surfaceSoft
    val paperDeep = surfaceCard
    val inkMid = body
    val inkQuiet = muted
    val rule = hairline
    val ruleStrong = surfaceCreamStrong
    val terracotta = primary
    val focusDark = surfaceDark
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
