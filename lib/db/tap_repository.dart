import 'package:drift/drift.dart';
import 'app_database.dart';

class TapRepository {
  TapRepository(this._db);
  final AppDatabase _db;

  static int epochDay(DateTime dt) =>
      dt.toUtc().millisecondsSinceEpoch ~/ 86400000;

  Future<void> insertTap(int wordId, DateTime at) async {
    await _db.into(_db.taps).insert(
      TapsCompanion.insert(
        wordId: wordId,
        tappedAt: at.millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> insertTaps(List<({int wordId, int tappedAt})> rows) async {
    await _db.batch((batch) {
      batch.insertAll(
        _db.taps,
        rows.map((r) => TapsCompanion.insert(
              wordId: r.wordId,
              tappedAt: r.tappedAt,
            )),
      );
    });
  }

  Future<Map<int, int>> getHeatmapData(int daysBack) async {
    final today = epochDay(DateTime.now());
    final cutoff = (today - daysBack) * 86400000;
    final rows = await (_db.selectOnly(_db.taps)
          ..addColumns([_db.taps.tappedAt, _db.taps.tappedAt.count()])
          ..where(_db.taps.tappedAt.isBiggerOrEqualValue(cutoff))
          ..groupBy([_db.taps.tappedAt]))
        .get();

    // Aggregate by epochDay
    final result = <int, int>{};
    for (int i = 0; i < daysBack; i++) {
      result[today - i] = 0;
    }
    for (final row in rows) {
      final ms = row.read(_db.taps.tappedAt) ?? 0;
      final day = ms ~/ 86400000;
      result[day] = (result[day] ?? 0) + 1;
    }
    return result;
  }

  Future<List<int>> getDaysWithTaps() async {
    final rows = await (_db.selectOnly(_db.taps)
          ..addColumns([_db.taps.tappedAt])
          ..groupBy([_db.taps.tappedAt]))
        .get();
    final days = <int>{};
    for (final row in rows) {
      final ms = row.read(_db.taps.tappedAt) ?? 0;
      days.add(ms ~/ 86400000);
    }
    return days.toList()..sort();
  }

  Future<int> getTodayTapCount() async {
    final today = epochDay(DateTime.now());
    final startMs = today * 86400000;
    final endMs = startMs + 86400000;
    final count = await (_db.taps.count(
      where: (t) =>
          t.tappedAt.isBiggerOrEqualValue(startMs) &
          t.tappedAt.isSmallerThanValue(endMs),
    )).getSingle();
    return count;
  }

  Future<void> migrateFromSharedPrefs(
      List<({int wordId, int epochDay})> legacy) async {
    final rows = legacy
        .map((e) => (
              wordId: e.wordId,
              tappedAt: e.epochDay * 86400000,
            ))
        .toList();
    if (rows.isNotEmpty) await insertTaps(rows);
  }
}
