package com.chinesewidget.chinese_reading_widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fires on every phone unlock (ACTION_USER_PRESENT).
 *
 * Registered dynamically in MainActivity — ACTION_USER_PRESENT cannot be
 * declared in the static manifest. Refreshes both flashcard widget sizes so
 * the current 20-minute time-bucket word is shown immediately on unlock.
 */
class UnlockReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_USER_PRESENT) return
        FlashcardWidgetProvider.updateAll(context)
        FlashcardWidget2x2Provider.updateAll(context)
    }
}
