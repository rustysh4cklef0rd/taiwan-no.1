package com.chinesewidget.chinese_reading_widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fires on every phone unlock (ACTION_USER_PRESENT).
 *
 * Each unlock cycles the flashcard widget to the next of today's 6 words.
 * At the start of a new calendar day the index resets to 0.
 */
class UnlockReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_USER_PRESENT) return

        val prefs = context.getSharedPreferences(
            "FlutterHomeWidgetPlugin", Context.MODE_PRIVATE
        )

        val epochDay = System.currentTimeMillis() / 86_400_000L
        val lastDay  = prefs.getLong("flashcard_epoch_day", -1L)

        val nextSlot = if (lastDay != epochDay) {
            // New day — reset to first word
            0
        } else {
            // Same day — advance to next word, wrap after 6
            (prefs.getInt("flashcard_slot", 0) + 1) % 6
        }

        prefs.edit()
            .putInt("flashcard_slot", nextSlot)
            .putLong("flashcard_epoch_day", epochDay)
            .apply()

        FlashcardWidgetProvider.updateAll(context)
    }
}
