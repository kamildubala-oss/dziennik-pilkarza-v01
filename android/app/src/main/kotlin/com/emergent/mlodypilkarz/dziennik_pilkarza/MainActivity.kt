package com.emergent.mlodypilkarz.dziennik_pilkarza

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Kanał "dziennik/files" - zapis kopii i eksportów na telefonie
 * (systemowe okno wyboru folderu), otwieranie kopii do przywrócenia
 * oraz udostępnianie pliku (e-mail, Dysk Google, komunikatory).
 * Nie wymaga żadnych uprawnień do pamięci.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "dziennik/files"
    private val reqSave = 4101
    private val reqOpen = 4102

    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "saveFile" -> {
                if (pendingResult != null) {
                    result.error("busy", "Trwa inna operacja na pliku", null)
                    return
                }
                val name = call.argument<String>("name") ?: "eksport.txt"
                val mime = call.argument<String>("mime") ?: "application/octet-stream"
                val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                pendingResult = result
                pendingBytes = bytes
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_TITLE, name)
                }
                try {
                    startActivityForResult(intent, reqSave)
                } catch (e: Exception) {
                    completePending(null, e)
                }
            }
            "openFile" -> {
                if (pendingResult != null) {
                    result.error("busy", "Trwa inna operacja na pliku", null)
                    return
                }
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf("application/json", "text/plain", "application/octet-stream")
                    )
                }
                try {
                    startActivityForResult(intent, reqOpen)
                } catch (e: Exception) {
                    completePending(null, e)
                }
            }
            "shareFile" -> {
                try {
                    val name = call.argument<String>("name") ?: "eksport.txt"
                    val mime = call.argument<String>("mime") ?: "application/octet-stream"
                    val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                    val dir = File(cacheDir, "exports").apply { mkdirs() }
                    val file = File(dir, name)
                    file.writeBytes(bytes)
                    val uri = FileProvider.getUriForFile(this, "$packageName.files", file)
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = mime
                        putExtra(Intent.EXTRA_STREAM, uri)
                        putExtra(Intent.EXTRA_SUBJECT, name)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(send, "Udostępnij plik"))
                    result.success(true)
                } catch (e: Exception) {
                    result.error("share_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun completePending(value: Any?, error: Exception? = null) {
        val r = pendingResult
        pendingResult = null
        pendingBytes = null
        if (r == null) return
        if (error != null) r.error("file_error", error.message, null) else r.success(value)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqSave && requestCode != reqOpen) return
        val uri: Uri? = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            completePending(null) // anulowano
            return
        }
        try {
            if (requestCode == reqSave) {
                val bytes = pendingBytes ?: ByteArray(0)
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                    ?: throw IllegalStateException("Nie można zapisać pliku")
                completePending(true)
            } else {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw IllegalStateException("Nie można odczytać pliku")
                completePending(bytes)
            }
        } catch (e: Exception) {
            completePending(null, e)
        }
    }
}
