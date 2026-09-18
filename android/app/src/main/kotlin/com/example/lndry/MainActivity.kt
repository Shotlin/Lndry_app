package com.lndry.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val installReferrerChannel = "com.lndry.app/install_referrer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installReferrerChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "getInstallReferrer") {
                    InstallReferrerBridge(applicationContext).getReferrer(result)
                } else {
                    result.notImplemented()
                }
            }
    }
}
