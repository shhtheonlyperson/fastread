package com.shhtheonlyperson.fastread.spike.data

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.shhtheonlyperson.fastread.spike.core.RSVPEngine
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale
import java.util.UUID
import kotlin.math.ceil
import kotlin.math.roundToInt

class Persistence(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("justread_v1", Context.MODE_PRIVATE)

    var articles: List<ReadingArticle> by mutableStateOf(loadArticles())
        private set
    var selectedArticleId: String? by mutableStateOf(prefs.getString(StorageKey.selectedArticle, null))
        private set
    var stats: ReadingStats by mutableStateOf(loadStats())
        private set
    var wpm: Int by mutableIntStateOf(normalizedWPM(loadWPM()))
        private set
    var punctuationPause: Boolean by mutableStateOf(loadPunctuationPause())
        private set
    var focusIndicator: FocusIndicatorStyle by mutableStateOf(loadFocusIndicator())
        private set
    var dictionary: List<String> by mutableStateOf(loadDictionary())
        private set

    val currentArticle: ReadingArticle?
        get() = selectedArticleId
            ?.let { id -> articles.firstOrNull { it.id == id } }
            ?: articles.firstOrNull()

    val recentSources: List<RecentSource>
        get() {
            val seen = mutableSetOf<String>()
            return articles.mapNotNull { article ->
                val label = article.source.trim()
                if (label.isBlank() || label == "Clipboard") return@mapNotNull null
                val key = (article.sourceUrl ?: label).lowercase()
                if (!seen.add(key)) return@mapNotNull null
                RecentSource(
                    label = label,
                    date = relativeDateLabel(article.createdAt),
                    url = article.sourceUrl,
                )
            }.take(5)
        }

    init {
        ensureSelectedArticle()
        rollStatsIfNeeded()
        persistSettings()
    }

    fun openArticle(id: String, resume: Boolean) {
        if (articles.none { it.id == id }) return
        selectedArticleId = id
        persistSelectedArticle()
        updateArticle(id) { article ->
            article.copy(
                timesOpened = article.timesOpened + 1,
                lastOpenedAt = nowMillis(),
                wordIndex = if (resume) article.wordIndex else 0,
                progress = if (resume || article.isFinished) article.progress else 0.0,
            )
        }
    }

    fun setWPM(value: Int) {
        val next = normalizedWPM(value)
        if (next == wpm) return
        wpm = next
        persistSettings()
    }

    fun updatePunctuationPause(value: Boolean) {
        punctuationPause = value
        persistSettings()
    }

    fun updateFocusIndicator(value: FocusIndicatorStyle) {
        focusIndicator = value
        persistSettings()
    }

    fun addToUserDictionary(entry: String) {
        val trimmed = entry.trim()
        if (trimmed.isBlank() || dictionary.contains(trimmed)) return
        dictionary = dictionary + trimmed
        invalidateTokenCaches()
        persistDictionary()
    }

    fun removeFromUserDictionary(entry: String) {
        if (!dictionary.contains(entry)) return
        dictionary = dictionary.filterNot { it == entry }
        invalidateTokenCaches()
        persistDictionary()
    }

    fun addTextArticle(text: String, title: String = "Pasted text", source: String = "Clipboard", sourceUrl: String? = null): ReadingArticle? {
        val normalized = ArticleTextExtractor.normalize(text)
        if (normalized.isBlank()) return null
        return addArticle(
            title = title,
            source = source,
            sourceUrl = sourceUrl,
            author = "You",
            text = normalized,
        )
    }

    fun addFetchedArticle(result: ArticleFetchResult): ReadingArticle? = addArticle(
        title = result.title,
        source = result.source,
        sourceUrl = result.url,
        author = "Web",
        text = result.text,
    )

    fun addEpubArticle(displayName: String, text: String): ReadingArticle? {
        val title = displayName.substringBeforeLast('.').ifBlank { "EPUB" }
        return addArticle(
            title = title,
            source = displayName,
            sourceUrl = null,
            author = "EPUB",
            text = ArticleTextExtractor.normalize(text),
        )
    }

    fun deleteArticle(id: String) {
        val index = articles.indexOfFirst { it.id == id }
        if (index < 0) return
        articles = articles.filterNot { it.id == id }
        if (selectedArticleId == id) {
            selectedArticleId = articles.getOrNull(index)?.id ?: articles.lastOrNull()?.id
            persistSelectedArticle()
        }
        persistArticles()
    }

    fun tokensFor(article: ReadingArticle): List<String> {
        val (updated, tokens) = ensureTokens(article)
        if (updated != article) {
            replaceArticle(updated)
        }
        return tokens
    }

    fun wordCount(article: ReadingArticle): Int = tokensFor(article).count()

    fun setCurrentIndex(index: Int, recordReadWord: Boolean = false) {
        val id = currentArticle?.id ?: return
        updateArticle(id) { article ->
            article.copy(wordIndex = index, isFinished = false, finishedAt = null)
        }
        if (recordReadWord) recordReadWords(1)
    }

    fun markRead() {
        val article = currentArticle ?: return
        val wasFinished = article.isFinished
        val count = tokensFor(article).count()
        updateArticle(article.id) {
            it.copy(
                wordIndex = maxOf(count - 1, 0),
                progress = 1.0,
                isFinished = true,
                finishedAt = nowMillis(),
                tag = "Finished",
            )
        }
        if (!wasFinished) recordFinishedArticle()
    }

    fun scrubTo(progress: Float): Int {
        val article = currentArticle ?: return 0
        val count = tokensFor(article).count()
        val target = (progress.coerceIn(0f, 1f) * maxOf(count - 1, 0)).roundToInt()
        setCurrentIndex(target)
        return target
    }

    private fun addArticle(
        title: String,
        source: String,
        sourceUrl: String?,
        author: String,
        text: String,
    ): ReadingArticle? {
        val trimmed = text.trim()
        if (trimmed.isBlank()) return null
        val tokens = RSVPEngine.tokenize(trimmed, userDictionary = dictionary)
        val now = nowMillis()
        val article = ReadingArticle(
            id = "draft-${UUID.randomUUID()}",
            title = title.ifBlank { "Pasted text" },
            source = source.ifBlank { "Clipboard" },
            sourceUrl = sourceUrl,
            author = author.ifBlank { "You" },
            date = displayDate(now),
            createdAt = now,
            lastOpenedAt = now,
            finishedAt = null,
            readTime = "${estimatedMinutes(tokens.count(), wpm)} min",
            lede = ArticleTextExtractor.makeLede(trimmed, tokens),
            tag = "Reading now",
            text = trimmed,
            progress = 0.0,
            wordIndex = 0,
            timesOpened = 1,
            isFinished = false,
            tokens = tokens,
            tokenizerVersion = RSVPEngine.VERSION,
        )
        articles = listOf(article) + articles
        selectedArticleId = article.id
        persistSelectedArticle()
        persistArticles()
        return article
    }

    private fun updateArticle(id: String, mutate: (ReadingArticle) -> ReadingArticle) {
        var changed = false
        articles = articles.map { article ->
            if (article.id != id) return@map article
            val (withTokens, tokens) = ensureTokens(mutate(article))
            val clampedIndex = withTokens.wordIndex.coerceIn(0, maxOf(tokens.count() - 1, 0))
            val progress = if (tokens.isEmpty()) 0.0 else (clampedIndex + 1).toDouble() / tokens.count().toDouble()
            changed = true
            withTokens.copy(
                wordIndex = clampedIndex,
                progress = if (withTokens.isFinished) 1.0 else progress,
                tag = if (withTokens.isFinished) "Finished" else if (progress > 0) "Reading now" else "Saved",
            )
        }
        if (changed) persistArticles()
    }

    private fun replaceArticle(updated: ReadingArticle) {
        articles = articles.map { if (it.id == updated.id) updated else it }
        persistArticles()
    }

    private fun ensureTokens(article: ReadingArticle): Pair<ReadingArticle, List<String>> {
        val validTokens = article.tokens
        if (validTokens != null && article.tokenizerVersion == RSVPEngine.VERSION) {
            return article to validTokens
        }
        val fresh = RSVPEngine.tokenize(article.text, userDictionary = dictionary)
        return article.copy(tokens = fresh, tokenizerVersion = RSVPEngine.VERSION) to fresh
    }

    private fun invalidateTokenCaches() {
        articles = articles.map { it.copy(tokens = null, tokenizerVersion = null) }
        persistArticles()
    }

    private fun recordReadWords(count: Int) {
        if (count <= 0) return
        startActivityIfNeeded()
        val todayKey = dayKey(LocalDate.now())
        stats = stats.copy(
            today = stats.today.copy(
                words = stats.today.words + count,
                minutes = estimatedMinutes(stats.today.words + count, wpm),
            ),
            week = stats.week.map { day ->
                if (day.date == todayKey) day.copy(words = day.words + count) else day
            },
            avgWPM = wpm,
            bestWPM = maxOf(stats.bestWPM, wpm),
        )
        persistStats()
    }

    private fun recordFinishedArticle() {
        startActivityIfNeeded()
        stats = stats.copy(
            today = stats.today.copy(
                articles = stats.today.articles + 1,
                minutes = estimatedMinutes(stats.today.words, wpm),
            ),
            totalArticles = stats.totalArticles + 1,
            avgWPM = wpm,
            bestWPM = maxOf(stats.bestWPM, wpm),
        )
        persistStats()
    }

    private fun startActivityIfNeeded(now: LocalDate = LocalDate.now()) {
        rollStatsIfNeeded(now)
        val todayKey = dayKey(now)
        val activeToday = stats.lastActiveDay == todayKey && (stats.today.words > 0 || stats.today.articles > 0)
        if (activeToday) return
        val previous = stats.lastActiveDay?.let(LocalDate::parse)
        val streak = if (previous == now.minusDays(1)) stats.streak + 1 else 1
        stats = stats.copy(streak = streak, lastActiveDay = todayKey)
    }

    private fun rollStatsIfNeeded(now: LocalDate = LocalDate.now()) {
        val todayKey = dayKey(now)
        val wordsByDay = stats.week.mapNotNull { day -> day.date?.let { it to day.words } }.toMap()
        val week = weekTemplate(now).map { day ->
            day.copy(words = wordsByDay[day.date] ?: 0)
        }
        val today = if (stats.lastActiveDay != todayKey) {
            TodayStats(words = wordsByDay[todayKey] ?: 0, minutes = 0, articles = 0)
        } else {
            stats.today.copy(words = week.firstOrNull { it.date == todayKey }?.words ?: stats.today.words)
        }
        stats = stats.copy(
            today = today.copy(minutes = estimatedMinutes(today.words, wpm)),
            week = week,
        )
        persistStats()
    }

    private fun ensureSelectedArticle() {
        if (selectedArticleId != null && articles.any { it.id == selectedArticleId }) return
        selectedArticleId = articles.firstOrNull()?.id
        persistSelectedArticle()
    }

    private fun loadArticles(): List<ReadingArticle> {
        val raw = prefs.getString(StorageKey.articles, null)
        if (!raw.isNullOrBlank()) {
            runCatching {
                val array = JSONArray(raw)
                return (0 until array.length()).mapNotNull { index ->
                    array.optJSONObject(index)?.let(ReadingArticle::fromJson)
                }
            }
        }

        val legacyText = prefs.getString(LegacyKey.article, "").orEmpty()
        if (legacyText.isBlank()) return emptyList()
        val normalized = ArticleTextExtractor.normalize(legacyText)
        val tokens = prefs.getString(LegacyKey.tokens, null)
            ?.split(LegacyKey.tokenSeparator)
            ?.takeIf { it.isNotEmpty() }
            ?: RSVPEngine.tokenize(normalized, userDictionary = loadDictionary())
        val now = nowMillis()
        return listOf(
            ReadingArticle(
                id = "legacy-${UUID.randomUUID()}",
                title = "Pasted text",
                source = "Clipboard",
                sourceUrl = null,
                author = "You",
                date = displayDate(now),
                createdAt = now,
                lastOpenedAt = now,
                finishedAt = null,
                readTime = "${estimatedMinutes(tokens.count(), wpm = normalizedWPM(loadWPM()))} min",
                lede = ArticleTextExtractor.makeLede(normalized, tokens),
                tag = "Reading now",
                text = normalized,
                progress = 0.0,
                wordIndex = prefs.getInt(LegacyKey.index, 0),
                timesOpened = 1,
                isFinished = false,
                tokens = tokens,
                tokenizerVersion = prefs.takeIf { it.contains(LegacyKey.tokenizerVersion) }?.getInt(LegacyKey.tokenizerVersion, -1),
            ),
        )
    }

    private fun loadStats(): ReadingStats {
        val raw = prefs.getString(StorageKey.stats, null) ?: return emptyStats()
        return runCatching {
            val loaded = ReadingStats.fromJson(JSONObject(raw))
            if (loaded.week.all { it.date != null }) loaded else emptyStats()
        }.getOrElse { emptyStats() }
    }

    private fun loadWPM(): Int = runCatching {
        prefs.getString(StorageKey.settings, null)
            ?.let { JSONObject(it).optInt("wpm", 550) }
            ?: prefs.getInt(LegacyKey.wpm, 550)
    }.getOrDefault(550)

    private fun loadPunctuationPause(): Boolean = runCatching {
        prefs.getString(StorageKey.settings, null)
            ?.let { JSONObject(it).optBoolean("punctuationPause", true) }
            ?: true
    }.getOrDefault(true)

    private fun loadFocusIndicator(): FocusIndicatorStyle = runCatching {
        val raw = prefs.getString(StorageKey.settings, null)
            ?.let { JSONObject(it).optString("focusIndicator") }
        FocusIndicatorStyle.fromStored(raw)
    }.getOrDefault(FocusIndicatorStyle.Dot)

    private fun loadDictionary(): List<String> {
        val newRaw = prefs.getString(StorageKey.dictionary, null)
        if (!newRaw.isNullOrBlank()) {
            return runCatching {
                val array = JSONArray(newRaw)
                (0 until array.length()).map { array.getString(it).trim() }
                    .filter { it.isNotBlank() }
                    .distinct()
            }.getOrDefault(emptyList())
        }
        return prefs.getString(LegacyKey.dictionary, "")
            ?.split('\n')
            ?.map { it.trim() }
            ?.filter { it.isNotBlank() }
            ?.distinct()
            ?: emptyList()
    }

    private fun persistArticles() {
        prefs.edit()
            .putString(StorageKey.articles, JSONArray().also { array ->
                articles.forEach { array.put(it.toJson()) }
            }.toString())
            .apply()
    }

    private fun persistStats() {
        prefs.edit().putString(StorageKey.stats, stats.toJson().toString()).apply()
    }

    private fun persistSettings() {
        prefs.edit().putString(
            StorageKey.settings,
            JSONObject()
                .put("wpm", wpm)
                .put("punctuationPause", punctuationPause)
                .put("focusIndicator", focusIndicator.name)
                .toString(),
        ).apply()
    }

    private fun persistDictionary() {
        prefs.edit().putString(
            StorageKey.dictionary,
            JSONArray().also { array -> dictionary.forEach { array.put(it) } }.toString(),
        ).apply()
    }

    private fun persistSelectedArticle() {
        val edit = prefs.edit()
        if (selectedArticleId == null) edit.remove(StorageKey.selectedArticle)
        else edit.putString(StorageKey.selectedArticle, selectedArticleId)
        edit.apply()
    }

    companion object {
        private object StorageKey {
            const val settings = "justread.settings.v1.android"
            const val articles = "justread.articles.v1.android"
            const val stats = "justread.stats.v1.android"
            const val selectedArticle = "justread.selectedArticle.v1.android"
            const val dictionary = "justread.userDictionary.v1.android"
        }

        private object LegacyKey {
            const val article = "article"
            const val wpm = "wpm"
            const val index = "index"
            const val dictionary = "dictionary"
            const val tokens = "tokens"
            const val tokenizerVersion = "tokenizerVersion"
            const val tokenSeparator = '\u0001'
        }

        fun normalizedWPM(value: Int): Int {
            val clamped = value.coerceIn(300, RSVPEngine.MAXIMUM_WPM.toInt())
            return ((((clamped - 300) / 50.0).roundToInt() * 50) + 300)
                .coerceIn(300, RSVPEngine.MAXIMUM_WPM.toInt())
        }

        private fun nowMillis(): Long = System.currentTimeMillis()

        private fun emptyStats(date: LocalDate = LocalDate.now()): ReadingStats =
            ReadingStats(week = weekTemplate(date))

        private fun weekTemplate(endingAt: LocalDate): List<DayWords> =
            (6 downTo 0).map { offset ->
                val day = endingAt.minusDays(offset.toLong())
                DayWords(
                    date = dayKey(day),
                    day = day.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault()),
                    words = 0,
                )
            }

        private fun dayKey(day: LocalDate): String = day.toString()

        private fun displayDate(millis: Long): String {
            val date = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()
            return date.format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US))
        }

        private fun relativeDateLabel(millis: Long): String {
            val date = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()
            val today = LocalDate.now()
            val days = java.time.temporal.ChronoUnit.DAYS.between(date, today).toInt()
            return when (days) {
                in Int.MIN_VALUE..0 -> "Today"
                1 -> "Yesterday"
                in 2..6 -> "${days}d ago"
                else -> date.format(DateTimeFormatter.ofPattern("MMM d", Locale.US))
            }
        }

        private fun estimatedMinutes(words: Int, wpm: Int): Int {
            if (words <= 0) return 0
            return maxOf(1, ceil(words.toDouble() / wpm.toDouble()).toInt())
        }
    }
}
