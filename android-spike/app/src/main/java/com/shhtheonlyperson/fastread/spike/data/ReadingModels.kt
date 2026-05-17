package com.shhtheonlyperson.fastread.spike.data

import org.json.JSONArray
import org.json.JSONObject

enum class FocusIndicatorStyle(val label: String) {
    Dot("Dots"),
    Line("Line"),
    Crosshair("Crosshair");

    companion object {
        fun fromStored(value: String?): FocusIndicatorStyle =
            entries.firstOrNull { it.name == value } ?: Dot
    }
}

data class DayWords(
    val date: String? = null,
    val day: String,
    val words: Int,
) {
    fun toJson(): JSONObject = JSONObject()
        .putOpt("date", date)
        .put("day", day)
        .put("words", words)

    companion object {
        fun fromJson(json: JSONObject): DayWords = DayWords(
            date = json.optString("date").takeIf { it.isNotBlank() },
            day = json.optString("day"),
            words = json.optInt("words"),
        )
    }
}

data class TodayStats(
    val words: Int = 0,
    val minutes: Int = 0,
    val articles: Int = 0,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("words", words)
        .put("minutes", minutes)
        .put("articles", articles)

    companion object {
        fun fromJson(json: JSONObject): TodayStats = TodayStats(
            words = json.optInt("words"),
            minutes = json.optInt("minutes"),
            articles = json.optInt("articles"),
        )
    }
}

data class ReadingStats(
    val today: TodayStats = TodayStats(),
    val week: List<DayWords> = emptyList(),
    val streak: Int = 0,
    val avgWPM: Int = 0,
    val bestWPM: Int = 0,
    val totalArticles: Int = 0,
    val lastActiveDay: String? = null,
) {
    val weekTotal: Int get() = week.sumOf { it.words }

    fun toJson(): JSONObject = JSONObject()
        .put("today", today.toJson())
        .put("week", JSONArray().also { array -> week.forEach { array.put(it.toJson()) } })
        .put("streak", streak)
        .put("avgWPM", avgWPM)
        .put("bestWPM", bestWPM)
        .put("totalArticles", totalArticles)
        .putOpt("lastActiveDay", lastActiveDay)

    companion object {
        fun fromJson(json: JSONObject): ReadingStats {
            val weekJson = json.optJSONArray("week") ?: JSONArray()
            return ReadingStats(
                today = json.optJSONObject("today")?.let(TodayStats::fromJson) ?: TodayStats(),
                week = (0 until weekJson.length()).mapNotNull { index ->
                    weekJson.optJSONObject(index)?.let(DayWords::fromJson)
                },
                streak = json.optInt("streak"),
                avgWPM = json.optInt("avgWPM"),
                bestWPM = json.optInt("bestWPM"),
                totalArticles = json.optInt("totalArticles"),
                lastActiveDay = json.optString("lastActiveDay").takeIf { it.isNotBlank() },
            )
        }
    }
}

data class RecentSource(
    val label: String,
    val date: String,
    val url: String?,
)

data class ReadingArticle(
    val id: String,
    val title: String,
    val source: String,
    val sourceUrl: String?,
    val author: String,
    val date: String,
    val createdAt: Long,
    val lastOpenedAt: Long,
    val finishedAt: Long?,
    val readTime: String,
    val lede: String,
    val tag: String,
    val text: String,
    val progress: Double,
    val wordIndex: Int,
    val timesOpened: Int,
    val isFinished: Boolean,
    val tokens: List<String>? = null,
    val tokenizerVersion: Int? = null,
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("title", title)
        .put("source", source)
        .putOpt("sourceUrl", sourceUrl)
        .put("author", author)
        .put("date", date)
        .put("createdAt", createdAt)
        .put("lastOpenedAt", lastOpenedAt)
        .putOpt("finishedAt", finishedAt)
        .put("readTime", readTime)
        .put("lede", lede)
        .put("tag", tag)
        .put("text", text)
        .put("progress", progress)
        .put("wordIndex", wordIndex)
        .put("timesOpened", timesOpened)
        .put("isFinished", isFinished)
        .putOpt("tokens", tokens?.let { values ->
            JSONArray().also { array -> values.forEach { array.put(it) } }
        })
        .putOpt("tokenizerVersion", tokenizerVersion)

    companion object {
        fun fromJson(json: JSONObject): ReadingArticle = ReadingArticle(
            id = json.getString("id"),
            title = json.optString("title", "Pasted text"),
            source = json.optString("source", "Clipboard"),
            sourceUrl = json.optString("sourceUrl").takeIf { it.isNotBlank() },
            author = json.optString("author", "You"),
            date = json.optString("date"),
            createdAt = json.optLong("createdAt"),
            lastOpenedAt = json.optLong("lastOpenedAt", json.optLong("createdAt")),
            finishedAt = if (json.has("finishedAt") && !json.isNull("finishedAt")) json.optLong("finishedAt") else null,
            readTime = json.optString("readTime", "1 min"),
            lede = json.optString("lede"),
            tag = json.optString("tag", "Saved"),
            text = json.optString("text"),
            progress = json.optDouble("progress"),
            wordIndex = json.optInt("wordIndex"),
            timesOpened = json.optInt("timesOpened"),
            isFinished = json.optBoolean("isFinished"),
            tokens = json.optJSONArray("tokens")?.toStringList(),
            tokenizerVersion = if (json.has("tokenizerVersion") && !json.isNull("tokenizerVersion")) {
                json.optInt("tokenizerVersion")
            } else {
                null
            },
        )

        private fun JSONArray.toStringList(): List<String> =
            (0 until length()).map { getString(it) }
    }
}
