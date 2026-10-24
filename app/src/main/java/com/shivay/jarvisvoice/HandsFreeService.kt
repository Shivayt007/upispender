package com.shivay.jarvisvoice

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.ContactsContract
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.telecom.TelecomManager
import java.util.Locale

/**
 * User-started experimental microphone foreground service. Android SpeechRecognizer
 * is not a perpetual wake-word API and some devices will kill screen-off recognition.
 */
class HandsFreeService : Service(), RecognitionListener {
    companion object {
        const val ACTION_START = "com.shivay.jarvisvoice.START"
        const val ACTION_STOP = "com.shivay.jarvisvoice.STOP"
        const val ACTION_SPEAK = "com.shivay.jarvisvoice.SPEAK"
        @Volatile var running = false
            private set
    }

    private enum class State { WAKE, COMMAND, CONFIRM }
    private data class Contact(val name: String, val phone: String)

    private val main = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var listening = false
    private var speaking = false
    private var state = State.WAKE
    private var pendingContact: Contact? = null
    private var consecutiveErrors = 0
    private val restart = Runnable { beginListening() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> { stopSelf(); return START_NOT_STICKY }
            ACTION_SPEAK -> {
                if (running) {
                    val phrase = intent.getStringExtra("spoken_text")
                    if (!phrase.isNullOrBlank()) talk(phrase)
                }
                return START_NOT_STICKY
            }
        }
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            stopSelf(); return START_NOT_STICKY
        }
        if (!running) {
            val channel = NotificationChannel("jarvis_listening", "Jarvis voice listener",
                NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
            val stopIntent = PendingIntent.getService(this, 2,
                Intent(this, HandsFreeService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification = Notification.Builder(this, "jarvis_listening")
                .setContentTitle("Jarvis is listening")
                .setContentText("Say 'Hey Jarvis, wake up'. Tap Stop to end microphone access.")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .addAction(Notification.Action.Builder(null, "Stop", stopIntent).build())
                .build()
            startForeground(71, notification)
            running = true
            state = State.WAKE
            if (!SpeechRecognizer.isRecognitionAvailable(this)) {
                talk("Speech recognition is not installed on this phone.") { stopSelf() }
            } else {
                recognizer = SpeechRecognizer.createSpeechRecognizer(this)
                recognizer?.setRecognitionListener(this)
                talk("Jarvis is ready. Say Hey Jarvis, wake up.")
            }
        }
        return START_NOT_STICKY
    }

    private fun beginListening() {
        if (!running || speaking || listening || recognizer == null) return
        try {
            val request = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US.toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
            }
            listening = true
            recognizer?.startListening(request)
        } catch (_: Exception) {
            listening = false
            retryLater(3500)
        }
    }

    private fun retryLater(delay: Long = 850) {
        main.removeCallbacks(restart)
        if (running && !speaking) main.postDelayed(restart, delay)
    }

    private fun talk(text: String, then: (() -> Unit)? = null) {
        speaking = true
        main.removeCallbacks(restart)
        if (listening) {
            listening = false
            recognizer?.cancel()
        }
        VoiceSpeaker.say(this, text) {
            speaking = false
            if (then != null) then() else retryLater(400)
        }
    }

    override fun onReadyForSpeech(params: Bundle?) = Unit
    override fun onBeginningOfSpeech() = Unit
    override fun onRmsChanged(rmsdB: Float) = Unit
    override fun onBufferReceived(buffer: ByteArray?) = Unit
    override fun onEndOfSpeech() = Unit
    override fun onPartialResults(partialResults: Bundle?) = Unit
    override fun onEvent(eventType: Int, params: Bundle?) = Unit

    override fun onError(error: Int) {
        listening = false
        if (speaking || !running) return
        consecutiveErrors++
        if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
            talk("Microphone permission is missing.") { stopSelf() }
            return
        }
        // Do not spin aggressively if the recognition service is unavailable.
        retryLater(if (consecutiveErrors > 4) 5_000 else 1_200)
    }

    override fun onResults(results: Bundle?) {
        listening = false
        consecutiveErrors = 0
        if (speaking || !running) return
        val heard = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            ?.firstOrNull()?.lowercase(Locale.US)?.trim().orEmpty()
        if (heard.isBlank()) { retryLater(); return }
        when (state) {
            State.WAKE -> {
                val wake = when {
                    "hey jarvis" in heard -> heard.substringAfter("hey jarvis")
                    "jarvis wake up" in heard -> heard.substringAfter("jarvis wake up")
                    else -> { retryLater(); return }
                }
                state = State.COMMAND
                val command = wake.trim().removePrefix("wake up").trim(' ', ',', '.')
                if (command.isBlank()) talk("Yes? How can I help you?")
                else handleCommand(command)
            }
            State.COMMAND -> handleCommand(heard)
            State.CONFIRM -> {
                when {
                    Regex("\\b(yes|confirm|go ahead)\\b").containsMatchIn(heard) -> {
                        val person = pendingContact
                        pendingContact = null
                        state = State.WAKE
                        if (person == null) talk("No call is pending.")
                        else talk("Calling ${person.name}.") { placeCall(person.phone) }
                    }
                    Regex("\\b(no|cancel|stop)\\b").containsMatchIn(heard) -> {
                        pendingContact = null; state = State.WAKE; talk("Call cancelled.")
                    }
                    else -> talk("Please say yes or no.")
                }
            }
        }
    }

    private fun handleCommand(command: String) {
        if (command == "stop" || command == "sleep") {
            state = State.WAKE; talk("Going back to standby."); return
        }
        val wanted = when {
            command.startsWith("call that person") || command.startsWith("call the sender") ->
                getSharedPreferences("jarvis", MODE_PRIVATE).getString("last_sender", null)
            command.startsWith("call ") -> command.removePrefix("call ").trim()
            else -> null
        }
        if (wanted.isNullOrBlank()) {
            state = State.WAKE
            talk("I can call a saved contact. Say Hey Jarvis, call Rahul.")
            return
        }
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            state = State.WAKE; talk("Grant Contacts permission first."); return
        }
        if (checkSelfPermission(Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
            state = State.WAKE; talk("Grant Phone permission first."); return
        }
        val person = findUniqueContact(wanted)
        if (person == null) {
            state = State.WAKE
            talk("I couldn't find exactly one saved contact for $wanted.")
            return
        }
        pendingContact = person
        state = State.CONFIRM
        talk("Call ${person.name} on the normal phone network? Say yes or no.")
    }

    private fun findUniqueContact(search: String): Contact? {
        val contacts = mutableListOf<Contact>()
        val columns = arrayOf(
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY,
            ContactsContract.CommonDataKinds.Phone.NUMBER
        )
        val uri = ContactsContract.CommonDataKinds.Phone.CONTENT_URI
        try {
            contentResolver.query(uri, columns,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME_PRIMARY} LIKE ?",
                arrayOf("%$search%"), null)?.use { cursor ->
                while (cursor.moveToNext() && contacts.size < 60) {
                    val name = cursor.getString(0) ?: continue
                    val number = cursor.getString(1) ?: continue
                    if (number.isNotBlank()) contacts.add(Contact(name, number))
                }
            }
        } catch (_: SecurityException) { return null }
        val exact = contacts.filter { it.name.equals(search, ignoreCase = true) }
            .distinctBy { it.phone.filter(Char::isDigit) }
        if (exact.size == 1) return exact.first()
        if (exact.isNotEmpty()) return null
        return contacts.distinctBy { it.phone.filter(Char::isDigit) }.singleOrNull()
    }

    private fun placeCall(number: String) {
        try {
            if (checkSelfPermission(Manifest.permission.CALL_PHONE) != PackageManager.PERMISSION_GRANTED) {
                talk("Phone permission is missing."); return
            }
            val telecom = getSystemService(TelecomManager::class.java)
            telecom.placeCall(Uri.fromParts("tel", number, null), Bundle())
            stopSelf() // Avoid microphone listening during a call.
        } catch (_: Exception) {
            talk("I couldn't start the SIM call. Please check your device calling settings.")
        }
    }

    override fun onDestroy() {
        running = false
        main.removeCallbacks(restart)
        recognizer?.cancel()
        recognizer?.destroy()
        recognizer = null
        listening = false
        super.onDestroy()
    }
}
