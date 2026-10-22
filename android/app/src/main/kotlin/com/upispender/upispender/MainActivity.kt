package com.upispender.upispender

import android.Manifest
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.upispender.upispender/sms"
    private val requestCodeSms = 7339
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "permission" to hasPermission(),
                            "enabled" to SmsQueue.enabled(this),
                            "pending" to SmsQueue.list(this).size
                        )
                    )
                    "requestPermission" -> {
                        if (hasPermission()) {
                            result.success(true)
                        } else if (pendingPermissionResult != null) {
                            result.error("BUSY", "Permission request already in progress", null)
                        } else {
                            pendingPermissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.RECEIVE_SMS), requestCodeSms)
                        }
                    }
                    "enable" -> {
                        val value = call.argument<Boolean>("value") ?: false
                        val canEnable = !value || hasPermission()
                        if (canEnable) SmsQueue.setEnabled(this, value)
                        result.success(canEnable)
                    }
                    "pending" -> result.success(SmsQueue.list(this))
                    "dismiss" -> {
                        val id = call.argument<String>("id") ?: ""
                        result.success(SmsQueue.remove(this, id))
                    }
                    "clear" -> {
                        SmsQueue.clear(this)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasPermission(): Boolean =
        checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == requestCodeSms) {
            pendingPermissionResult?.success(hasPermission())
            pendingPermissionResult = null
        }
    }

    override fun onDestroy() {
        pendingPermissionResult?.error("CANCELLED", "Activity destroyed", null)
        pendingPermissionResult = null
        super.onDestroy()
    }
}
