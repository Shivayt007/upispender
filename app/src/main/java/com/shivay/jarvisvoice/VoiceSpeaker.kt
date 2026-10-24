package com.shivay.jarvisvoice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/** Single application-scoped TTS engine. Delivers done callback on Android main thread. */
object VoiceSpeaker {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: TextToSpeech? = null
    private var ready = false
    private var waiting: Pair<String, (() -> Unit)?>? = null
    private var finished: (() -> Unit)? = null
    private var counter = 0L

    fun say(context: Context, text: String, onDone: (() -> Unit)? = null) {
        handler.post {
            if (engine == null) {
                waiting = text to onDone
                engine = TextToSpeech(context.applicationContext) { status ->
                    handler.post {
                        ready = status == TextToSpeech.SUCCESS
                        if (ready) {
                            engine?.language = Locale.US
                            engine?.setSpeechRate(0.96f)
                            engine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                                override fun onStart(utteranceId: String) = Unit
                                override fun onDone(utteranceId: String) { handler.post { finished?.invoke(); finished = null } }
                                @Deprecated("Deprecated in Android SDK")
                                override fun onError(utteranceId: String) { handler.post { finished?.invoke(); finished = null } }
                            })
                        }
                        val next = waiting
                        waiting = null
                        if (ready && next != null) speak(next.first, next.second)
                        else next?.second?.invoke()
                    }
                }
            } else if (ready) {
                speak(text, onDone)
            } else {
                waiting = text to onDone
            }
        }
    }

    private fun speak(text: String, onDone: (() -> Unit)?) {
        finished = onDone
        counter++
        val status = engine?.speak(text.take(550), TextToSpeech.QUEUE_FLUSH, null, "jarvis-$counter")
        if (status == TextToSpeech.ERROR) { finished = null; onDone?.invoke() }
    }
}
