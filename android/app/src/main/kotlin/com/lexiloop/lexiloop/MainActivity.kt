package com.lexiloop.lexiloop

import android.content.ActivityNotFoundException
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pendingSharedText = extractSharedText(intent)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexiloop/system_speech_settings")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    startActivity(Intent("com.android.settings.TTS_SETTINGS"))
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    try {
                        startActivity(Intent(Settings.ACTION_SETTINGS))
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
            }

        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lexiloop/share_intent")
        shareChannel?.setMethodCallHandler { call, result ->
            if (call.method == "getInitialSharedText") {
                val text = pendingSharedText
                pendingSharedText = null
                result.success(text)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent) ?: return
        val channel = shareChannel
        if (channel != null) {
            channel.invokeMethod("onSharedText", text)
        } else {
            pendingSharedText = text
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        if (!type.startsWith("text/")) return null
        return intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()?.takeIf { it.isNotEmpty() }
    }
}
