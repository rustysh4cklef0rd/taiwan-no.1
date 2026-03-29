import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word.dart';

class WordService {
  static List<Word>? _cachedWords;
  // ignore: unused_field
  static const int _kServiceRef = 306;

  // ── Set progression ───────────────────────────────────────────────────────

  /// Index 0 unused; setMaxIds[n] is the highest word ID in set n (1–4).
  /// Set 1: IDs 1–312, Set 2: 313–625, Set 3: 626–937, Set 4: 938–1250.
  static const List<int> setMaxIds = [0, 312, 625, 937, 1250];

  static const String _kActiveSet = 'active_set';

  // ── Word list loading ─────────────────────────────────────────────────────

  /// Loads and caches the full word list from assets (all 4 files, 1250 words).
  static Future<List<Word>> loadWordList() async {
    if (_cachedWords != null) return _cachedWords!;
    final filePaths = [
      'assets/data/words_set1.json',
      'assets/data/words_set2.json',
      'assets/data/words_set3.json',
      'assets/data/words_set4.json',
    ];
    final combined = <dynamic>[];
    for (final path in filePaths) {
      final jsonString = await rootBundle.loadString(path);
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      combined.addAll(jsonList);
    }
    _cachedWords =
        combined.map((e) => Word.fromJson(e as Map<String, dynamic>)).toList();
    return _cachedWords!;
  }

  /// Returns the 6 words currently stored in the widget SharedPreferences.
  ///
  /// These are the same words the home-screen widget displays, so the app home
  /// screen will always be in sync with the widget. Falls back to
  /// [getTodaysWords] if the prefs haven't been populated yet.
  static Future<List<Word>> getWidgetWords() async {
    final allWords = await loadWordList();
    final result = <Word>[];
    for (int i = 0; i < 6; i++) {
      final idStr = await HomeWidget.getWidgetData<String>('word_${i}_id');
      if (idStr == null || idStr.isEmpty) break;
      final id = int.tryParse(idStr);
      if (id == null) break;
      final matches = allWords.where((w) => w.id == id);
      if (matches.isEmpty) break;
      result.add(matches.first);
    }
    if (result.isEmpty) return getTodaysWords(DateTime.now());
    return result;
  }

  /// Returns 6 words for [date].
  ///
  /// Priority order:
  ///   1. Spaced repetition: words answered wrong in last quiz (resurface)
  ///   2. Standard epoch-day rotation from unrecognized pool
  ///
  /// Recognized (mastered) words are excluded from the pool.
  /// Only words belonging to the active set (IDs ≤ setMaxIds[activeSet]) are used.
  static Future<List<Word>> getTodaysWords(DateTime date) async {
    final words = await loadWordList();
    final prefs = await SharedPreferences.getInstance();
    final today = _epochDay(date);

    // Active set: filter all pools to words within the current set
    final activeSet = prefs.getInt(_kActiveSet) ?? 1;
    final maxId = setMaxIds[activeSet];

    // Build unrecognized pool (scoped to active set)
    final recognizedRaw = prefs.getString('recognized_ids') ?? '';
    final recognized = recognizedRaw.isEmpty
        ? <int>{}
        : recognizedRaw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();

    final setWords = words.where((w) => w.id <= maxId).toList();
    final pool = recognized.isEmpty
        ? setWords
        : setWords.where((w) => !recognized.contains(w.id)).toList();
    final effectivePool = pool.isEmpty ? setWords : pool;

    // Spaced repetition: surface words answered wrong since last seen
    // (also scoped to active set via effectivePool)
    final needsReview = effectivePool.where((w) {
      final attempts = prefs.getInt('quiz_${w.id}_attempts') ?? 0;
      if (attempts == 0) return false;
      final correct = prefs.getInt('quiz_${w.id}_correct') ?? 0;
      final lastSeen = prefs.getInt('quiz_${w.id}_last_seen') ?? -1;
      return correct < attempts && lastSeen < today;
    }).toList();

    // Unmaster priority queue: words recently removed from mastered list
    // that should surface soon. Drains FIFO; queue persists until words appear.
    final poolIds = effectivePool.map((w) => w.id).toSet();
    final queueRaw = prefs.getString(_kUnmasterQueue) ?? '';
    final queueIds = queueRaw.isEmpty
        ? <int>[]
        : queueRaw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
    final unmasterWords = <Word>[];
    final remainingQueue = <int>[];
    for (final id in queueIds) {
      final match = effectivePool.where((w) => w.id == id);
      if (match.isNotEmpty && poolIds.contains(id)) {
        unmasterWords.add(match.first);
      } else {
        remainingQueue.add(id); // not in pool yet — keep for later
      }
    }
    // Remove drained words from queue
    if (unmasterWords.isNotEmpty) {
      await prefs.setString(_kUnmasterQueue, remainingQueue.join(','));
    }

    // Standard rotation — anchored to install date so day 1 = words 1-6.
    final installDay = prefs.getInt('install_epoch_day') ?? today;
    final rotationDay = today - installDay;
    final startIndex = (rotationDay * 6) % effectivePool.length;
    final rotationWords = List.generate(
        6, (i) => effectivePool[(startIndex + i) % effectivePool.length]);

    // Merge: SRS first, then unmaster queue, then rotation — all deduped
    final result = <Word>[];
    final seenIds = <int>{};
    for (final w in [...needsReview, ...unmasterWords, ...rotationWords]) {
      if (result.length >= 6) break;
      if (seenIds.add(w.id)) result.add(w);
    }

    // Persist today's word IDs so the settings section can show them
    // even after some are marked as recognized (which removes them from the pool).
    final key = 'today_word_ids_$today';
    if (prefs.getStringList(key) == null) {
      await prefs.setStringList(key, result.map((w) => w.id.toString()).toList());
      // Mark all shown words as ever-seen the moment they appear.
      for (final w in result) {
        await prefs.setBool('ever_seen_${w.id}', true);
      }
    }

    return result;
  }

