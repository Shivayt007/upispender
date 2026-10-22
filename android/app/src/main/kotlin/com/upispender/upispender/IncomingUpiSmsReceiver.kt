package com.upispender.upispender

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

/**
 * Incoming SMS capture only. No READ_SMS permission and no historical SMS access.
 * We never store the raw message, bank account number or any OTP.
 * A matching debit is placed in a review queue; only the user can add it to spending.
 */
internal object SmsParser {
    private val otp = Regex(
        """(?i)\b(?:otp|one[\s-]?time[\s-]?password|verification[\s-]?code|login[\s-]?code|passcode|do not share)\b"""
    )
    private val nonDebit = Regex(
        """(?i)\b(?:credited|received|refunded|refund|reversal|reversed|cashback|failed|declined|unsuccessful|cancelled|canceled|not completed|not processed|collect request)\b"""
    )
    private val debit = Regex(
        """(?i)\b(?:debited|spent|paid|sent|transferred|withdrawn|withdrawal|purchase|dr\.?|payment of)\b"""
    )
    private val upi = Regex("""(?i)\b(?:upi|vpa|bhim)\b|[a-z0-9._-]{2,}@[a-z0-9._-]{2,}""")
    private val currencyFirst = Regex(
        """(?i)(?:₹|(?<![a-z])INR\b|(?<![a-z])Rs\.?\b)\s*[:\-]?\s*([\d,]+(?:\.\d{1,2})?)"""
    )
    private val currencyLast = Regex(
        """(?i)\b([\d,]+(?:\.\d{1,2})?)\s*(?:INR\b|Rs\.?\b)"""
    )
    private val payee = Regex(
        """(?i)\b(?:paid to|sent to|transfer to|to|at)\s+([a-z0-9][a-z0-9._@-]{1,49})"""
    )
    private val reference = Regex(
        """(?i)\b(?:UPI\s*(?:ref|txn|transaction|id)?[\s:/#-]*|utr[\s:/#-]*|ref(?:erence)?\s*(?:no|number)?[\s:/#-]*)(\d{10,16})\b"""
    )

    fun parse(sender: String, text: String, at: Long): JSONObject? {
        val body = text.replace(Regex("""\s+"""), " ").trim()
        if (body.length !in 20..1200 || otp.containsMatchIn(body) ||
            nonDebit.containsMatchIn(body) || !debit.containsMatchIn(body) ||
            !upi.containsMatchIn(body)) return null

        val raw = (currencyFirst.find(body) ?: currencyLast.find(body))?.groupValues?.get(1)
            ?.replace(",", "") ?: return null
        val parts = raw.split(".")
        val rupees = parts[0].toLongOrNull() ?: return null
        val fraction = if (parts.size > 1) (parts[1].padEnd(2, '0').take(2)).toLongOrNull() ?: return null else 0L
        if (rupees < 0 || rupees > 100000000 || fraction !in 0..99) return null
        val amount = rupees * 100 + fraction
        if (amount < 1 || amount > 10000000000L) return null

        val merchant = payee.find(body)?.groupValues?.get(1) ?: ""
        val candidate = if (merchant.lowercase(Locale.ROOT) in setOf("a/c","acct","account","upi","vpa","rs","inr")) "" else merchant
        val txnReference = reference.find(body)?.groupValues?.get(1) ?: ""
        // Exact repeats are deduplicated; a reference identifier also permits detection
        // across different bank/app SMS senders mentioning the same UPI transaction.
        val signature = if (txnReference.isNotEmpty()) {
            "ref:" + txnReference + ":" + amount
        } else {
            sender.lowercase(Locale.ROOT) + "|" + body.lowercase(Locale.ROOT)
        }
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(signature.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        return JSONObject().apply {
            put("id", digest)
            put("paise", amount)
            put("payee", candidate)
            put("at", at)
            put("sender", sender.take(32))
        }
    }
}

internal object SmsQueue {
    private const val PREFS = "upi_sms_private"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_QUEUE = "pending"
    private const val KEY_SEEN = "seen"

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun enabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    @Synchronized fun setEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, value).commit()
    }

    @Synchronized fun list(context: Context): List<Map<String, Any>> {
        val queue = JSONArray(prefs(context).getString(KEY_QUEUE, "[]") ?: "[]")
        return (0 until queue.length()).mapNotNull { i ->
            val item = queue.optJSONObject(i) ?: return@mapNotNull null
            mapOf(
                "id" to item.optString("id"),
                "paise" to item.optLong("paise"),
                "payee" to item.optString("payee"),
                "at" to item.optLong("at"),
                "sender" to item.optString("sender")
            )
        }.reversed()
    }

    @Synchronized fun add(context: Context, entry: JSONObject): Boolean {
        val store = prefs(context)
        val seen = JSONArray(store.getString(KEY_SEEN, "[]") ?: "[]")
        val id = entry.getString("id")
        for (i in 0 until seen.length()) {
            if (seen.optString(i) == id) return false
        }
        val old = JSONArray(store.getString(KEY_QUEUE, "[]") ?: "[]")
        val queue = JSONArray()
        for (i in maxOf(0, old.length() - 149) until old.length()) {
            queue.put(old.getJSONObject(i))
        }
        queue.put(entry)
        val nextSeen = JSONArray()
        for (i in maxOf(0, seen.length() - 999) until seen.length()) {
            nextSeen.put(seen.getString(i))
        }
        nextSeen.put(id)
        // commit() is synchronous: data survives if Android kills the process.
        return store.edit().putString(KEY_QUEUE, queue.toString())
            .putString(KEY_SEEN, nextSeen.toString()).commit()
    }

    @Synchronized fun remove(context: Context, id: String): Boolean {
        val store = prefs(context)
        val old = JSONArray(store.getString(KEY_QUEUE, "[]") ?: "[]")
        val queue = JSONArray()
        for (i in 0 until old.length()) {
            val entry = old.getJSONObject(i)
            if (entry.optString("id") != id) queue.put(entry)
        }
        return store.edit().putString(KEY_QUEUE, queue.toString()).commit()
    }

    @Synchronized fun clear(context: Context) {
        prefs(context).edit().remove(KEY_QUEUE).remove(KEY_SEEN).commit()
    }
}

class IncomingUpiSmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        if (!SmsQueue.enabled(context)) return
        if (context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) != PackageManager.PERMISSION_GRANTED) return
        try {
            val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (messages.isEmpty()) return
            val sender = messages.first().displayOriginatingAddress ?: return
            val joinedBody = messages.joinToString("") { it.messageBody ?: "" }
            val at = messages.first().timestampMillis.takeIf { it > 0 } ?: System.currentTimeMillis()
            val record = SmsParser.parse(sender, joinedBody, at) ?: return
            if (SmsQueue.add(context, record)) showReviewNotification(context)
        } catch (exception: Exception) {
            Log.w("UPISms", "Unable to process incoming transaction SMS", exception)
        }
    }

    private fun showReviewNotification(context: Context) {
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = "incoming_upi_review"
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                channelId, "UPI payment detection", NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Review newly detected UPI debit messages"
            })
        }
        val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        openIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        val open = PendingIntent.getActivity(
            context, 4401, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("UPI debit detected")
            .setContentText("Open UPI Spend Tracker to review and categorize the payment.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        manager.notify(4401, notification)
    }
}
