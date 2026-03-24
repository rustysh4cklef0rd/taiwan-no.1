package com.chinesewidget.chinese_reading_widget

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * Short-lived foreground service that speaks a Chinese character via the
 * device's on-board TTS engine. Launched by a widget PendingIntent — no
 * Flutter engine or app activity required.
 *
 * Lifecycle: start → TTS init → speak → onDone → stopSelf().
 * Total runtime: typically 1–3 seconds.
 */
class WordTtsService : Service(), TextToSpeech.OnInitListener {

    private var tts: TextToSpeech? = null
    private var textToSpeak: String? = null

    companion object {
        const val EXTRA_TEXT = "text"
        private const val CHANNEL_ID = "word_tts"
        private const val NOTIFICATION_ID = 9001
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        textToSpeak = intent?.getStringExtra(EXTRA_TEXT)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, "Pronunciation",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    setShowBadge(false)
                    enableLights(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                mgr.createNotificationChannel(ch)
            }
            val notification = Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(textToSpeak ?: "")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .build()
            startForeground(NOTIFICATION_ID, notification)
        }

        tts = TextToSpeech(this, this)
        return START_NOT_STICKY
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            stopSelf(); return
        }

        // Prefer zh-TW; fall back to zh-HK, then generic zh.
        val preferred = listOf(
            Locale.forLanguageTag("zh-TW"),
            Locale.forLanguageTag("zh-HK"),
            Locale.CHINESE,
        )
        var set = false
        for (locale in preferred) {
            val result = tts?.setLanguage(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
            if (result != TextToSpeech.LANG_MISSING_DATA &&
                result != TextToSpeech.LANG_NOT_SUPPORTED) {
                set = true; break
            }
        }
        if (!set) { stopSelf(); return }

        tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) {}
            override fun onDone(id: String?)  { stopSelf() }
            @Deprecated("Deprecated in API 21")
            override fun onError(id: String?) { stopSelf() }
        })

        val text = textToSpeak
        if (text.isNullOrBlank()) { stopSelf(); return }
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "utterance")
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
