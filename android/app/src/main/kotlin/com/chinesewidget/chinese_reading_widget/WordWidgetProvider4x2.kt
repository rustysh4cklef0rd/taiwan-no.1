package com.chinesewidget.chinese_reading_widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * AppWidgetProvider for the 4×2 widget (6 words).
 *
 * Word data is stored in SharedPreferences by the Flutter side via the
 * `home_widget` package (prefs name: "FlutterHomeWidgetPlugin").
 *
 * Each word slot has keys:  word_N_char, word_N_pinyin (N = 0..5).
 *
 * Tapping a cell sends a PendingIntent that launches MainActivity with
 * the extra "word_index" (int), which Flutter reads on startup.
 */
class WordWidgetProvider4x2 : AppWidgetProvider() {

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
        private const val EXTRA_WORD_INDEX = "word_index"

        /** Cell view IDs in order (slot 0..5). */
        private val CELL_IDS = intArrayOf(
            R.id.cell_0, R.id.cell_1, R.id.cell_2,
            R.id.cell_3, R.id.cell_4, R.id.cell_5
        )
        private val CHAR_IDS = intArrayOf(
            R.id.char_0, R.id.char_1, R.id.char_2,
            R.id.char_3, R.id.char_4, R.id.char_5
        )
        private val PINYIN_IDS = intArrayOf(
            R.id.pinyin_0, R.id.pinyin_1, R.id.pinyin_2,
            R.id.pinyin_3, R.id.pinyin_4, R.id.pinyin_5
        )
        private val MEANING_IDS = intArrayOf(
            R.id.meaning_0, R.id.meaning_1, R.id.meaning_2,
            R.id.meaning_3, R.id.meaning_4, R.id.meaning_5
        )

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int
        ) {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // Choose layout based on dark-mode pref stored by Flutter.
            val isDark = prefs.getBoolean("dark_mode", false)
            val layoutId = if (isDark) R.layout.widget_layout_4x2_night
                           else R.layout.widget_layout_4x2

            val views = RemoteViews(context.packageName, layoutId)

            // Stale check: if words are from a previous day, queue an immediate refresh.
            val storedDay = prefs.getLong("last_epoch_day", -1L)
            val todayDay = System.currentTimeMillis() / 86_400_000L
            if (storedDay < todayDay) {
                WorkManager.getInstance(context)
                    .enqueue(OneTimeWorkRequestBuilder<DailyWordWorker>().build())
            }

            val hidePinyin = prefs.getBoolean("hide_pinyin", false)

            for (slot in 0..5) {
                val character = prefs.getString("word_${slot}_char", "字") ?: "字"
                val pinyin    = prefs.getString("word_${slot}_pinyin", "") ?: ""

                views.setTextViewText(CHAR_IDS[slot], character)
                views.setTextViewText(PINYIN_IDS[slot], pinyin)
                if (hidePinyin) views.setTextViewText(PINYIN_IDS[slot], "")
                val meaning = prefs.getString("word_${slot}_meaning", "") ?: ""
                views.setTextViewText(MEANING_IDS[slot], meaning)

                // Save the word index so Flutter knows which detail to open.
                val tapIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra(EXTRA_WORD_INDEX, slot)
                    // Write to home_widget prefs so Flutter can read it on cold start.
                    // We also set launch_word_index directly in the intent extra.
                }

                val pendingIntent = PendingIntent.getActivity(
                    context,
                    // Unique request code per slot so they aren't collapsed.
                    widgetId * 10 + slot,
                    tapIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                views.setOnClickPendingIntent(CELL_IDS[slot], pendingIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
