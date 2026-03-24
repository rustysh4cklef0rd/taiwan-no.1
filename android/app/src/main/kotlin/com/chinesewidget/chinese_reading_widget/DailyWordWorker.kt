package com.chinesewidget.chinese_reading_widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import androidx.work.*
import org.json.JSONArray
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit

/**
 * Native Kotlin WorkManager worker that runs daily at ~midnight to update
 * the widget's word data without requiring Flutter/Dart to be running.
 *
 * Words are loaded directly from Flutter's bundled asset via context.assets,
 * and today's 6 words are written to the FlutterHomeWidgetPlugin SharedPreferences
 * store so both AppWidgetProviders can read them during onUpdate().
 */
class DailyWordWorker(context: Context, params: WorkerParameters) :
    CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        return try {
            val words = loadWordList()
            val todaysWords = getTodaysWords(words)
            writeWordsToPrefs(todaysWords)
            triggerWidgetUpdate()
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }

    private fun loadWordList(): JSONArray {
        val assetManager = applicationContext.assets
        // Flutter bundles assets under flutter_assets/
        val stream = assetManager.open("flutter_assets/assets/data/words.json")
        val reader = BufferedReader(InputStreamReader(stream))
        val json = reader.readText()
        reader.close()
        return JSONArray(json)
    }

    private fun getTodaysWords(words: JSONArray): List<WordEntry> {
        // Read recognized IDs saved by Flutter and filter them out.
        val prefs = applicationContext.getSharedPreferences(
            "FlutterHomeWidgetPlugin", Context.MODE_PRIVATE
        )
        val recognizedRaw = prefs.getString("recognized_ids", "") ?: ""
        val recognizedIds = if (recognizedRaw.isBlank()) emptySet<Int>()
            else recognizedRaw.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()

        // Build a list of indices for unrecognized words.
        val poolIndices = (0 until words.length()).filter { i ->
            !recognizedIds.contains(words.getJSONObject(i).getInt("id"))
        }
        // Fall back to full list if every word is mastered.
        val effectiveIndices = if (poolIndices.isEmpty())
            (0 until words.length()).toList()
        else poolIndices

        val epochDay = System.currentTimeMillis() / 86_400_000L
        val startIndex = ((epochDay * 6) % effectiveIndices.size).toInt()

        return (0 until 6).map { i ->
            val obj = words.getJSONObject(effectiveIndices[(startIndex + i) % effectiveIndices.size])
            WordEntry(
                id = obj.getInt("id"),
                character = obj.getString("character"),
                pinyin = obj.getString("pinyin"),
                meaning = obj.getString("meaning"),
                phrase = obj.getString("phrase"),
                phrasePinyin = obj.getString("phrase_pinyin"),
                phraseMeaning = obj.getString("phrase_meaning"),
            )
        }
    }

    private fun writeWordsToPrefs(words: List<WordEntry>) {
        val prefs: SharedPreferences = applicationContext
            .getSharedPreferences("FlutterHomeWidgetPlugin", Context.MODE_PRIVATE)
        val editor = prefs.edit()
        words.forEachIndexed { i, w ->
            editor.putString("word_${i}_char", w.character)
            editor.putString("word_${i}_pinyin", w.pinyin)
            editor.putString("word_${i}_meaning", w.meaning)
            editor.putString("word_${i}_phrase", w.phrase)
            editor.putString("word_${i}_phrase_pinyin", w.phrasePinyin)
            editor.putString("word_${i}_phrase_meaning", w.phraseMeaning)
            editor.putString("word_${i}_id", w.id.toString())
        }
        editor.putString("last_updated", System.currentTimeMillis().toString())
        editor.putLong("last_epoch_day", System.currentTimeMillis() / 86_400_000L)
        editor.apply()
    }

    private fun triggerWidgetUpdate() {
        val manager = AppWidgetManager.getInstance(applicationContext)
        listOf(
            ComponentName(applicationContext, WordWidgetProvider4x2::class.java),
            ComponentName(applicationContext, WordWidgetProvider2x2::class.java),
            ComponentName(applicationContext, FlashcardWidgetProvider::class.java),
            ComponentName(applicationContext, FlashcardWidget2x2Provider::class.java),
        ).forEach { component ->
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) {
                manager.notifyAppWidgetViewDataChanged(ids, android.R.id.list)
                // Re-trigger onUpdate by sending the standard broadcast.
                val intent = android.content.Intent(
                    AppWidgetManager.ACTION_APPWIDGET_UPDATE
                ).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                    setComponent(component)
                }
                applicationContext.sendBroadcast(intent)
            }
        }
    }

    companion object {
        private const val WORK_NAME = "daily_word_update"

        /**
         * Schedule a daily periodic task. Safe to call multiple times — uses
         * KEEP policy so an existing enqueued task is not replaced.
         */
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<DailyWordWorker>(1, TimeUnit.DAYS)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                        .build()
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                request,
            )
        }
    }
}

data class WordEntry(
    val id: Int,
    val character: String,
    val pinyin: String,
    val meaning: String,
    val phrase: String,
    val phrasePinyin: String,
    val phraseMeaning: String,
)
