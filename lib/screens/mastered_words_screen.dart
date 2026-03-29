import 'package:flutter/material.dart';
import '../models/word.dart';
import '../services/word_service.dart';
import 'package:chinese_reading_widget/main.dart'
    show pushTodaysWordsToWidget, effectiveDate, invalidateLaunchCache, NeonColors;

class MasteredWordsScreen extends StatefulWidget {
  const MasteredWordsScreen({super.key});

  @override
  State<MasteredWordsScreen> createState() => _MasteredWordsScreenState();
}

class _MasteredWordsScreenState extends State<MasteredWordsScreen> {
  List<Word> _masteredWords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allWords = await WordService.loadWordList();
    final masteredIds = await WordService.getRecognizedIds();
    final mastered = allWords
        .where((w) => masteredIds.contains(w.id))
        .toList()
      ..sort((a, b) => a.character.compareTo(b.character));
    if (mounted) {
      setState(() {
        _masteredWords = mastered;
        _loading = false;
      });
    }
  }

  Future<void> _unmaster(Word word) async {
    await WordService.unmarkRecognized(word.id);
    await WordService.addToUnmasterQueue(word.id);
    invalidateLaunchCache();
    await pushTodaysWordsToWidget(effectiveDate);
    setState(() => _masteredWords.removeWhere((w) => w.id == word.id));
  }

  Future<void> _confirmClearAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all mastered words?'),
        content: Text(
          'All ${_masteredWords.length} mastered word${_masteredWords.length == 1 ? '' : 's'} '
          'will return to the widget rotation.',
        ),
        actions: [
          GestureDetector(
            onTap: () => Navigator.of(ctx).pop(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: NeonColors.inkDim.withAlpha(20),
                border: Border.all(color: NeonColors.inkDim.withAlpha(80), width: 1.5),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: NeonColors.inkDim.withAlpha(20), blurRadius: 10, spreadRadius: 1),
                  BoxShadow(color: NeonColors.inkDim.withAlpha(10), blurRadius: 20, spreadRadius: 2),
                ],
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: NeonColors.inkDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(ctx).pop(true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: NeonColors.pink.withAlpha(20),
                border: Border.all(color: NeonColors.pink.withAlpha(80), width: 1.5),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(color: NeonColors.pink.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                  BoxShadow(color: NeonColors.pink.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                ],
              ),
              child: Text(
                'Clear All',
                style: TextStyle(
                  color: NeonColors.pink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await WordService.clearAllRecognized();
      invalidateLaunchCache();
      await pushTodaysWordsToWidget(effectiveDate);
      if (mounted) setState(() => _masteredWords.clear());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mastered Words',
          style: textTheme.titleMedium,
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          if (_masteredWords.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClearAll(context),
              child: Text(
                'Clear All',
                style: TextStyle(
                  color: isDark ? NeonColors.pink : colorScheme.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  shadows: isDark
                      ? [Shadow(color: NeonColors.pink.withAlpha(128), blurRadius: 8)]
                      : null,
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _masteredWords.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64,
                          color: isDark ? NeonColors.whiteDim : colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('No mastered words yet',
                          style: textTheme.bodyLarge?.copyWith(
                              color: isDark ? NeonColors.whiteDim : colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _masteredWords.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, i) {
                    final word = _masteredWords[i];
                    return ListTile(
                      leading: Text(
                        word.character,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isDark ? NeonColors.white : colorScheme.onSurface,
                        ),
                      ),
                      title: Text(word.pinyin,
                          style: textTheme.bodyMedium?.copyWith(
                            color: isDark ? NeonColors.cyan : null,
                          )),
                      subtitle: Text(
                        word.meaning,
                        style: textTheme.bodySmall?.copyWith(
                          color: isDark ? NeonColors.whiteDim : colorScheme.outline,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () => _unmaster(word),
                        child: Text(
                          'Unmaster',
                          style: TextStyle(
                            color: isDark ? NeonColors.orange : colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            shadows: isDark
                                ? [Shadow(color: NeonColors.orange.withAlpha(128), blurRadius: 8)]
                                : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
