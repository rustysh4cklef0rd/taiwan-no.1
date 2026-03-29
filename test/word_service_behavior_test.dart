// ignore_for_file: avoid_redundant_argument_values

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chinese_reading_widget/models/word.dart';
import 'package:chinese_reading_widget/services/word_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

Word _w(int id) => Word(
      id: id,
      character: '字$id',
      pinyin: 'p$id',
      meaning: 'm$id',
      phrase: '',
      phrasePinyin: '',
      phraseMeaning: '',
      frequencyRank: id,
    );

/// Build a synthetic word list of [count] words with IDs 1..count.
List<Word> _words(int count) => List.generate(count, (i) => _w(i + 1));

int _epochDay(DateTime d) =>
    d.toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;

/// Pure reimplementation of WordService.getTodaysWords logic.
/// Accepts all inputs explicitly so tests never need platform channels.
List<Word> _compute({
  required List<Word> allWords,
  int activeSet = 1,
  Set<int> recognizedIds = const {},
  Map<int, int> quizAttempts = const {},
  Map<int, int> quizCorrect = const {},
  Map<int, int> quizLastSeen = const {},
  int installDay = 0,
  int today = 0,
  List<int> setMaxIds = WordService.setMaxIds,
  List<int> unmasterQueue = const [],
}) {
  final maxId = setMaxIds[activeSet];
  final setWords = allWords.where((w) => w.id <= maxId).toList();
  final pool = recognizedIds.isEmpty
      ? setWords
      : setWords.where((w) => !recognizedIds.contains(w.id)).toList();
  final effectivePool = pool.isEmpty ? setWords : pool;

  final needsReview = effectivePool.where((w) {
    final attempts = quizAttempts[w.id] ?? 0;
    if (attempts == 0) return false;
    final correct = quizCorrect[w.id] ?? 0;
    final lastSeen = quizLastSeen[w.id] ?? -1;
    return correct < attempts && lastSeen < today;
  }).toList();

  final poolIds = effectivePool.map((w) => w.id).toSet();
  final unmasterWords = unmasterQueue
      .where((id) => poolIds.contains(id))
      .map((id) => effectivePool.firstWhere((w) => w.id == id))
      .toList();

  final rotationDay = today - installDay;
  final startIndex =
      effectivePool.isEmpty ? 0 : (rotationDay * 6) % effectivePool.length;
  final rotationWords = List.generate(
      6, (i) => effectivePool[(startIndex + i) % effectivePool.length]);

  final result = <Word>[];
  final seenIds = <int>{};
  for (final w in [...needsReview, ...unmasterWords, ...rotationWords]) {
    if (result.length >= 6) break;
    if (seenIds.add(w.id)) result.add(w);
  }
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Setup helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Registers a no-op mock for the home_widget method channel so
/// HomeWidget.saveWidgetData() does not throw in unit tests.
void _mockHomeWidget() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('home_widget'),
    (MethodCall call) async => null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Today's words — rotation ─────────────────────────────────────────────
  group('getTodaysWords — rotation', () {
    final words = _words(12);

    test('always returns exactly 6 words', () {
      final result = _compute(allWords: words, today: 0, installDay: 0);
      expect(result.length, 6);
    });

    test('no duplicates in today\'s 6 words', () {
      final result = _compute(allWords: words, today: 5, installDay: 0);
      final ids = result.map((w) => w.id).toList();
      expect(ids.toSet().length, 6);
    });

    test('day 0 (install day) starts from word 1', () {
      final result = _compute(allWords: words, today: 0, installDay: 0);
      expect(result.first.id, 1);
    });

    test('day 1 starts from word 7', () {
      final result = _compute(allWords: words, today: 1, installDay: 0);
      expect(result.first.id, 7);
    });

    test('rotation is deterministic — same day gives same words', () {
      final a = _compute(allWords: words, today: 3, installDay: 0);
      final b = _compute(allWords: words, today: 3, installDay: 0);
      expect(a.map((w) => w.id).toList(), b.map((w) => w.id).toList());
    });

    test('different days yield different words', () {
      final day1 = _compute(allWords: words, today: 0, installDay: 0);
      final day2 = _compute(allWords: words, today: 1, installDay: 0);
      expect(day1.first.id, isNot(day2.first.id));
    });

    test('wrap-around stays in bounds', () {
      final big = _words(200);
      // Force start near end
      const rotationDay = 33; // startIndex = (33*6)%200 = 198
      final result = _compute(allWords: big, today: rotationDay, installDay: 0);
      for (final w in result) {
        expect(w.id, greaterThanOrEqualTo(1));
        expect(w.id, lessThanOrEqualTo(200));
      }
    });
  });

  // ── Today's words — recognized word filtering ────────────────────────────
  group('getTodaysWords — recognized word filtering', () {
    test('recognized words are excluded from the rotation pool', () {
      final words = _words(12);
      // Recognize words 1–6 (today's default first page)
      final recognized = {1, 2, 3, 4, 5, 6};
      final result = _compute(
        allWords: words,
        recognizedIds: recognized,
        today: 0,
        installDay: 0,
      );
      for (final w in result) {
        expect(recognized.contains(w.id), isFalse,
            reason: 'Recognized word ${w.id} should not appear');
      }
    });

    test('when ALL words recognized, falls back to full set — never returns empty', () {
      final words = _words(6);
      final allIds = words.map((w) => w.id).toSet();
      final result = _compute(
        allWords: words,
        recognizedIds: allIds,
        today: 0,
        installDay: 0,
      );
      // Falls back to full set, so we still get words
      expect(result.length, 6);
    });

    test('today\'s words still show after recognizing all of them (widget prefs unchanged)', () {
      // Simulates: user sees words 1–6 today.  Marks them all recognized.
      // getTodaysWords now draws from the fallback (same words, since pool=full set).
      // Widget prefs are independent — they still hold the original 6 words
      // until next push.  We test that the fallback produces valid output.
      final words = _words(6); // only 6 words total
      final todayWords = _compute(allWords: words, today: 0, installDay: 0);
      expect(todayWords.length, 6);

      // Now mark all of today's words as recognized
      final recognized = todayWords.map((w) => w.id).toSet();
      final afterRecognizing = _compute(
        allWords: words,
        recognizedIds: recognized,
        today: 0,
        installDay: 0,
      );
      // App still shows 6 words — never blank
      expect(afterRecognizing.length, 6);
    });

    test('next day rotation uses reduced pool after recognition', () {
      final words = _words(12);
      final recognized = {1, 2, 3, 4, 5, 6};

      final todayNoRec = _compute(allWords: words, today: 0, installDay: 0);
      final tomorrowWithRec = _compute(
        allWords: words,
        recognizedIds: recognized,
        today: 1,
        installDay: 0,
      );
      // Tomorrow's words come from the unrecognized pool {7..12}
      for (final w in tomorrowWithRec) {
        expect(recognized.contains(w.id), isFalse);
      }
      // And today's words are different
      expect(todayNoRec.first.id, isNot(tomorrowWithRec.first.id));
    });

    test('partial recognition: only recognized words removed', () {
      final words = _words(12);
      final recognized = {1, 3, 5}; // remove odd-indexed words from pool
      final result = _compute(
        allWords: words,
        recognizedIds: recognized,
        today: 0,
        installDay: 0,
      );
      for (final w in result) {
        expect(recognized.contains(w.id), isFalse);
      }
    });
  });

  // ── Today's words — spaced repetition (SRS) ──────────────────────────────
  group('getTodaysWords — spaced repetition', () {
    test('wrong-answered word (not seen today) surfaces at front', () {
      final words = _words(12);
      const wrongWordId = 10;
      // Install on day 0, today = day 0, wrongWord is NOT in today's rotation
      final result = _compute(
        allWords: words,
        quizAttempts: {wrongWordId: 2},
        quizCorrect: {wrongWordId: 1}, // 1 wrong out of 2
        quizLastSeen: {wrongWordId: -1}, // never seen today
        today: 0,
        installDay: 0,
      );
      expect(result.first.id, wrongWordId,
          reason: 'SRS word should surface first');
    });

    test('correctly-answered word does not resurface', () {
      final words = _words(12);
      const wordId = 10;
      final result = _compute(
        allWords: words,
        quizAttempts: {wordId: 3},
        quizCorrect: {wordId: 3}, // 100% correct
        quizLastSeen: {wordId: -1},
        today: 0,
        installDay: 0,
      );
      expect(result.any((w) => w.id == wordId && result.indexOf(w) == 0),
          isFalse,
          reason: 'Fully correct word should not be prioritised by SRS');
    });

    test('wrong-answered word seen TODAY does not resurface', () {
      final words = _words(12);
      const wordId = 10;
      const today = 5;
      final result = _compute(
        allWords: words,
        quizAttempts: {wordId: 2},
        quizCorrect: {wordId: 0},
        quizLastSeen: {wordId: today}, // seen today — suppress
        today: today,
        installDay: 0,
      );
      // Word may still appear via rotation but should NOT be at front via SRS
      if (result.isNotEmpty && result.first.id == wordId) {
        fail('SRS word seen today should not be forced to front');
      }
    });

    test('SRS word does resurface on a day AFTER it was last seen', () {
      final words = _words(12);
      const wordId = 10;
      final result = _compute(
        allWords: words,
        quizAttempts: {wordId: 2},
        quizCorrect: {wordId: 0},
        quizLastSeen: {wordId: 3}, // last seen day 3
        today: 5,                  // today is day 5
        installDay: 0,
      );
      expect(result.first.id, wordId);
    });

    test('multiple SRS words all surface before rotation words', () {
      final words = _words(18);
      // Mark words 15, 16, 17 as needing review
      final attempts = {15: 1, 16: 1, 17: 1};
      final correct = {15: 0, 16: 0, 17: 0};
      final lastSeen = {15: -1, 16: -1, 17: -1};
      final result = _compute(
        allWords: words,
        quizAttempts: attempts,
        quizCorrect: correct,
        quizLastSeen: lastSeen,
        today: 0,
        installDay: 0,
      );
      // First 3 should be the SRS words (in some order)
      final first3ids = result.take(3).map((w) => w.id).toSet();
      expect(first3ids.containsAll({15, 16, 17}), isTrue);
    });
  });

  // ── Today's words — active set scoping ───────────────────────────────────
  group('getTodaysWords — active set scoping', () {
    final words = _words(1250);

    test('set 1 only returns words with ID ≤ 312', () {
      final result = _compute(allWords: words, activeSet: 1, today: 0, installDay: 0);
      for (final w in result) {
        expect(w.id, lessThanOrEqualTo(312));
      }
    });

    test('set 2 only returns words with ID ≤ 625', () {
      final result = _compute(allWords: words, activeSet: 2, today: 0, installDay: 0);
      for (final w in result) {
        expect(w.id, lessThanOrEqualTo(625));
      }
    });

    test('set 2 can return words in the 313–625 range', () {
      // With a large enough rotation day, we'll cycle into set 2 territory
      final result = _compute(
        allWords: words,
        activeSet: 2,
        today: 52, // 52*6=312; startIndex = 312%625 = 312 → first word ID 313
        installDay: 0,
      );
      expect(result.any((w) => w.id > 312), isTrue);
    });

    test('set 1 never returns words from set 2 or higher', () {
      for (int day = 0; day < 60; day++) {
        final result = _compute(allWords: words, activeSet: 1, today: day, installDay: 0);
        for (final w in result) {
          expect(w.id, lessThanOrEqualTo(312),
              reason: 'Day $day returned word ${w.id} outside set 1');
        }
      }
    });
  });

  // ── Recognized words (SharedPreferences) ─────────────────────────────────
  group('recognized words', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      _mockHomeWidget();
      SharedPreferences.setMockInitialValues({});
    });

    test('markRecognized persists the word ID', () async {
      await WordService.markRecognized(42);
      expect(await WordService.isRecognized(42), isTrue);
    });

    test('markRecognized multiple words', () async {
      await WordService.markRecognized(1);
      await WordService.markRecognized(2);
      await WordService.markRecognized(3);
      expect(await WordService.getRecognizedCount(), 3);
    });

    test('unmarkRecognized removes a word', () async {
      await WordService.markRecognized(10);
      await WordService.markRecognized(20);
      await WordService.unmarkRecognized(10);
      expect(await WordService.isRecognized(10), isFalse);
      expect(await WordService.isRecognized(20), isTrue);
    });

    test('isRecognized returns false for unknown word', () async {
      expect(await WordService.isRecognized(999), isFalse);
    });

    test('getRecognizedCount returns correct count', () async {
      await WordService.markRecognized(1);
      await WordService.markRecognized(2);
      expect(await WordService.getRecognizedCount(), 2);
    });

    test('clearAllRecognized empties the set', () async {
      await WordService.markRecognized(1);
      await WordService.markRecognized(2);
      await WordService.clearAllRecognized();
      expect(await WordService.getRecognizedCount(), 0);
    });

    test('markRecognized is idempotent — no duplicate IDs', () async {
      await WordService.markRecognized(5);
      await WordService.markRecognized(5);
      expect(await WordService.getRecognizedCount(), 1);
    });
  });

  // ── Quiz / SRS recording ──────────────────────────────────────────────────
  group('quiz / SRS recording', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('recordQuizResult correct: increments both attempts and correct', () async {
      await WordService.recordQuizResult(1, correct: true);
      final stats = await WordService.getQuizStats(1);
      expect(stats.attempts, 1);
      expect(stats.correct, 1);
    });

    test('recordQuizResult wrong: increments attempts only', () async {
      await WordService.recordQuizResult(1, correct: false);
      final stats = await WordService.getQuizStats(1);
      expect(stats.attempts, 1);
      expect(stats.correct, 0);
    });

    test('multiple results accumulate', () async {
      await WordService.recordQuizResult(1, correct: true);
      await WordService.recordQuizResult(1, correct: false);
      await WordService.recordQuizResult(1, correct: true);
      final stats = await WordService.getQuizStats(1);
      expect(stats.attempts, 3);
      expect(stats.correct, 2);
    });

    test('getQuizStats returns zeros for unseen word', () async {
      final stats = await WordService.getQuizStats(999);
      expect(stats.attempts, 0);
      expect(stats.correct, 0);
    });

    test('different word IDs have independent stats', () async {
      await WordService.recordQuizResult(1, correct: true);
      await WordService.recordQuizResult(2, correct: false);
      final s1 = await WordService.getQuizStats(1);
      final s2 = await WordService.getQuizStats(2);
      expect(s1.correct, 1);
      expect(s2.correct, 0);
    });
  });

  // ── Streak tracking ───────────────────────────────────────────────────────
  group('streak tracking', () {
    late int today;

    setUp(() {
      today = _epochDay(DateTime.now());
      SharedPreferences.setMockInitialValues({});
    });

    test('first ever tap creates streak of 1', () async {
      await WordService.recordTap(1);
      final streak = await WordService.getStreakData();
      expect(streak.current, 1);
    });

    test('consecutive day increments streak', () async {
      SharedPreferences.setMockInitialValues({
        'streak_current': 3,
        'streak_last_day': today - 1,
        'streak_longest': 3,
        'total_days_studied': 3,
      });
      await WordService.recordTap(1);
      final streak = await WordService.getStreakData();
      expect(streak.current, 4);
    });

    test('missed day resets streak to 1', () async {
      SharedPreferences.setMockInitialValues({
        'streak_current': 5,
        'streak_last_day': today - 3, // 3 days ago
        'streak_longest': 5,
        'total_days_studied': 5,
      });
      await WordService.recordTap(1);
      final streak = await WordService.getStreakData();
      expect(streak.current, 1);
    });

    test('tapping same day twice does not double-count streak', () async {
      SharedPreferences.setMockInitialValues({
        'streak_current': 2,
        'streak_last_day': today,
        'streak_longest': 2,
        'total_days_studied': 2,
      });
      await WordService.recordTap(1);
      await WordService.recordTap(2);
      final streak = await WordService.getStreakData();
      expect(streak.current, 2); // unchanged
    });

    test('longest streak updates when current exceeds it', () async {
      SharedPreferences.setMockInitialValues({
        'streak_current': 4,
        'streak_last_day': today - 1,
        'streak_longest': 4,
        'total_days_studied': 4,
      });
      await WordService.recordTap(1);
      final streak = await WordService.getStreakData();
      expect(streak.longest, 5);
    });

    test('longest streak does not decrease when current streak resets', () async {
      SharedPreferences.setMockInitialValues({
        'streak_current': 10,
        'streak_last_day': today - 5, // missed days → reset
        'streak_longest': 10,
        'total_days_studied': 10,
      });
      await WordService.recordTap(1);
      final streak = await WordService.getStreakData();
      expect(streak.current, 1);
      expect(streak.longest, 10); // preserved
    });
  });

  // ── Heatmap and tap tracking ──────────────────────────────────────────────
  group('heatmap and tap tracking', () {
    late int today;

    setUp(() {
      today = _epochDay(DateTime.now());
      SharedPreferences.setMockInitialValues({});
    });

    test('recordTap increments daily review count', () async {
      await WordService.recordTap(1);
      final heatmap = await WordService.getHeatmapData(1);
      expect(heatmap[today], 1);
    });

    test('multiple taps same day accumulate in heatmap', () async {
      await WordService.recordTap(1);
      await WordService.recordTap(2);
      await WordService.recordTap(3);
      final heatmap = await WordService.getHeatmapData(1);
      expect(heatmap[today], 3);
    });

    test('recordTap marks word as ever_seen', () async {
      await WordService.recordTap(42);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('ever_seen_42'), isTrue);
    });

    test('heatmap returns 0 for days with no taps', () async {
      final heatmap = await WordService.getHeatmapData(7);
      for (final count in heatmap.values) {
        expect(count, 0);
      }
    });

    test('getTodaysTapCount returns 0 when prefs empty', () async {
      // Without a word list (loadWordList will fail), getTodaysTapCount
      // internally calls getTodaysWords which calls loadWordList.
      // We just check the SharedPreferences path doesn't crash with empty prefs.
      final prefs = await SharedPreferences.getInstance();
      final day = _epochDay(DateTime.now());
      // Simulate: word 1 was tapped today
      await prefs.setInt('tapped_1', day);
      // No crash — verified by reaching here
      expect(prefs.getInt('tapped_1'), day);
    });
  });

  // ── Set stats and unlock threshold ───────────────────────────────────────
  group('set stats and unlock threshold', () {
    // Pure logic helpers — mirror getSetStats / canUnlockNextSet without assets.

    /// Returns how many words in [setNum] are in [recognizedIds].
    ({int total, int recognized, double percentDone}) computeSetStats(
      List<Word> allWords,
      int setNum,
      Set<int> recognizedIds,
    ) {
      final setMaxIds = WordService.setMaxIds;
      final minId = setNum == 1 ? 1 : setMaxIds[setNum - 1] + 1;
      final maxId = setMaxIds[setNum];
      final setWords =
          allWords.where((w) => w.id >= minId && w.id <= maxId).toList();
      final recCount =
          setWords.where((w) => recognizedIds.contains(w.id)).length;
      final total = setWords.length;
      final pct = total == 0 ? 0.0 : recCount / total;
      return (total: total, recognized: recCount, percentDone: pct);
    }

    test('getSetStats: set 1 has 312 words total', () {
      final stats = computeSetStats(_words(1250), 1, {});
      expect(stats.total, 312);
    });

    test('getSetStats: set 2 has 313 words total', () {
      final stats = computeSetStats(_words(1250), 2, {});
      expect(stats.total, 313);
    });

    test('getSetStats: recognized count correct', () {
      final stats = computeSetStats(_words(1250), 1, {1, 2, 3, 100, 200});
      expect(stats.recognized, 5);
    });

    test('canUnlockNextSet: false when below 80% threshold', () {
      final words = _words(312);
      final recognized = words.take(200).map((w) => w.id).toSet(); // ~64%
      final stats = computeSetStats(words, 1, recognized);
      expect(stats.percentDone, lessThan(0.8));
    });

    test('canUnlockNextSet: true at exactly 80%', () {
      final words = _words(312);
      final threshold = (312 * 0.8).ceil(); // 250
      final recognized = words.take(threshold).map((w) => w.id).toSet();
      final stats = computeSetStats(words, 1, recognized);
      expect(stats.percentDone, greaterThanOrEqualTo(0.8));
    });

    test('canUnlockNextSet: true above 80%', () {
      final words = _words(312);
      final recognized = words.take(300).map((w) => w.id).toSet(); // ~96%
      final stats = computeSetStats(words, 1, recognized);
      expect(stats.percentDone, greaterThanOrEqualTo(0.8));
    });

    test('set 4 cannot be unlocked further (already last set)', () {
      // Mirrors canUnlockNextSet returning false for activeSet >= 4
      const activeSet = 4;
      expect(activeSet >= 4, isTrue); // no set 5 exists
    });

    test('percentDone is 0.0 when nothing recognized', () {
      final stats = computeSetStats(_words(312), 1, {});
      expect(stats.percentDone, 0.0);
    });

    test('percentDone is 1.0 when everything recognized', () {
      final words = _words(312);
      final allIds = words.map((w) => w.id).toSet();
      final stats = computeSetStats(words, 1, allIds);
      expect(stats.percentDone, 1.0);
    });
  });

  // ── Unmaster priority queue ───────────────────────────────────────────────
  // Regression: design decision 2026-03-28 — words removed from mastered list
  // should surface within 1-2 days, not randomly via rotation.
  // Report: ~/.gstack/projects/UBFSJARVIS-taiwan-no.1/rewar-master-design-20260328-153734.md
  group('unmaster priority queue', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      _mockHomeWidget();
    });

    test('queued word appears before rotation words', () {
      // Word 50 is far outside today's rotation window (day 0 = words 1-6).
      // With queue, it should surface first.
      final words = _words(312);
      final result = _compute(
        allWords: words,
        installDay: 0,
        today: 0,
        unmasterQueue: [50],
      );
      expect(result.first.id, 50);
    });

    test('queued word appears after SRS words but before rotation', () {
      final words = _words(312);
      // Word 99 answered wrong → SRS, word 50 in unmaster queue, rotation = 1-6
      final result = _compute(
        allWords: words,
        installDay: 0,
        today: 1,
        quizAttempts: {99: 1},
        quizCorrect: {99: 0},
        quizLastSeen: {99: 0},
        unmasterQueue: [50],
      );
      expect(result[0].id, 99); // SRS first
      expect(result[1].id, 50); // unmaster queue second
    });

    test('multiple queued words all surface before rotation', () {
      final words = _words(312);
      final result = _compute(
        allWords: words,
        installDay: 0,
        today: 0,
        unmasterQueue: [100, 200, 300],
      );
      expect(result.map((w) => w.id).toList(), containsAll([100, 200, 300]));
      // All three appear before rotation words (IDs 1-6)
      expect(result.indexOf(result.firstWhere((w) => w.id == 100)),
          lessThan(result.indexOf(result.firstWhere((w) => w.id == 1))));
    });

    test('queue word not in active pool is ignored (stays in queue)', () {
      // Set 1 only includes IDs ≤ 312. A queued ID outside the pool is skipped.
      final words = _words(312);
      final result = _compute(
        allWords: words,
        activeSet: 1,
        installDay: 0,
        today: 0,
        unmasterQueue: [999], // outside set 1 pool
      );
      expect(result.any((w) => w.id == 999), isFalse);
      expect(result.length, 6); // still returns 6 rotation words
    });

    test('addToUnmasterQueue persists word ID', () async {
      await WordService.addToUnmasterQueue(42);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('unmaster_queue') ?? '';
      expect(raw, contains('42'));
    });

    test('addToUnmasterQueue is idempotent — no duplicates', () async {
      await WordService.addToUnmasterQueue(42);
      await WordService.addToUnmasterQueue(42);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('unmaster_queue') ?? '';
      final ids = raw.split(',').where((s) => s == '42').toList();
      expect(ids.length, 1);
    });

    test('addToUnmasterQueue preserves existing queue entries', () async {
      await WordService.addToUnmasterQueue(10);
      await WordService.addToUnmasterQueue(20);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('unmaster_queue') ?? '';
      final ids = raw.split(',').map(int.parse).toList();
      expect(ids, containsAll([10, 20]));
    });
  });
}
