package com.jaram.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.jaram.app/back"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )
    }

    @Deprecated("System back is forwarded to Dart via MethodChannel")
    @Suppress("OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        val ch = methodChannel
        if (ch == null) {
            @Suppress("DEPRECATION")
            super.onBackPressed()
            return
        }
        ch.invokeMethod("onBackPressed", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (result != true) {
                    @Suppress("DEPRECATION")
                    super@MainActivity.onBackPressed()
                }
            }
            override fun error(code: String, message: String?, details: Any?) {
                @Suppress("DEPRECATION")
                super@MainActivity.onBackPressed()
            }
            override fun notImplemented() {
                @Suppress("DEPRECATION")
                super@MainActivity.onBackPressed()
            }
        })
    }
}
