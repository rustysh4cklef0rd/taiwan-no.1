package com.chinesewidget.chinese_reading_widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Build
import android.widget.RemoteViews
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/** 2×2 compact flashcard — character + pinyin + meaning + speaker button. */
class FlashcardWidget2x2Provider : AppWidgetProvider() {

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        // Bootstrap: if word data doesn't exist yet (app never opened), run
        // DailyWordWorker immediately so the widget shows real words right away.
        val prefs = context.getSharedPreferences("FlutterHomeWidgetPlugin", Context.MODE_PRIVATE)
        if (prefs.getString("word_0_char", null) == null) {
            WorkManager.getInstance(context).enqueueUniqueWork(
                "daily_word_immediate",
                ExistingWorkPolicy.KEEP,
                OneTimeWorkRequestBuilder<DailyWordWorker>().build()
            )
        }
        DailyWordWorker.schedule(context)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) updateWidget(context, appWidgetManager, id)
    }

    companion object {
        private const val PREFS = "FlutterHomeWidgetPlugin"

        fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

            val slot    = ((System.currentTimeMillis() / 1_200_000L) % 6).toInt()
            val character = prefs.getString("word_${slot}_char",    "…") ?: "…"
            val pinyin    = prefs.getString("word_${slot}_pinyin",  "")  ?: ""
            val meaning   = prefs.getString("word_${slot}_meaning", "")  ?: ""

            val isDark = prefs.getBoolean("dark_mode", false)
            val layoutId = if (isDark) R.layout.widget_layout_flashcard_2x2_night
                           else R.layout.widget_layout_flashcard_2x2

            val views = RemoteViews(context.packageName, layoutId)
            views.setTextViewText(R.id.flashcard_character, character)
            views.setTextViewText(R.id.flashcard_pinyin, pinyin)
            views.setTextViewText(R.id.flashcard_meaning, meaning)

            // Tap character → open detail screen in app
            val tapIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("word_index", slot)
            }
            views.setOnClickPendingIntent(
                R.id.flashcard_character,
                PendingIntent.getActivity(
                    context, widgetId + 200, tapIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )

            // Tap 🔊 → speak via WordTtsService (no app launch)
            val speakIntent = Intent(context, WordTtsService::class.java).apply {
                putExtra(WordTtsService.EXTRA_TEXT, character)
            }
            val speakPending = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PendingIntent.getForegroundService(
                    context, widgetId + 400, speakIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                PendingIntent.getService(
                    context, widgetId + 400, speakIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }
            views.setOnClickPendingIntent(R.id.flashcard_speak_btn, speakPending)

            manager.updateAppWidget(widgetId, views)
        }

        fun updateAll(context: Context) {
            val mgr = AppWidgetManager.getInstance(context)
            val ids = mgr.getAppWidgetIds(
                android.content.ComponentName(context, FlashcardWidget2x2Provider::class.java)
            )
            for (id in ids) updateWidget(context, mgr, id)
        }
    }
}
