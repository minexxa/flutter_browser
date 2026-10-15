package com.example.flutter_android_browser

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.flutter_android_browser/volume"
    private var methodChannel: MethodChannel? = null

    /// 是否启用音量键翻页（由 Dart 侧设置同步）
    private var volumeScrollEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeScrollEnabled" -> {
                    volumeScrollEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "onVolumeKey" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (volumeScrollEnabled && isVolumeKey(keyCode)) {
            methodChannel?.invokeMethod(
                "onVolumeKey",
                mapOf("down" to (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN))
            )
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (volumeScrollEnabled && isVolumeKey(keyCode)) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun isVolumeKey(keyCode: Int): Boolean =
        keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP

    override fun onDestroy() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        super.onDestroy()
    }
}