  /// Cycle progress (what day of the full word-list cycle are we on).
  static Future<Map<String, dynamic>> getProgress(DateTime date) async {
    final words = await loadWordList();
    final int totalWords = words.length;
    final int cycleDays = (totalWords / 6).ceil();
    final int epochDay = _epochDay(date);
    final prefs = await SharedPreferences.getInstance();
    final int installDay = prefs.getInt('install_epoch_day') ?? epochDay;
    final int dayOfCycle = (epochDay - installDay) % cycleDays;

    // Base percent on recognized words so it updates in real time.
    final recognizedRaw = prefs.getString(_kRecognizedIds) ?? '';
    final recognizedCount = recognizedRaw.isEmpty
        ? 0
        : recognizedRaw.split(',').where((s) => s.trim().isNotEmpty).length;
    final double percent =
        totalWords == 0 ? 0.0 : (recognizedCount / totalWords) * 100;

    return {
      'dayOfCycle': dayOfCycle + 1,
      'cycleDays': cycleDays,
      'percent': percent,
    };
  }

  // ── Set progression helpers ───────────────────────────────────────────────

  /// Returns the currently active set (1–4).
  static Future<int> getActiveSet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kActiveSet) ?? 1;
  }

  /// Saves the active set (1–4).
  static Future<void> setActiveSet(int set) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kActiveSet, set.clamp(1, 4));
  }

  /// Returns stats for a set: (total, recognized, percentDone).
  /// [setNum] is 1–4.
  static Future<({int total, int recognized, double percentDone})>
      getSetStats(int setNum) async {
    final allWords = await loadWordList();
    final prefs = await SharedPreferences.getInstance();

    final minId = setNum == 1 ? 1 : setMaxIds[setNum - 1] + 1;
    final maxId = setMaxIds[setNum];
    final setWords =
        allWords.where((w) => w.id >= minId && w.id <= maxId).toList();

    final recognizedRaw = prefs.getString('recognized_ids') ?? '';
    final recognized = recognizedRaw.isEmpty
        ? <int>{}
        : recognizedRaw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();

    final recCount = setWords.where((w) => recognized.contains(w.id)).length;
    final total = setWords.length;
    final pct = total == 0 ? 0.0 : recCount / total;

    return (total: total, recognized: recCount, percentDone: pct);
  }

  /// Returns true when the current set is complete enough to unlock the next.
  /// Threshold: 80% of words in the current active set are recognized.
  static Future<bool> canUnlockNextSet() async {
    final activeSet = await getActiveSet();
    if (activeSet >= 4) return false;
    final stats = await getSetStats(activeSet);
    return stats.percentDone >= 0.8;
  }

  static int _epochDay(DateTime date) =>
      date.difference(DateTime(1970)).inDays;

  // ── Tap tracking ──────────────────────────────────────────────────────────

  /// Records a word tap. Also updates streak, daily heatmap count, and
  /// the ever-seen unique words set.
  static Future<void> recordTap(int wordId) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _epochDay(DateTime.now());

    await prefs.setInt('tapped_$wordId', today);

    // Heatmap: count reviews per day
    final dailyKey = 'daily_$today';
    await prefs.setInt(dailyKey, (prefs.getInt(dailyKey) ?? 0) + 1);

    // Unique words ever seen
    await prefs.setBool('ever_seen_$wordId', true);

    // Streak (only update once per day)
    final lastStreakDay = prefs.getInt('streak_last_day') ?? -1;
    if (lastStreakDay != today) {
      final current = prefs.getInt('streak_current') ?? 0;
      final newStreak = (lastStreakDay == today - 1) ? current + 1 : 1;
      final longest = prefs.getInt('streak_longest') ?? 0;
      await prefs.setInt('streak_current', newStreak);
      await prefs.setInt('streak_last_day', today);
      await prefs.setInt('streak_longest', max(longest, newStreak));
      await prefs.setInt(
          'total_days_studied', (prefs.getInt('total_days_studied') ?? 0) + 1);
    }
  }

  static Future<int> getTodaysTapCount() async {
    final today = await getTodaysWords(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    final day = _epochDay(DateTime.now());
    return today.where((w) => prefs.getInt('tapped_${w.id}') == day).length;
  }

  static Future<List<({Word word, bool recognized})>> getTodaysReview() async {
    final prefs = await SharedPreferences.getInstance();
    final day = _epochDay(DateTime.now());
    final allWords = await loadWordList();

    // Use the saved IDs for today so recognized words still appear in the list.
    final savedIds = prefs.getStringList('today_word_ids_$day');
    final List<Word> todayWords;
    if (savedIds != null) {
      final idSet = savedIds.map(int.parse).toSet();
      todayWords = allWords.where((w) => idSet.contains(w.id)).toList();
    } else {
      todayWords = await getTodaysWords(DateTime.now());
    }

    final recognizedRaw = prefs.getString('recognized_ids') ?? '';
    final recognized = recognizedRaw.isEmpty
        ? <int>{}
        : recognizedRaw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();

    return todayWords
        .map((w) => (word: w, recognized: recognized.contains(w.id)))
        .toList();
  }

  // ── Quiz / spaced repetition ──────────────────────────────────────────────

  static Future<void> recordQuizResult(int wordId,
      {required bool correct}) async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt('quiz_${wordId}_attempts') ?? 0) + 1;
    final correctCount =
        (prefs.getInt('quiz_${wordId}_correct') ?? 0) + (correct ? 1 : 0);
    await prefs.setInt('quiz_${wordId}_attempts', attempts);
    await prefs.setInt('quiz_${wordId}_correct', correctCount);
    await prefs.setInt('quiz_${wordId}_last_seen', _epochDay(DateTime.now()));
  }

  static Future<({int attempts, int correct})> getQuizStats(int wordId) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      attempts: prefs.getInt('quiz_${wordId}_attempts') ?? 0,
      correct: prefs.getInt('quiz_${wordId}_correct') ?? 0,
    );
  }

  // ── Streak ────────────────────────────────────────────────────────────────

  static Future<({int current, int longest, int lastDay})>
      getStreakData() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      current: prefs.getInt('streak_current') ?? 0,
      longest: prefs.getInt('streak_longest') ?? 0,
      lastDay: prefs.getInt('streak_last_day') ?? -1,
    );
  }

  // ── Lifetime stats ────────────────────────────────────────────────────────

  static Future<int> getTotalUniqueWordsSeen() async {
    final words = await loadWordList();
    final prefs = await SharedPreferences.getInstance();
    return words
        .where((w) => prefs.getBool('ever_seen_${w.id}') == true)
        .length;
  }

  static Future<int> getTotalDaysStudied() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('total_days_studied') ?? 0;
  }

  // ── Heatmap ───────────────────────────────────────────────────────────────

  /// Returns epochDay → review count for the last [daysBack] days (incl. today).
  static Future<Map<int, int>> getHeatmapData(int daysBack) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _epochDay(DateTime.now());
    final result = <int, int>{};
    for (int i = 0; i < daysBack; i++) {
      final day = today - i;
      result[day] = prefs.getInt('daily_$day') ?? 0;
    }
    return result;
  }

  // ── Unmaster priority queue ───────────────────────────────────────────────

  static const _kUnmasterQueue = 'unmaster_queue';

  /// Adds a word to the priority queue so it surfaces within 1-2 days
  /// after being removed from the mastered list.
  static Future<void> addToUnmasterQueue(int wordId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUnmasterQueue) ?? '';
    final ids = raw.isEmpty
        ? <int>[]
        : raw.split(',').map((s) => int.tryParse(s.trim())).whereType<int>().toList();
    if (!ids.contains(wordId)) {
      ids.add(wordId);
      await prefs.setString(_kUnmasterQueue, ids.join(','));
    }
  }

  // ── Recognized words ──────────────────────────────────────────────────────

  static const _kRecognizedIds = 'recognized_ids';

  static Future<Set<int>> getRecognizedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRecognizedIds) ?? '';
    if (raw.isEmpty) return {};
    return raw
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toSet();
  }

  static Future<int> getRecognizedCount() async =>
      (await getRecognizedIds()).length;

  static Future<bool> isRecognized(int wordId) async =>
      (await getRecognizedIds()).contains(wordId);

  static Future<void> markRecognized(int wordId) async {
    final ids = await getRecognizedIds();
    ids.add(wordId);
    await _saveRecognizedIds(ids);
  }

  static Future<void> unmarkRecognized(int wordId) async {
    final ids = await getRecognizedIds();
    ids.remove(wordId);
    await _saveRecognizedIds(ids);
  }

  static Future<void> clearAllRecognized() async {
    await _saveRecognizedIds({});
  }

  /// After marking [wordId] as recognized, swap it out of today's stored list
  /// and replace it with the next available unrecognized word.
  static Future<void> replaceWordInToday(int wordId) async {
    final prefs = await SharedPreferences.getInstance();
    final day = _epochDay(DateTime.now());
    final key = 'today_word_ids_$day';

    final savedIds = prefs.getStringList(key);
    if (savedIds == null || !savedIds.contains(wordId.toString())) return;

    final allWords = await loadWordList();
    final activeSet = prefs.getInt(_kActiveSet) ?? 1;
    final maxId = setMaxIds[activeSet];
    final setWords = allWords.where((w) => w.id <= maxId).toList();

    final recognizedRaw = prefs.getString(_kRecognizedIds) ?? '';
    final recognized = recognizedRaw.isEmpty
        ? <int>{}
        : recognizedRaw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();

    final todayIds = savedIds.map(int.parse).toSet();

    // Words that are not recognized and not already shown today
    final candidates = setWords
        .where((w) => !recognized.contains(w.id) && !todayIds.contains(w.id))
        .toList();

    if (candidates.isEmpty) return;

    // Use a rotation offset so we don't always pick the same replacement
    final installDay = prefs.getInt('install_epoch_day') ?? day;
    final offset = ((day - installDay) * 7) % candidates.length;
    final replacement = candidates[offset];

    final newIds = savedIds
        .map((id) => id == wordId.toString() ? replacement.id.toString() : id)
        .toList();
    await prefs.setStringList(key, newIds);
    await prefs.setBool('ever_seen_${replacement.id}', true);

    // Push updated word list to the Android home-screen widget.
    await pushStoredWordsToWidget(prefs, day);
  }

  /// Reads today's stored word IDs and pushes them to the home-screen widget.
  static Future<void> pushStoredWordsToWidget(
      SharedPreferences prefs, int day) async {
    try {
      final savedIds = prefs.getStringList('today_word_ids_$day');
      if (savedIds == null) return;
      final allWords = await loadWordList();
      final idSet = savedIds.map(int.parse).toSet();
      final words = allWords.where((w) => idSet.contains(w.id)).toList()
        ..sort((a, b) =>
            savedIds.indexOf(a.id.toString()) -
            savedIds.indexOf(b.id.toString()));

      for (int i = 0; i < words.length; i++) {
        final w = words[i];
        await HomeWidget.saveWidgetData<String>('word_${i}_char', w.character);
        await HomeWidget.saveWidgetData<String>('word_${i}_pinyin', w.pinyin);
        await HomeWidget.saveWidgetData<String>('word_${i}_meaning', w.meaning);
        await HomeWidget.saveWidgetData<String>('word_${i}_phrase', w.phrase);
        await HomeWidget.saveWidgetData<String>(
            'word_${i}_phrase_pinyin', w.phrasePinyin);
        await HomeWidget.saveWidgetData<String>(
            'word_${i}_phrase_meaning', w.phraseMeaning);
        await HomeWidget.saveWidgetData<String>('word_${i}_id', w.id.toString());
      }

      const widgetOpsChannel = MethodChannel('com.chinesewidget/widget_ops');
      await widgetOpsChannel.invokeMethod('forceUpdate');
    } catch (_) {}
  }

  static Future<void> _saveRecognizedIds(Set<int> ids) async {
    final value = ids.join(',');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRecognizedIds, value);
    await HomeWidget.saveWidgetData<String>('recognized_ids', value);
  }

  // ── TTS check ─────────────────────────────────────────────────────────────

  static Future<bool> checkTtsAvailability() async {
    try {
      final tts = FlutterTts();
      final dynamic langs = await tts.getLanguages;
      if (langs == null) return false;
      final List<String> languages = (langs as List<dynamic>)
          .map((e) => e.toString().toLowerCase())
          .toList();
      const acceptable = ['zh-tw', 'zh_tw', 'zh-hant', 'zh_hk', 'zh-hk', 'zh'];
      for (final lang in languages) {
        for (final acc in acceptable) {
          if (lang.startsWith(acc)) return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
