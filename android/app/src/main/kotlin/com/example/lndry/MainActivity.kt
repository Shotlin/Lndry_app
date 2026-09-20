package com.lndry.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val installReferrerChannel = "com.lndry.app/install_referrer"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createPushChannel()
    }

    /** High-importance channel the backend sends every push on (channelId lndry_notifications). */
    private fun createPushChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "lndry_notifications",
                "LNDRY notifications",
                NotificationManager.IMPORTANCE_HIGH
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

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
