package com.shhtheonlyperson.fastread.spike.data

import com.shhtheonlyperson.fastread.spike.core.RSVPEngine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

data class ArticleFetchResult(
    val title: String,
    val source: String,
    val url: String,
    val text: String,
    val wordCount: Int,
)

enum class ArticleFetchError(val messageText: String) {
    InvalidUrl("Enter a valid http(s) URL."),
    HttpError("Fetch failed."),
    Oversized("Page is too large to extract."),
    UnsupportedContentType("Unsupported content type."),
    Timeout("Fetching the page timed out."),
}

object SourceInputClassifier {
    private val whitespaceRegex = Regex("\\s+")

    fun isLikelySingleUrl(input: String): Boolean =
        normalizedUrlString(input) != null && !input.trim().contains(whitespaceRegex)

    fun normalizedUrlString(input: String): String? {
        val trimmed = input.trim()
        if (trimmed.isBlank()) return null
        val candidate = if (trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true)
        ) {
            trimmed
        } else if (trimmed.contains(".") && !trimmed.contains(whitespaceRegex)) {
            "https://$trimmed"
        } else {
            return null
        }
        return runCatching {
            val url = URL(candidate)
            val scheme = url.protocol.lowercase()
            if (scheme == "http" || scheme == "https") url.toString() else null
        }.getOrNull()
    }
}

object ArticleFetcher {
    private const val MAX_BYTES = 6 * 1024 * 1024

    suspend fun fetch(urlString: String): Result<ArticleFetchResult> = withContext(Dispatchers.IO) {
        runCatching {
            val normalized = SourceInputClassifier.normalizedUrlString(urlString)
                ?: throw FetchException(ArticleFetchError.InvalidUrl)
            val connection = (URL(normalized).openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000
                readTimeout = 15_000
                instanceFollowRedirects = true
                requestMethod = "GET"
                setRequestProperty("Accept", "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.2")
                setRequestProperty("User-Agent", "Mozilla/5.0 JustRead Android reader")
            }

            try {
                val status = connection.responseCode
                if (status !in 200..299) {
                    throw FetchException(ArticleFetchError.HttpError, "Fetch failed with HTTP $status.")
                }
                val contentLength = connection.contentLengthLong
                if (contentLength > MAX_BYTES) throw FetchException(ArticleFetchError.Oversized)
                val contentType = connection.contentType.orEmpty()
                if (contentType.isNotBlank() &&
                    !contentType.contains("text/html", ignoreCase = true) &&
                    !contentType.contains("application/xhtml+xml", ignoreCase = true) &&
                    !contentType.contains("text/plain", ignoreCase = true)
                ) {
                    throw FetchException(ArticleFetchError.UnsupportedContentType, "Unsupported content type: $contentType")
                }

                val raw = connection.inputStream.use { input ->
                    val out = ByteArrayOutputStream()
                    val buffer = ByteArray(16 * 1024)
                    var total = 0
                    while (true) {
                        val read = input.read(buffer)
                        if (read == -1) break
                        total += read
                        if (total > MAX_BYTES) throw FetchException(ArticleFetchError.Oversized)
                        out.write(buffer, 0, read)
                    }
                    out.toByteArray().toString(Charsets.UTF_8)
                }
                val text = ArticleTextExtractor.readableText(raw)
                val tokens = RSVPEngine.tokenize(text)
                val url = connection.url?.toString() ?: normalized
                ArticleFetchResult(
                    title = ArticleTextExtractor.extractTitle(raw)
                        ?: URL(url).host
                        ?: "Fetched article",
                    source = URL(url).host ?: "Web",
                    url = url,
                    text = text,
                    wordCount = tokens.count(),
                )
            } catch (error: java.net.SocketTimeoutException) {
                throw FetchException(ArticleFetchError.Timeout)
            } finally {
                connection.disconnect()
            }
        }.recoverCatching { error ->
            if (error is FetchException) throw error
            throw FetchException(ArticleFetchError.HttpError, error.message ?: ArticleFetchError.HttpError.messageText)
        }
    }
}

class FetchException(
    val reason: ArticleFetchError,
    override val message: String = reason.messageText,
) : Exception(message)
