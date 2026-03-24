class Word {
  final int id;
  final String character;
  final String pinyin;
  final String meaning;
  final String phrase;
  final String phrasePinyin;
  final String phraseMeaning;
  final int frequencyRank;

  const Word({
    required this.id,
    required this.character,
    required this.pinyin,
    required this.meaning,
    required this.phrase,
    required this.phrasePinyin,
    required this.phraseMeaning,
    required this.frequencyRank,
  });

  factory Word.fromJson(Map<String, dynamic> json) {
    return Word(
      id: json['id'] as int,
      character: json['character'] as String,
      pinyin: json['pinyin'] as String,
      meaning: json['meaning'] as String,
      phrase: json['phrase'] as String,
      phrasePinyin: json['phrase_pinyin'] as String,
      phraseMeaning: json['phrase_meaning'] as String,
      frequencyRank: json['frequency_rank'] as int,
    );
  }

  Map<String, dynamic> toJson() {
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

  /// Serialize to a simple map of string keys → string values for SharedPreferences.
  Map<String, String> toPrefsMap(int slot) {
    return {
      'word_${slot}_char': character,
      'word_${slot}_pinyin': pinyin,
      'word_${slot}_meaning': meaning,
      'word_${slot}_phrase': phrase,
      'word_${slot}_phrase_pinyin': phrasePinyin,
      'word_${slot}_phrase_meaning': phraseMeaning,
      'word_${slot}_id': id.toString(),
    };
  }

  static Word fromPrefsMap(Map<String, String> prefs, int slot) {
    return Word(
      id: int.tryParse(prefs['word_${slot}_id'] ?? '0') ?? 0,
      character: prefs['word_${slot}_char'] ?? '',
      pinyin: prefs['word_${slot}_pinyin'] ?? '',
      meaning: prefs['word_${slot}_meaning'] ?? '',
      phrase: prefs['word_${slot}_phrase'] ?? '',
      phrasePinyin: prefs['word_${slot}_phrase_pinyin'] ?? '',
      phraseMeaning: prefs['word_${slot}_phrase_meaning'] ?? '',
      frequencyRank: 0,
    );
  }

  @override
  String toString() => 'Word($character, $pinyin)';
}
