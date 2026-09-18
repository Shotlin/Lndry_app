package com.lndry.app

import android.content.Context
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerClient.InstallReferrerResponse
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.plugin.common.MethodChannel

/**
 * Wraps Google's Play Install Referrer client so the Dart side (see
 * ReferralAttributionService) can read back a referral code carried
 * through a Play Store install link on first launch. Implemented directly
 * against the official com.android.installreferrer library rather than a
 * third-party Flutter plugin wrapper.
 */
class InstallReferrerBridge(private val context: Context) {
    fun getReferrer(result: MethodChannel.Result) {
        val client = InstallReferrerClient.newBuilder(context).build()
        client.startConnection(object : InstallReferrerStateListener {
            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                if (responseCode == InstallReferrerResponse.OK) {
                    try {
                        result.success(client.installReferrer.installReferrer)
                    } catch (e: Exception) {
                        result.success(null)
                    }
                } else {
                    // FEATURE_NOT_SUPPORTED / SERVICE_UNAVAILABLE / etc. —
                    // no Play Store on this device or nothing to report.
                    result.success(null)
                }
                client.endConnection()
            }

            override fun onInstallReferrerServiceDisconnected() {
                // No-op — this is a single one-shot read.
            }
        })
    }
}
