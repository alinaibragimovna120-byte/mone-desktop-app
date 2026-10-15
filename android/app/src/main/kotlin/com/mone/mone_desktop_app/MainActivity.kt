package com.mone.mone_desktop_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

/**
 * Принимает файлы, которыми поделились из других приложений
 * (Telegram, почта, «Файлы»…), и отдаёт их программе через канал
 * mone/shared_files.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    /** Скопированные файлы, которые программа ещё не забрала. */
    private val pending = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mone/shared_files",
        ).also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "takeFiles") {
                    result.success(ArrayList(pending))
                    pending.clear()
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // При пересоздании окна или запуске из «недавних» Android повторяет
        // прежний intent — тот файл уже добавлен.
        val fromHistory =
            intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0
        if (savedInstanceState == null && !fromHistory) {
            sharedDir().deleteRecursively()
            receive(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        receive(intent)
    }

    private fun sharedDir() = File(cacheDir, "shared")

    private fun receive(intent: Intent?) {
        val uris = intent?.let(::sharedUris).orEmpty()
        if (uris.isEmpty()) return
        // Файлы бывают большими — копируем не в главном потоке.
        Thread {
            val paths = uris.mapNotNull(::copyToCache)
            runOnUiThread {
                if (paths.isNotEmpty()) {
                    pending.addAll(paths)
                    channel?.invokeMethod("filesAvailable", null)
                }
            }
        }.start()
    }

    @Suppress("DEPRECATION")
    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableExtra(Intent.EXTRA_STREAM)
            },
        )
        Intent.ACTION_SEND_MULTIPLE -> (
            if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
        ).orEmpty()
        Intent.ACTION_VIEW -> listOfNotNull(intent.data)
        else -> emptyList()
    }

    /** Каждый файл — в своей папке, чтобы сохранить исходное имя. */
    private fun copyToCache(uri: Uri): String? = try {
        val target = File(File(sharedDir(), UUID.randomUUID().toString()), displayName(uri))
        target.parentFile!!.mkdirs()
        contentResolver.openInputStream(uri)!!.use { input ->
            target.outputStream().use { input.copyTo(it) }
        }
        target.path
    } catch (e: Exception) {
        null
    }

    private fun displayName(uri: Uri): String {
        val name = runCatching {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { if (it.moveToFirst()) it.getString(0) else null }
        }.getOrNull() ?: uri.lastPathSegment
        return name?.let { File(it).name }?.takeIf { it.isNotBlank() } ?: "Файл"
    }
}
