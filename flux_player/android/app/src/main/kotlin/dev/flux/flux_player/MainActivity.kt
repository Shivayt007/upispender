package dev.flux.flux_player

import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        @Volatile private var eventSink: EventChannel.EventSink? = null
        fun emit(data: Map<String, Any?>) {
            Handler(Looper.getMainLooper()).post { eventSink?.success(data) }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "flux/events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }
                override fun onCancel(arguments: Any?) { eventSink = null }
            })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "flux/native")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "list" -> result.success(DownloadService.list(this))
                        "enqueue", "pause", "resume", "cancel" -> {
                            val command = call.method
                            if (command == "enqueue") {
                                val url = call.argument<String>("url") ?: ""
                                val uri = android.net.Uri.parse(url)
                                if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrEmpty()) {
                                    result.error("URL", "HTTP or HTTPS URL is required", null)
                                    return@setMethodCallHandler
                                }
                            }
                            val intent = Intent(this, DownloadService::class.java)
                            intent.action = command
                            intent.putExtra("id", call.argument<String>("id"))
                            intent.putExtra("url", call.argument<String>("url"))
                            intent.putExtra("name", call.argument<String>("name"))
                            intent.putExtra("parts", call.argument<Int>("parts") ?: 8)
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
                            else startService(intent)
                            result.success(null)
                        }
                        "brightness" -> {
                            val value = (call.argument<Double>("value") ?: 0.5).toFloat().coerceIn(.02f, 1f)
                            val settings = window.attributes
                            settings.screenBrightness = value
                            window.attributes = settings
                            result.success(null)
                        }
                        "resetBrightness" -> {
                            val settings = window.attributes
                            settings.screenBrightness = -1f
                            window.attributes = settings
                            result.success(null)
                        }
                        "volume" -> {
                            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val level = ((call.argument<Double>("value") ?: .5) * max).toInt().coerceIn(0, max)
                            audio.setStreamVolume(AudioManager.STREAM_MUSIC, level, 0)
                            result.success(null)
                        }
                        "getVolume" -> {
                            val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                            result.success(audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() /
                                    audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("NATIVE", e.message, null)
                }
            }
    }
}
