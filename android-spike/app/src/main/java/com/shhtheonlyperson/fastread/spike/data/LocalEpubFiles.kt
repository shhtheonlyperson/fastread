package com.shhtheonlyperson.fastread.spike.data

import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.OpenableColumns
import java.io.File

data class LocalEpubFile(
    val file: File,
    val displayName: String,
    val locationName: String,
)

fun findLocalEpubFiles(context: Context): List<LocalEpubFile> {
    val roots = listOfNotNull(
        context.filesDir,
        context.getExternalFilesDir(null),
        context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS),
    )

    return roots
        .distinctBy { it.absolutePath }
        .flatMap { root ->
            root.walkTopDown()
                .maxDepth(2)
                .filter { it.isFile && it.extension.equals("epub", ignoreCase = true) }
                .map {
                    LocalEpubFile(
                        file = it,
                        displayName = it.nameWithoutExtension,
                        locationName = it.parentFile?.name?.uppercase() ?: "APP FILES",
                    )
                }
                .toList()
        }
        .sortedBy { it.displayName.lowercase() }
}

fun Context.displayName(uri: Uri): String? {
    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) {
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0) return cursor.getString(index)
        }
    }
    return uri.lastPathSegment
}
