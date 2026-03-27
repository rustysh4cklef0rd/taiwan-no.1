package com.chinesewidget.chinese_reading_widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.SharedPreferences
import android.util.Log
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
        Log.d("CWDBG", "DailyWordWorker.doWork: STARTED")
        return try {
            val words = loadWordList()
            val todaysWords = getTodaysWords(words)
            Log.d("CWDBG", "DailyWordWorker: writing words=${todaysWords.map { "${it.character}(${it.id})" }}")
            writeWordsToPrefs(todaysWords)
            triggerWidgetUpdate()
            Log.d("CWDBG", "DailyWordWorker.doWork: DONE")
            Result.success()
        } catch (e: Exception) {
            Log.e("CWDBG", "DailyWordWorker.doWork: FAILED $e")
            Result.retry()
        }
    }

    private fun loadWordList(): JSONArray {
        val assetManager = applicationContext.assets
        // Flutter bundles assets under flutter_assets/. Load all 4 files and merge.
        val filePaths = listOf(
            "flutter_assets/assets/data/words_set1.json",
            "flutter_assets/assets/data/words_set2.json",
            "flutter_assets/assets/data/words_set3.json",
            "flutter_assets/assets/data/words_set4.json",
        )
        val combined = JSONArray()
        for (path in filePaths) {
            try {
                val stream = assetManager.open(path)
                val reader = BufferedReader(InputStreamReader(stream))
                val json = reader.readText()
                reader.close()
                val part = JSONArray(json)
                for (i in 0 until part.length()) {
                    combined.put(part.getJSONObject(i))
                }
            } catch (e: Exception) {
                Log.w("CWDBG", "DailyWordWorker: skipping missing asset $path: $e")
            }
        }
        if (combined.length() == 0) throw IllegalStateException("No word files could be loaded")
        return combined
    }

    private fun getTodaysWords(words: JSONArray): List<WordEntry> {
        // Read recognized IDs saved by Flutter and filter them out.
        val widgetPrefs = applicationContext.getSharedPreferences(
            "HomeWidgetPreferences", Context.MODE_PRIVATE
        )
        val recognizedRaw = widgetPrefs.getString("recognized_ids", "") ?: ""
        val recognizedIds = if (recognizedRaw.isBlank()) emptySet<Int>()
            else recognizedRaw.split(",").mapNotNull { it.trim().toIntOrNull() }.toSet()

        // Read active set from Flutter's SharedPreferences (keys prefixed with "flutter.").
        val flutterPrefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        val activeSet = flutterPrefs.getInt("flutter.active_set", 1)

        // Set max IDs: index matches set number (0 unused).
        val setMaxIds = listOf(0, 312, 625, 937, 1250)
        val maxId = setMaxIds.getOrElse(activeSet) { 1250 }

        // Build a list of indices for unrecognized words within the active set.
        val poolIndices = (0 until words.length()).filter { i ->
            val word = words.getJSONObject(i)
            val id = word.getInt("id")
            !recognizedIds.contains(id) && id <= maxId
        }
        // Fall back to active-set words only (ignore recognized filter) if everything mastered.
        val setIndices = (0 until words.length()).filter { i ->
            words.getJSONObject(i).getInt("id") <= maxId
        }
        val effectiveIndices = if (poolIndices.isEmpty())
            if (setIndices.isEmpty()) (0 until words.length()).toList() else setIndices
        else poolIndices

        val epochDay = System.currentTimeMillis() / 86_400_000L
        // Anchor rotation to install date so day 1 = words 1-6.
        val installEpochDay = flutterPrefs.getInt("flutter.install_epoch_day", -1).toLong()
        val rotationDay = if (installEpochDay < 0) 0L else (epochDay - installEpochDay)
        val startIndex = ((rotationDay * 6) % effectiveIndices.size).toInt()

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
            .getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
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
        // Store as String so Flutter's home_widget (which uses putString) and
        // Kotlin can both read the same value with getString().
        // Remove first to clear any legacy Long value before writing String.
        editor.remove("last_epoch_day")
        editor.putString("last_epoch_day", (System.currentTimeMillis() / 86_400_000L).toString())
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
        private const val SCHEDULE_REF = 826

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
