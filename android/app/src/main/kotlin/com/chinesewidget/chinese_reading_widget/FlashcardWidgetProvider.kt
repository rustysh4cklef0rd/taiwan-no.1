package com.chinesewidget.chinese_reading_widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.widget.RemoteViews

/**
 * Flashcard widget — shows ONE word at a time in full detail.
 * Cycles to the next word each time the user unlocks their phone (via UnlockReceiver).
 *
 * Cycling state stored in FlutterHomeWidgetPlugin prefs:
 *   flashcard_slot       — current word index 0..5
 *   flashcard_epoch_day  — epoch day when slot was last reset (resets at midnight)
 */
class FlashcardWidgetProvider : AppWidgetProvider() {

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        val prefs = context.getSharedPreferences("FlutterHomeWidgetPlugin", Context.MODE_PRIVATE)
        if (prefs.getString("word_0_char", null) == null) {
            androidx.work.WorkManager.getInstance(context)
                .enqueue(androidx.work.OneTimeWorkRequestBuilder<DailyWordWorker>().build())
        }
        DailyWordWorker.schedule(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "FlutterHomeWidgetPlugin"

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int
        ) {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // Cycle through the 6 daily words every 20 minutes.
        // 6 words × 20 min = all words seen within 2 hours; then repeats.
        val twentyMinBlock = (System.currentTimeMillis() / 1_200_000L) % 6
        val slot = twentyMinBlock.toInt()

            val character    = prefs.getString("word_${slot}_char", "…") ?: "…"
            val pinyin       = prefs.getString("word_${slot}_pinyin", "") ?: ""
            val meaning      = prefs.getString("word_${slot}_meaning", "") ?: ""
            val phrase       = prefs.getString("word_${slot}_phrase", "") ?: ""
            val phrasePinyin = prefs.getString("word_${slot}_phrase_pinyin", "") ?: ""
            val phraseMeaning = prefs.getString("word_${slot}_phrase_meaning", "") ?: ""

            val isDark = prefs.getBoolean("dark_mode", false)
            val layoutId = if (isDark) R.layout.widget_layout_flashcard_night
                           else R.layout.widget_layout_flashcard

            val views = RemoteViews(context.packageName, layoutId)

            views.setTextViewText(R.id.flashcard_character, character)
            views.setTextViewText(R.id.flashcard_pinyin, pinyin)
            views.setTextViewText(R.id.flashcard_meaning, meaning)
            views.setTextViewText(
                R.id.flashcard_phrase,
                if (phrase.isNotEmpty() && phrasePinyin.isNotEmpty())
                    "$phrase  •  $phrasePinyin"
                else phrase
            )
            views.setTextViewText(R.id.flashcard_phrase_meaning, phraseMeaning)

            // Tap → open detail screen for this word
            val tapIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("word_index", slot)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                widgetId + 200, // offset to avoid collision with other providers
                tapIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.flashcard_character, pendingIntent)

            // 🔊 button → speak via WordTtsService (no app launch needed)
            val speakIntent = Intent(context, WordTtsService::class.java).apply {
                putExtra(WordTtsService.EXTRA_TEXT, character)
            }
            val speakPending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(
                    context, widgetId + 500, speakIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                PendingIntent.getService(
                    context, widgetId + 500, speakIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }
            views.setOnClickPendingIntent(R.id.flashcard_speak_btn, speakPending)

            appWidgetManager.updateAppWidget(widgetId, views)
        }

        /** Update all active flashcard widgets. */
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = android.content.ComponentName(
                context, FlashcardWidgetProvider::class.java
            )
            val ids = manager.getAppWidgetIds(component)
            for (id in ids) updateWidget(context, manager, id)
        }
    }
}
