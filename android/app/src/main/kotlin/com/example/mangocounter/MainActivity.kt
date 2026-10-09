package com.example.mangocounter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.MediaMetadataRetriever
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val metadataExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mangocounter/video")
            .setMethodCallHandler { call, result ->
                if (call.method != "durationMs") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_PATH", "A video path is required", null)
                    return@setMethodCallHandler
                }
                metadataExecutor.execute {
                    val retriever = MediaMetadataRetriever()
                    try {
                        retriever.setDataSource(path)
                        val duration = retriever.extractMetadata(
                            MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                        if (duration == null || duration <= 0) {
                            throw IllegalArgumentException("Unable to read video duration")
                        }
                        runOnUiThread { result.success(duration) }
                    } catch (error: Exception) {
                        runOnUiThread { result.error("VIDEO_METADATA", error.message, null) }
                    } finally {
                        retriever.release()
                    }
                }
            }
    }

    override fun onDestroy() {
        metadataExecutor.shutdown()
        super.onDestroy()
    }
}
