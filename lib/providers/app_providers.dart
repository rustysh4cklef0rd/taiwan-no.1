import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/app_database.dart';
import '../db/tap_repository.dart';
import '../models/word.dart';
import '../services/word_service.dart';

// ── Infrastructure ────────────────────────────────────────────────────────────

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final tapRepositoryProvider = Provider<TapRepository>((ref) {
  return TapRepository(ref.watch(appDatabaseProvider));
});

// ── Settings ──────────────────────────────────────────────────────────────────

@immutable
class AppSettings {
  const AppSettings({
    required this.darkMode,
    required this.quizMode,
    required this.hidePinyin,
    required this.dayOffset,
  });

  final bool darkMode;
  final bool quizMode;
  final bool hidePinyin;
  final int dayOffset;

  AppSettings copyWith({
    bool? darkMode,
    bool? quizMode,
    bool? hidePinyin,
    int? dayOffset,
  }) =>
      AppSettings(
        darkMode: darkMode ?? this.darkMode,
        quizMode: quizMode ?? this.quizMode,
        hidePinyin: hidePinyin ?? this.hidePinyin,
        dayOffset: dayOffset ?? this.dayOffset,
      );
}

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      darkMode: prefs.getBool('dark_mode') ?? true,
      quizMode: prefs.getBool('quiz_mode') ?? false,
      hidePinyin: prefs.getBool('hide_pinyin') ?? false,
      dayOffset: prefs.getInt('day_offset') ?? 0,
    );
  }

  Future<void> setDarkMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', v);
    state = AsyncData(state.value!.copyWith(darkMode: v));
  }

  Future<void> setQuizMode(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quiz_mode', v);
    state = AsyncData(state.value!.copyWith(quizMode: v));
  }

  Future<void> setHidePinyin(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_pinyin', v);
    state = AsyncData(state.value!.copyWith(hidePinyin: v));
  }

  Future<void> setDayOffset(int v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('day_offset', v);
    state = AsyncData(state.value!.copyWith(dayOffset: v));
    // Invalidate today's words so HomeScreen rebuilds
    ref.invalidate(todaysWordsProvider);
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

// ── Tap state ─────────────────────────────────────────────────────────────────

@immutable
class TapState {
  const TapState({
    required this.heatmapData,
    required this.streakCurrent,
    required this.streakLongest,
    required this.todayTapCount,
  });

  final Map<int, int> heatmapData;
  final int streakCurrent;
  final int streakLongest;
  final int todayTapCount;

  TapState copyWith({
    Map<int, int>? heatmapData,
    int? streakCurrent,
    int? streakLongest,
    int? todayTapCount,
  }) =>
      TapState(
        heatmapData: heatmapData ?? this.heatmapData,
        streakCurrent: streakCurrent ?? this.streakCurrent,
        streakLongest: streakLongest ?? this.streakLongest,
        todayTapCount: todayTapCount ?? this.todayTapCount,
      );
}

class TapNotifier extends AsyncNotifier<TapState> {
  @override
  Future<TapState> build() => _loadFromDb();

  Future<TapState> _loadFromDb() async {
    final repo = ref.read(tapRepositoryProvider);
    final heatmap = await repo.getHeatmapData(84);
    final days = await repo.getDaysWithTaps();
    final streaks = _computeStreak(days);
    final todayCount = await repo.getTodayTapCount();
    return TapState(
      heatmapData: heatmap,
      streakCurrent: streaks.$1,
      streakLongest: streaks.$2,
      todayTapCount: todayCount,
    );
  }

  // Optimistic update — instant UI, write queued in background
  void optimisticRecordTap(int wordId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final today = TapRepository.epochDay(DateTime.now());
    final updatedHeatmap = Map<int, int>.from(current.heatmapData)
      ..[today] = (current.heatmapData[today] ?? 0) + 1;
    final newTodayCount = current.todayTapCount + 1;
    state = AsyncData(current.copyWith(
      heatmapData: updatedHeatmap,
      todayTapCount: newTodayCount,
    ));
    // Enqueue the actual write
    ref.read(writeQueueProvider.notifier).enqueue(wordId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(await _loadFromDb());
  }

  static (int current, int longest) _computeStreak(List<int> sortedDays) {
    if (sortedDays.isEmpty) return (0, 0);
    final today = TapRepository.epochDay(DateTime.now());
    int current = 0;
    int longest = 0;
    int streak = 1;

    for (int i = sortedDays.length - 1; i >= 0; i--) {
      if (i == sortedDays.length - 1) {
        // Check if the last tap day is today or yesterday
        if (sortedDays[i] >= today - 1) {
          current = 1;
        }
        continue;
      }
      if (sortedDays[i + 1] - sortedDays[i] == 1) {
        streak++;
        if (current > 0) current = streak;
      } else {
        if (streak > longest) longest = streak;
        streak = 1;
        if (current > 0 && sortedDays[i] < today - 1) break;
      }
    }
    if (streak > longest) longest = streak;
    if (current == 0 && sortedDays.last == today) current = 1;
    return (current, longest);
  }
}

final tapProvider = AsyncNotifierProvider<TapNotifier, TapState>(
  TapNotifier.new,
);

// ── Write queue ───────────────────────────────────────────────────────────────

class _QueueEntry {
  _QueueEntry({required this.wordId, required this.tappedAt});
  final int wordId;
  final DateTime tappedAt;
}

class _WriteQueueNotifier extends Notifier<List<_QueueEntry>> {
  Timer? _flushTimer;

  @override
  List<_QueueEntry> build() {
    ref.onDispose(() => _flushTimer?.cancel());
    return [];
  }

  void enqueue(int wordId) {
    state = [...state, _QueueEntry(wordId: wordId, tappedAt: DateTime.now())];
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushTimer?.isActive == true) return;
    _flushTimer = Timer(const Duration(seconds: 3), _flush);
  }

  Future<void> _flush() async {
    if (state.isEmpty) return;
    final batch = List<_QueueEntry>.from(state);
    state = [];
    final repo = ref.read(tapRepositoryProvider);
    final rows = batch
        .map((e) => (
              wordId: e.wordId,
              tappedAt: e.tappedAt.millisecondsSinceEpoch,
            ))
        .toList();
    try {
      await repo.insertTaps(rows);
    } catch (_) {
      // Re-queue on failure
      state = [
        ...batch.map((e) => _QueueEntry(wordId: e.wordId, tappedAt: e.tappedAt)),
        ...state
      ];
    }
  }
}

final writeQueueProvider =
    NotifierProvider<_WriteQueueNotifier, List<_QueueEntry>>(
  _WriteQueueNotifier.new,
);

// ── Today's words ─────────────────────────────────────────────────────────────

final todaysWordsProvider = FutureProvider<List<Word>>((ref) async {
  final settingsAsync = await ref.watch(appSettingsProvider.future);
  final effectiveDate =
      DateTime.now().add(Duration(days: settingsAsync.dayOffset));
  return WordService.getTodaysWords(effectiveDate);
});
