package com.chinesewidget.chinese_reading_widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * AppWidgetProvider for the 2×2 widget (6 words in a 3×2 grid).
 */
class WordWidgetProvider2x2 : AppWidgetProvider() {

    /** Bootstrap: fire DailyWordWorker once if the app has never been opened. */
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        if (prefs.getString("word_0_char", null) == null) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                "daily_word_immediate",
                ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<DailyWordWorker>().build()
            )
        }
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

        private const val PREFS_NAME = "HomeWidgetPreferences"
        private const val EXTRA_WORD_INDEX = "word_index"

        private val CELL_IDS   = intArrayOf(R.id.cell_0,   R.id.cell_1,   R.id.cell_2,   R.id.cell_3,   R.id.cell_4,   R.id.cell_5)
        private val CHAR_IDS   = intArrayOf(R.id.char_0,   R.id.char_1,   R.id.char_2,   R.id.char_3,   R.id.char_4,   R.id.char_5)
        private val PINYIN_IDS = intArrayOf(R.id.pinyin_0, R.id.pinyin_1, R.id.pinyin_2, R.id.pinyin_3, R.id.pinyin_4, R.id.pinyin_5)
        private val MEANING_IDS = intArrayOf(R.id.meaning_0, R.id.meaning_1, R.id.meaning_2, R.id.meaning_3, R.id.meaning_4, R.id.meaning_5)

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int
        ) {
            val prefs: SharedPreferences =
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val isDark = prefs.getBoolean("dark_mode", false)
            val layoutId = if (isDark) R.layout.widget_layout_2x2_night
                           else R.layout.widget_layout_2x2

            val views = RemoteViews(context.packageName, layoutId)

            val hidePinyin = prefs.getBoolean("hide_pinyin", false)

            for (slot in 0..5) {
                val character = prefs.getString("word_${slot}_char", "字") ?: "字"
                val pinyin    = prefs.getString("word_${slot}_pinyin", "") ?: ""

                views.setTextViewText(CHAR_IDS[slot], character)
                views.setTextViewText(PINYIN_IDS[slot], pinyin)
                if (hidePinyin) views.setTextViewText(PINYIN_IDS[slot], "")
                val meaning = prefs.getString("word_${slot}_meaning", "") ?: ""
                views.setTextViewText(MEANING_IDS[slot], meaning)

                val wordId = prefs.getString("word_${slot}_id", "-1")
                    ?.toIntOrNull() ?: slot
                val tapIntent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_MAIN
                    addCategory(Intent.CATEGORY_LAUNCHER)
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("word_id", wordId)
                }

                val pendingIntent = PendingIntent.getActivity(
                    context,
                    // Offset by 100 to avoid collision with 4×2 widget request codes.
                    100 + widgetId * 10 + slot,
                    tapIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )

                views.setOnClickPendingIntent(CELL_IDS[slot], pendingIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
