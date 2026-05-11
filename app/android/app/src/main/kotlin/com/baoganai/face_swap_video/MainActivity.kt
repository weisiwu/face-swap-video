package com.baoganai.face_swap_video

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.baoganai.face_swap_video/device_phone"
    private val requestPhoneNumberCode = 9301
    private var pendingPhoneResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPrimarySimPhoneNumber" -> getPrimarySimPhoneNumber(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun getPrimarySimPhoneNumber(result: MethodChannel.Result) {
        if (!hasPhonePermission()) {
            if (pendingPhoneResult != null) {
                result.error("REQUEST_IN_PROGRESS", "Phone number permission request is already in progress", null)
                return
            }
            pendingPhoneResult = result
            ActivityCompat.requestPermissions(this, requiredPhonePermissions(), requestPhoneNumberCode)
            return
        }
        result.success(readPrimarySimPhoneNumber())
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != requestPhoneNumberCode) return

        val result = pendingPhoneResult ?: return
        pendingPhoneResult = null
        if (grantResults.any { it == PackageManager.PERMISSION_GRANTED }) {
            result.success(readPrimarySimPhoneNumber())
        } else {
            result.success(null)
        }
    }

    private fun hasPhonePermission(): Boolean {
        return requiredPhonePermissions().any { permission ->
            ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requiredPhonePermissions(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            arrayOf(Manifest.permission.READ_PHONE_NUMBERS, Manifest.permission.READ_PHONE_STATE)
        } else {
            arrayOf(Manifest.permission.READ_PHONE_STATE)
        }
    }

    private fun readPrimarySimPhoneNumber(): String? {
        val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as SubscriptionManager
        val activeSubscriptions = try {
            subscriptionManager.activeSubscriptionInfoList.orEmpty()
        } catch (_: SecurityException) {
            emptyList()
        }
        if (activeSubscriptions.isEmpty()) return null

        val primarySubscription = pickPrimarySubscription(activeSubscriptions)
        return readPhoneNumber(subscriptionManager, primarySubscription.subscriptionId)
            ?.takeIf { it.isNotBlank() }
    }

    private fun pickPrimarySubscription(activeSubscriptions: List<SubscriptionInfo>): SubscriptionInfo {
        val defaultIds = listOf(
            SubscriptionManager.getDefaultDataSubscriptionId(),
            SubscriptionManager.getDefaultVoiceSubscriptionId(),
            SubscriptionManager.getDefaultSmsSubscriptionId(),
        ).filter { id -> id != SubscriptionManager.INVALID_SUBSCRIPTION_ID }

        for (defaultId in defaultIds) {
            activeSubscriptions.firstOrNull { it.subscriptionId == defaultId }?.let { return it }
        }

        return activeSubscriptions.minWithOrNull(
            compareBy<SubscriptionInfo> { it.simSlotIndex }.thenBy { it.subscriptionId },
        ) ?: activeSubscriptions.first()
    }

    private fun readPhoneNumber(
        subscriptionManager: SubscriptionManager,
        subscriptionId: Int,
    ): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                subscriptionManager.getPhoneNumber(subscriptionId)
            } else {
                val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                telephonyManager.createForSubscriptionId(subscriptionId).line1Number
            }
        } catch (_: SecurityException) {
            null
        }
    }
}
