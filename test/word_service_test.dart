import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:chinese_reading_widget/models/word.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Minimal word JSON fixture.
Map<String, dynamic> _wordFixture({
  int id = 1,
  String character = '好',
  String pinyin = 'hǎo',
  String meaning = 'good',
  String phrase = '你好',
  String phrasePinyin = 'nǐ hǎo',
  String phraseMeaning = 'hello',
  int frequencyRank = 15,
}) {
  return {
    'id': id,
    'character': character,
    'pinyin': pinyin,
    'meaning': meaning,
    'phrase': phrase,
    'phrase_pinyin': phrasePinyin,
    'phrase_meaning': phraseMeaning,
    'frequency_rank': frequencyRank,
  };
}

/// Build a list of [count] synthetic words.
List<Map<String, dynamic>> _buildWordList(int count) {
  return List.generate(
    count,
    (i) => _wordFixture(
      id: i + 1,
      character: '字$i',
      pinyin: 'p$i',
      frequencyRank: i + 1,
    ),
  );
}

/// Pure implementation of the epoch-day formula (mirrors WordService).
List<int> _getTodaysIndices(DateTime date, int totalWords) {
  final int epochDay =
      date.toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;
  final int startIndex = (epochDay * 6) % totalWords;
  return List.generate(6, (i) => (startIndex + i) % totalWords);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ── Word.fromJson ────────────────────────────────────────────────────────
  group('Word.fromJson', () {
    test('parses all fields correctly', () {
      final json = _wordFixture(
        id: 42,
        character: '大',
        pinyin: 'dà',
        meaning: 'big',
        phrase: '大學',
        phrasePinyin: 'dà xué',
        phraseMeaning: 'university',
        frequencyRank: 13,
      );

      final word = Word.fromJson(json);

      expect(word.id, 42);
      expect(word.character, '大');
      expect(word.pinyin, 'dà');
      expect(word.meaning, 'big');
      expect(word.phrase, '大學');
      expect(word.phrasePinyin, 'dà xué');
      expect(word.phraseMeaning, 'university');
      expect(word.frequencyRank, 13);
    });

    test('round-trips through toJson → fromJson', () {
      final original = Word.fromJson(_wordFixture());
      final roundTripped = Word.fromJson(original.toJson());

      expect(roundTripped.id, original.id);
      expect(roundTripped.character, original.character);
      expect(roundTripped.pinyin, original.pinyin);
      expect(roundTripped.meaning, original.meaning);
      expect(roundTripped.phrase, original.phrase);
      expect(roundTripped.phrasePinyin, original.phrasePinyin);
      expect(roundTripped.phraseMeaning, original.phraseMeaning);
      expect(roundTripped.frequencyRank, original.frequencyRank);
    });

    test('round-trips through JSON string encoding', () {
      final original = Word.fromJson(_wordFixture(character: '中'));
      final encoded = jsonEncode(original.toJson());
      final decoded = Word.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded.character, '中');
    });
  });

  // ── Word.toPrefsMap / fromPrefsMap ───────────────────────────────────────
  group('Word prefs map', () {
    test('toPrefsMap stores all expected keys for slot 0', () {
      final word = Word.fromJson(_wordFixture(id: 5));
      final map = word.toPrefsMap(0);

      expect(map.containsKey('word_0_char'), isTrue);
      expect(map.containsKey('word_0_pinyin'), isTrue);
      expect(map.containsKey('word_0_meaning'), isTrue);
      expect(map.containsKey('word_0_phrase'), isTrue);
      expect(map.containsKey('word_0_phrase_pinyin'), isTrue);
      expect(map.containsKey('word_0_phrase_meaning'), isTrue);
      expect(map.containsKey('word_0_id'), isTrue);
      expect(map['word_0_id'], '5');
    });

    test('fromPrefsMap reconstructs the word', () {
      final original = Word.fromJson(_wordFixture(id: 7, character: '天'));
      final prefsMap = original.toPrefsMap(3);
      final recovered = Word.fromPrefsMap(prefsMap, 3);

      expect(recovered.id, 7);
      expect(recovered.character, '天');
      expect(recovered.pinyin, original.pinyin);
    });
  });

  // ── Epoch-day formula (getTodaysWords logic) ─────────────────────────────
  group('epoch-day word rotation', () {
    test('always returns exactly 6 indices', () {
      final date = DateTime(2024, 1, 1);
      final indices = _getTodaysIndices(date, 200);
      expect(indices.length, 6);
    });

    test('indices are deterministic for the same date', () {
      final date = DateTime(2025, 6, 15);
      final a = _getTodaysIndices(date, 200);
      final b = _getTodaysIndices(date, 200);
      expect(a, b);
    });

    test('consecutive days yield different starting indices', () {
      final day1 = DateTime(2024, 3, 1);
      final day2 = DateTime(2024, 3, 2);
      final i1 = _getTodaysIndices(day1, 200).first;
      final i2 = _getTodaysIndices(day2, 200).first;
      // startIndex advances by 6 each day (mod 200), so they must differ.
      expect(i1, isNot(i2));
    });

    test('all indices are within [0, totalWords)', () {
      final date = DateTime(2026, 1, 1);
      const total = 200;
      final indices = _getTodaysIndices(date, total);
      for (final idx in indices) {
        expect(idx, greaterThanOrEqualTo(0));
        expect(idx, lessThan(total));
      }
    });

    test('wrap-around: indices stay in bounds even when startIndex is near end',
        () {
      // Force a date where startIndex would be 198 or 199.
      // With 200 words and step 6, startIndex = (epochDay * 6) % 200.
      // We want startIndex = 198 → epochDay * 6 ≡ 198 (mod 200)
      //   e.g. epochDay = 33 → 33 * 6 = 198.
      final epoch = DateTime.utc(1970, 1, 1);
      final testDate = epoch.add(const Duration(days: 33));
      final indices = _getTodaysIndices(testDate, 200);

      expect(indices.first, 198);
      // indices should wrap: 198, 199, 0, 1, 2, 3
      expect(indices, [198, 199, 0, 1, 2, 3]);
    });

    test('full cycle: after cycleDays days the rotation repeats', () {
      // With 200 words: gcd(200, 6) = 2, so the cycle length is
      // 200 / gcd(200,6) = 100 days.  After 100 days the start index repeats.
      const total = 200;
      final base = DateTime(2024, 1, 1);
      final later = base.add(const Duration(days: 100));

      final indicesBase  = _getTodaysIndices(base, total);
      final indicesLater = _getTodaysIndices(later, total);
      expect(indicesBase, indicesLater);
    });

    test('works correctly with small word lists (edge case)', () {
      // 6 words total — every day shows all 6 (startIndex always 0).
      final date = DateTime(2025, 1, 1);
      final indices = _getTodaysIndices(date, 6);
      expect(indices.toSet().length, 6); // all distinct
      for (final idx in indices) {
        expect(idx, inInclusiveRange(0, 5));
      }
    });
  });

  // ── Word list parsing from raw JSON ──────────────────────────────────────
  group('word list JSON parsing', () {
    test('parses a list of words from a JSON array string', () {
      final jsonArray = jsonEncode(_buildWordList(10));
      final parsed = (jsonDecode(jsonArray) as List<dynamic>)
          .map((e) => Word.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(parsed.length, 10);
      expect(parsed.first.id, 1);
      expect(parsed.last.id, 10);
    });

    test('all 200 fixture words parse without error', () {
      final raw = _buildWordList(200);
      expect(
        () => raw.map(Word.fromJson).toList(),
        returnsNormally,
      );
    });
  });
}
