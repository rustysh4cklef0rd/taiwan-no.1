import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word.dart';

class WordService {
  static List<Word>? _cachedWords;

  /// Loads and caches the full word list from assets.
  static Future<List<Word>> loadWordList() async {
    if (_cachedWords != null) return _cachedWords!;
    final jsonString = await rootBundle.loadString('assets/data/words.json');
    final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
    _cachedWords =
        jsonList.map((e) => Word.fromJson(e as Map<String, dynamic>)).toList();
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
  static Future<List<Word>> getTodaysWords(DateTime date) async {
    final words = await loadWordList();
    final prefs = await SharedPreferences.getInstance();
    final today = _epochDay(date);

    // Build unrecognized pool
    final recognizedRaw = prefs.getString('recognized_ids') ?? '';
    final recognized = recognizedRaw.isEmpty
        ? <int>{}
        : recognizedRaw
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toSet();

    final pool = recognized.isEmpty
        ? words
        : words.where((w) => !recognized.contains(w.id)).toList();
    final effectivePool = pool.isEmpty ? words : pool;

    // Spaced repetition: surface words answered wrong since last seen
    final needsReview = effectivePool.where((w) {
      final attempts = prefs.getInt('quiz_${w.id}_attempts') ?? 0;
      if (attempts == 0) return false;
      final correct = prefs.getInt('quiz_${w.id}_correct') ?? 0;
      final lastSeen = prefs.getInt('quiz_${w.id}_last_seen') ?? -1;
      return correct < attempts && lastSeen < today;
    }).toList();

    // Standard rotation
    final startIndex = (today * 6) % effectivePool.length;
    final rotationWords = List.generate(
        6, (i) => effectivePool[(startIndex + i) % effectivePool.length]);

    // Merge: review words first, then rotation, deduped
    final result = <Word>[];
    final seenIds = <int>{};
    for (final w in [...needsReview, ...rotationWords]) {
      if (result.length >= 6) break;
      if (seenIds.add(w.id)) result.add(w);
    }
    return result;
  }

  /// Cycle progress (what day of the full word-list cycle are we on).
  static Future<Map<String, dynamic>> getProgress(DateTime date) async {
    final words = await loadWordList();
    final int totalWords = words.length;
    final int cycleDays = (totalWords / 6).ceil();
    final int epochDay = _epochDay(date);
    final int dayOfCycle = epochDay % cycleDays;
    final double percent = (dayOfCycle / cycleDays) * 100;
    return {
      'dayOfCycle': dayOfCycle + 1,
      'cycleDays': cycleDays,
      'percent': percent,
    };
  }

  static int _epochDay(DateTime date) =>
      date.toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;

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

  static Future<List<({Word word, bool tapped})>> getTodaysReview() async {
    final today = await getTodaysWords(DateTime.now());
    final prefs = await SharedPreferences.getInstance();
    final day = _epochDay(DateTime.now());
    return today
        .map((w) => (word: w, tapped: prefs.getInt('tapped_${w.id}') == day))
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
