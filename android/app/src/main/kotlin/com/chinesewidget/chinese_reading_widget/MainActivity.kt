package com.chinesewidget.chinese_reading_widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Registered dynamically because ACTION_USER_PRESENT cannot be declared
    // in the static manifest — Android silently ignores it there.
    private var unlockReceiver: UnlockReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.chinesewidget/widget_ops"
        ).setMethodCallHandler { call, result ->
            if (call.method == "forceUpdate") {
                forceUpdateAllWidgets()
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * Directly updates all word-widget instances by calling their companion
     * [updateWidget] without going through an async broadcast, so the change
     * is visible the moment Flutter finishes writing the SharedPreferences data.
     * Flashcard widgets receive a broadcast (their render logic lives in onUpdate).
     */
    private fun forceUpdateAllWidgets() {
        val manager = AppWidgetManager.getInstance(this)

        // Word grid widgets — direct synchronous update.
        for (id in manager.getAppWidgetIds(ComponentName(this, WordWidgetProvider4x2::class.java))) {
            WordWidgetProvider4x2.updateWidget(this, manager, id)
        }
        for (id in manager.getAppWidgetIds(ComponentName(this, WordWidgetProvider2x2::class.java))) {
            WordWidgetProvider2x2.updateWidget(this, manager, id)
        }

        // Flashcard widgets — broadcast (their update logic is inside onUpdate).
        listOf(FlashcardWidgetProvider::class.java, FlashcardWidget2x2Provider::class.java).forEach { cls ->
            val comp = ComponentName(this, cls)
            val ids = manager.getAppWidgetIds(comp)
            if (ids.isNotEmpty()) {
                sendBroadcast(Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
                    component = comp
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                })
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // If launched from a widget tap, write the word_id into the
        // home_widget SharedPreferences store so the Flutter side can read it
        // via HomeWidget.getWidgetData<int>('launch_word_id').
        val wordId = intent?.getIntExtra("word_id", -1) ?: -1
        if (wordId >= 0) {
            val prefs: SharedPreferences =
                getSharedPreferences("HomeWidgetPreferences", MODE_PRIVATE)
            prefs.edit().putInt("launch_word_id", wordId).apply()
        }

        super.onCreate(savedInstanceState)

        // Schedule the daily midnight word refresh.
        DailyWordWorker.schedule(this)

        // Register UnlockReceiver so the flashcard widget cycles on every phone
        // unlock. Must be dynamic — ACTION_USER_PRESENT is ignored in the manifest.
        unlockReceiver = UnlockReceiver()
        @Suppress("UnspecifiedRegisterReceiverFlag")
        registerReceiver(unlockReceiver, IntentFilter(Intent.ACTION_USER_PRESENT))
    }

    override fun onDestroy() {
        super.onDestroy()
        unlockReceiver?.let { unregisterReceiver(it) }
        unlockReceiver = null
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        val wordId = intent.getIntExtra("word_id", -1)
        if (wordId >= 0) {
            val prefs: SharedPreferences =
                getSharedPreferences("HomeWidgetPreferences", MODE_PRIVATE)
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
