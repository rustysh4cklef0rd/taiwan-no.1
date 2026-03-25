package com.chinesewidget.chinese_reading_widget

import android.content.SharedPreferences
import android.os.Bundle
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // If launched from a widget tap, write the word_id into the
        // home_widget SharedPreferences store so the Flutter side can read it
        // via HomeWidget.getWidgetData<int>('launch_word_id').
        val wordId = intent?.getIntExtra("word_id", -1) ?: -1
        if (wordId >= 0) {
            val prefs: SharedPreferences =
                getSharedPreferences("FlutterHomeWidgetPlugin", MODE_PRIVATE)
            prefs.edit().putInt("launch_word_id", wordId).apply()
        }

        super.onCreate(savedInstanceState)

        // Schedule native WorkManager daily update (KEEP policy — safe to call every launch).
        DailyWordWorker.schedule(this)

        // If words are from a previous day, refresh immediately.
        val hwPrefs = getSharedPreferences("FlutterHomeWidgetPlugin", MODE_PRIVATE)
        val storedDay = try {
            hwPrefs.getString("last_epoch_day", "-1")?.toLongOrNull() ?: -1L
        } catch (_: ClassCastException) {
            // Legacy: was stored as Long before migration to String
            try { hwPrefs.getLong("last_epoch_day", -1L) } catch (_: Exception) { -1L }
        }
        val todayDay = System.currentTimeMillis() / 86_400_000L
        if (storedDay < todayDay) {
            WorkManager.getInstance(this).enqueueUniqueWork(
                "daily_word_immediate",
                ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<DailyWordWorker>().build()
            )
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        val wordId = intent.getIntExtra("word_id", -1)
        if (wordId >= 0) {
            val prefs: SharedPreferences =
                getSharedPreferences("FlutterHomeWidgetPlugin", MODE_PRIVATE)
            prefs.edit().putInt("launch_word_id", wordId).apply()

            // Notify the running Flutter engine via a method channel so it
            // can navigate to the detail screen without a restart.
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                val channel = io.flutter.plugin.common.MethodChannel(
                    messenger, "com.chinesewidget/widget_tap"
                )
                channel.invokeMethod("onWidgetTap", mapOf("word_id" to wordId))
            }
        }
    }
}
