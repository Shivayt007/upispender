package com.shivay.jarvisvoice

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class NotificationReaderService : NotificationListenerService() {
    private val recentlySpoken = mutableMapOf<String, Long>()

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null || sbn.packageName == packageName) return
        val prefs = getSharedPreferences("jarvis", MODE_PRIVATE)
        val appName = when (sbn.packageName) {
            "com.whatsapp", "com.whatsapp.w4b" -> "WhatsApp"
            "org.telegram.messenger", "org.telegram.messenger.web" -> "Telegram"
            "com.instagram.android" -> "Instagram"
            "com.google.android.apps.messaging", "com.android.mms" -> "SMS"
            else -> return
        }
        val setting = if (appName == "SMS") "sms" else when (appName) {
            "WhatsApp" -> "com.whatsapp"
            "Telegram" -> "org.telegram.messenger"
            else -> "com.instagram.android"
        }
        if (!prefs.getBoolean(setting, appName != "Instagram")) return
        val extras = sbn.notification.extras
        val sender = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val body = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()?.trim().orEmpty()
        if (sender.isBlank() || body.isBlank() || sender.length > 70) return
        if (body.contains("verification code", ignoreCase = true) ||
            body.contains("one-time password", ignoreCase = true) ||
            Regex("\\b(otp|password|security code)\\b", RegexOption.IGNORE_CASE).containsMatchIn(body)) return
        val key = "${sbn.packageName}|$sender|$body"
        val now = System.currentTimeMillis()
        if (now - (recentlySpoken[key] ?: 0) < 45_000) return
        recentlySpoken[key] = now
        if (recentlySpoken.size > 100) recentlySpoken.entries.removeAll { now - it.value > 90_000 }

        // Only the most recent sender is persisted for "call that person".
        prefs.edit().putString("last_sender", sender).apply()
        val text = "New $appName message from $sender. $body"
        if (HandsFreeService.running) {
            startService(Intent(this, HandsFreeService::class.java)
                .setAction(HandsFreeService.ACTION_SPEAK)
                .putExtra("spoken_text", text))
        } else {
            VoiceSpeaker.say(this, text)
        }
    }
}
