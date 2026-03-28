import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word.dart';
import '../services/word_service.dart';
import 'package:chinese_reading_widget/main.dart'
    show pushTodaysWordsToWidget, simulatedDayOffset, saveDayOffset, effectiveDate, invalidateLaunchCache;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Progress
  int _dayOfCycle = 1;
  int _cycleDays = 34;
  double _percent = 0;

  // Streak
  int _streakCurrent = 0;
  int _streakLongest = 0;

  // Stats
  int _totalWordsSeen = 0;
  int _totalDaysStudied = 0;
  int _masteredCount = 0;

  // Heatmap
  Map<int, int> _heatmapData = {};
  int _todayEpochDay = 0;

  // Today's words
  List<({Word word, bool recognized})> _todaysReview = [];

  // Settings
  bool _darkMode = false;
  bool _quizMode = false;
  bool _hidePinyin = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final results = await Future.wait([
      WordService.getProgress(DateTime.now()),
      WordService.getTodaysReview(),
      WordService.getRecognizedCount(),
      WordService.getStreakData(),
      WordService.getTotalUniqueWordsSeen(),
      WordService.getTotalDaysStudied(),
      WordService.getHeatmapData(84),
    ]);

    if (!mounted) return;
    setState(() {
      final progress = results[0] as Map<String, dynamic>;
      _dayOfCycle = progress['dayOfCycle'] as int;
      _cycleDays = progress['cycleDays'] as int;
      _percent = progress['percent'] as double;

      _todaysReview = results[1] as List<({Word word, bool recognized})>;
      _masteredCount = results[2] as int;

      final streak = results[3] as ({int current, int longest, int lastDay});
      _streakCurrent = streak.current;
      _streakLongest = streak.longest;

      _totalWordsSeen = results[4] as int;
      _totalDaysStudied = results[5] as int;
      _heatmapData = results[6] as Map<int, int>;
      _todayEpochDay =
          DateTime.now().toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;

      _darkMode = prefs.getBool('dark_mode') ?? false;
      _quizMode = prefs.getBool('quiz_mode') ?? false;
      _hidePinyin = prefs.getBool('hide_pinyin') ?? false;
      _loading = false;
    });
  }

  Future<void> _toggleRecognized(Word word, bool currentlyRecognized) async {
    if (currentlyRecognized) {
      await WordService.unmarkRecognized(word.id);
    } else {
      await WordService.markRecognized(word.id);
      await WordService.replaceWordInToday(word.id);
    }
    invalidateLaunchCache();
    final results = await Future.wait([
      WordService.getTodaysReview(),
      WordService.getRecognizedCount(),
      WordService.getProgress(DateTime.now()),
      WordService.getTotalUniqueWordsSeen(),
    ]);
    if (!mounted) return;
    final progress = results[2] as Map<String, dynamic>;
    setState(() {
      _todaysReview = results[0] as List<({Word word, bool recognized})>;
      _masteredCount = results[1] as int;
      _dayOfCycle = progress['dayOfCycle'] as int;
      _cycleDays = progress['cycleDays'] as int;
      _percent = progress['percent'] as double;
      _totalWordsSeen = results[3] as int;
    });
  }

  Future<void> _confirmClearMastered(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear mastered words?'),
        content: Text(
          'All $_masteredCount mastered word${_masteredCount == 1 ? '' : 's'} '
          'will return to the widget rotation.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await WordService.clearAllRecognized();
      if (mounted) setState(() => _masteredCount = 0);
    }
  }

  Future<void> _toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    // Sync to widget prefs
    await HomeWidget.saveWidgetData<bool>('dark_mode', value);
    if (!mounted) return;
    setState(() => _darkMode = value);
    ThemeModeNotifier.of(context)?.toggle(value);
  }

  Future<void> _toggleQuizMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('quiz_mode', value);
    if (mounted) setState(() => _quizMode = value);
  }

  Future<void> _toggleHidePinyin(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_pinyin', value);
    // Sync to widget SharedPrefs so native providers can read it
    await HomeWidget.saveWidgetData<bool>('hide_pinyin', value);
    await HomeWidget.updateWidget(androidName: 'WordWidgetProvider4x2');
    await HomeWidget.updateWidget(androidName: 'WordWidgetProvider2x2');
    if (mounted) setState(() => _hidePinyin = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress & Settings'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Streak card ─────────────────────────────────────────
                _StreakCard(
                  current: _streakCurrent,
                  longest: _streakLongest,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
                const SizedBox(height: 24),

                // ── Stats row ───────────────────────────────────────────
                _StatsRow(
                  wordsSeen: _totalWordsSeen,
                  daysStudied: _totalDaysStudied,
                  longestStreak: _streakLongest,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
                const SizedBox(height: 24),

                // ── Heatmap ─────────────────────────────────────────────
                Text(
                  'ACTIVITY',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _HeatmapCard(
                  data: _heatmapData,
                  today: _todayEpochDay,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 32),

                // ── Word sets ────────────────────────────────────────────
                Text(
                  'WORD SETS',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _WordSetsCard(
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                  onUnlock: () => setState(() {}),
                ),
                const SizedBox(height: 32),

                // ── Progress card ────────────────────────────────────────
                _ProgressCard(
                  dayOfCycle: _dayOfCycle,
                  cycleDays: _cycleDays,
                  percent: _percent,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
                const SizedBox(height: 32),

                // ── Today's review ────────────────────────────────────────
                _TodaysReviewCard(
                  review: _todaysReview,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                  onToggle: _toggleRecognized,
                ),
                const SizedBox(height: 32),

                // ── Mastered words section ────────────────────────────────
                Text(
                  'MASTERED WORDS',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.check_circle_outline,
                            color: colorScheme.primary),
                        title: const Text('Words mastered'),
                        subtitle: const Text(
                            'These are skipped in the widget rotation'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _masteredCount > 0
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$_masteredCount',
                            style: textTheme.labelLarge?.copyWith(
                              color: _masteredCount > 0
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      if (_masteredCount > 0) ...[
                        const Divider(height: 1, indent: 56),
                        ListTile(
                          leading:
                              Icon(Icons.delete_outline, color: colorScheme.error),
                          title: Text('Clear mastered words',
                              style: TextStyle(color: colorScheme.error)),
                          subtitle: const Text(
                              'All mastered words return to widget rotation'),
                          onTap: () => _confirmClearMastered(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Learning settings ─────────────────────────────────────
                Text(
                  'LEARNING',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Quiz mode'),
                        subtitle: const Text(
                            'Hide meaning until you tap Reveal in detail view'),
                        secondary: Icon(Icons.quiz_outlined,
                            color: colorScheme.primary),
                        value: _quizMode,
                        onChanged: _toggleQuizMode,
                      ),
                      const Divider(height: 1, indent: 56),
                      SwitchListTile(
                        title: const Text('Hide pinyin in widget'),
                        subtitle: const Text(
                            'Test character recognition on your home screen'),
                        secondary: Icon(Icons.abc_outlined,
                            color: colorScheme.primary),
                        value: _hidePinyin,
                        onChanged: _toggleHidePinyin,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Display settings ─────────────────────────────────────
                Text(
                  'DISPLAY',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    title: const Text('Dark mode'),
                    subtitle: const Text('Switch widget and app to dark theme'),
                    secondary: Icon(
                      _darkMode
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: colorScheme.primary,
                    ),
                    value: _darkMode,
                    onChanged: _toggleDarkMode,
                  ),
                ),
                const SizedBox(height: 32),

                // ── About ─────────────────────────────────────────────────
                Text(
                  'ABOUT',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline,
                            color: colorScheme.primary),
                        title: const Text('Word list'),
                        trailing: Text(
                          '1,250 characters',
                          style: textTheme.bodySmall
                              ?.copyWith(color: colorScheme.outline),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.refresh_outlined,
                            color: colorScheme.primary),
                        title: const Text('Widget updates'),
                        trailing: Text(
                          'Daily + on app open',
                          style: textTheme.bodySmall
                              ?.copyWith(color: colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Day navigation (debug) ────────────────────────────────
                Text(
                  'DAY NAVIGATION',
                  style: textTheme.labelSmall?.copyWith(
                    color: colorScheme.error,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.arrow_back, size: 16),
                                label: const Text('Prev day'),
                                onPressed: () async {
                                  final nav = Navigator.of(context);
                                  await saveDayOffset(simulatedDayOffset - 1);
                                  await pushTodaysWordsToWidget(effectiveDate);
                                  if (!mounted) return;
                                  nav.pushNamedAndRemoveUntil(
                                      '/home', (_) => false);
                                },
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                simulatedDayOffset == 0
                                    ? 'Today'
                                    : 'Day ${simulatedDayOffset > 0 ? '+' : ''}$simulatedDayOffset',
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: simulatedDayOffset == 0
                                      ? colorScheme.outline
                                      : colorScheme.error,
                                ),
                              ),
                            ),
                            Expanded(
                              child: FilledButton.icon(
                                icon: const Icon(Icons.arrow_forward, size: 16),
                                label: const Text('Next day'),
                                onPressed: () async {
                                  final nav = Navigator.of(context);
                                  await saveDayOffset(simulatedDayOffset + 1);
                                  await pushTodaysWordsToWidget(effectiveDate);
                                  if (!mounted) return;
                                  nav.pushNamedAndRemoveUntil(
                                      '/home', (_) => false);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (simulatedDayOffset != 0) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading:
                              Icon(Icons.today_outlined, color: colorScheme.error),
                          title: const Text('Reset to today'),
                          onTap: () async {
                            final nav = Navigator.of(context);
                            await saveDayOffset(0);
                            await pushTodaysWordsToWidget(effectiveDate);
                            if (!mounted) return;
                            nav.pushNamedAndRemoveUntil(
                                '/home', (_) => false);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Streak card
// ─────────────────────────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({
    required this.current,
    required this.longest,
    required this.colorScheme,
    required this.textTheme,
  });

  final int current;
  final int longest;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: current > 0
            ? colorScheme.tertiaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Text(
            current > 0 ? '🔥' : '💤',
            style: const TextStyle(fontSize: 48),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current == 0
                      ? 'Start your streak today'
                      : '$current day streak',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: current > 0
                        ? colorScheme.onTertiaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                if (longest > 0)
                  Text(
                    'Best: $longest day${longest == 1 ? '' : 's'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: current > 0
                          ? colorScheme.onTertiaryContainer.withAlpha(180)
                          : colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.wordsSeen,
    required this.daysStudied,
    required this.longestStreak,
    required this.colorScheme,
    required this.textTheme,
  });

  final int wordsSeen;
  final int daysStudied;
  final int longestStreak;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatTile(
          value: '$wordsSeen',
          label: 'Words\nseen',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(width: 12),
        _StatTile(
          value: '$daysStudied',
          label: 'Days\nstudied',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
        const SizedBox(width: 12),
        _StatTile(
          value: '$longestStreak',
          label: 'Best\nstreak',
          colorScheme: colorScheme,
          textTheme: textTheme,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    required this.colorScheme,
    required this.textTheme,
  });

  final String value;
  final String label;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Heatmap card
// ─────────────────────────────────────────────────────────────────────────────

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({
    required this.data,
    required this.today,
    required this.colorScheme,
  });

  final Map<int, int> data;
  final int today;
  final ColorScheme colorScheme;

  Color _colorForCount(int count) {
    if (count == 0) return colorScheme.surfaceContainerHighest;
    if (count <= 2) return colorScheme.primary.withAlpha(80);
    if (count <= 4) return colorScheme.primary.withAlpha(150);
    return colorScheme.primary.withAlpha(230);
  }

  @override
  Widget build(BuildContext context) {
    // 84 days = 12 weeks. Display as columns of 7 (one column = one week).
    const totalDays = 84;
    const weeks = totalDays ~/ 7; // 12

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '12-week activity',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
                Text(
                  '${data.values.fold(0, (a, b) => a + b)} reviews',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.outline,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Grid: 12 columns (weeks) × 7 rows (days)
            SizedBox(
              height: 7 * 14.0,
              child: Row(
                children: List.generate(weeks, (weekIndex) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        children: List.generate(7, (dayIndex) {
                          // dayIndex 0 = Mon, 6 = Sun of that week
                          // weekIndex 0 = oldest week, 11 = current week
                          final daysAgo =
                              (weeks - 1 - weekIndex) * 7 + (6 - dayIndex);
                          final day = today - daysAgo;
                          final count = data[day] ?? 0;
                          final isToday = day == today;
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 1),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _colorForCount(count),
                                  borderRadius: BorderRadius.circular(2),
                                  border: isToday
                                      ? Border.all(
                                          color: colorScheme.primary,
                                          width: 1.5,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Less',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colorScheme.outline, fontSize: 10)),
                const SizedBox(width: 4),
                for (final alpha in [0, 80, 150, 230])
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: alpha == 0
                          ? colorScheme.surfaceContainerHighest
                          : colorScheme.primary.withAlpha(alpha),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                const SizedBox(width: 4),
                Text('More',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: colorScheme.outline, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Progress card
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.dayOfCycle,
    required this.cycleDays,
    required this.percent,
    required this.colorScheme,
    required this.textTheme,
  });

  final int dayOfCycle;
  final int cycleDays;
  final double percent;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day $dayOfCycle of $cycleDays',
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "You're ${percent.toStringAsFixed(0)}% through the word list cycle",
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onPrimaryContainer.withAlpha(200),
            ),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 10,
              backgroundColor:
                  colorScheme.onPrimaryContainer.withAlpha(40),
              valueColor: AlwaysStoppedAnimation<Color>(
                colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'The widget cycles through all 1,250 characters every $cycleDays days, then starts again.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimaryContainer.withAlpha(160),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Today's review card
// ─────────────────────────────────────────────────────────────────────────────

class _TodaysReviewCard extends StatelessWidget {
  const _TodaysReviewCard({
    required this.review,
    required this.colorScheme,
    required this.textTheme,
    required this.onToggle,
  });

  final List<({Word word, bool recognized})> review;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final void Function(Word word, bool currentlyRecognized) onToggle;

  @override
  Widget build(BuildContext context) {
    final knownCount = review.where((r) => r.recognized).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              "TODAY'S WORDS",
              style: textTheme.labelSmall?.copyWith(
                color: colorScheme.outline,
                letterSpacing: 1.4,
              ),
            ),
            const Spacer(),
            Text(
              '$knownCount / ${review.length} known',
              style: textTheme.labelSmall?.copyWith(
                color: knownCount == review.length
                    ? colorScheme.primary
                    : colorScheme.outline,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < review.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                _ReviewRow(
                  entry: review[i],
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                  onToggle: onToggle,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.entry,
    required this.colorScheme,
    required this.textTheme,
    required this.onToggle,
  });

  final ({Word word, bool recognized}) entry;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final void Function(Word word, bool currentlyRecognized) onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => onToggle(entry.word, entry.recognized),
      leading: Text(
        entry.word.character,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: entry.recognized
              ? colorScheme.onSurface
              : colorScheme.onSurface.withAlpha(100),
        ),
      ),
      title: Text(
        entry.word.pinyin,
        style: textTheme.bodyMedium?.copyWith(
          color: entry.recognized ? colorScheme.onSurface : colorScheme.outline,
        ),
      ),
      subtitle: Text(
        entry.word.meaning,
        style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.recognized
          ? Icon(Icons.check_circle_outline,
              color: colorScheme.primary, size: 20)
          : Icon(Icons.radio_button_unchecked,
              color: colorScheme.outline, size: 20),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Word sets card
// ─────────────────────────────────────────────────────────────────────────────

class _WordSetsCard extends StatelessWidget {
  const _WordSetsCard({
    required this.colorScheme,
    required this.textTheme,
    required this.onUnlock,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onUnlock;

  static const _setLabels = [
    'Set 1 — Characters 1–312',
    'Set 2 — Characters 313–625',
    'Set 3 — Characters 626–937',
    'Set 4 — Characters 938–1250',
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_WordSetsData>(
      future: _loadData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snapshot.data!;
        return Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < 4; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16),
                _SetRow(
                  setNum: i + 1,
                  label: _setLabels[i],
                  stats: data.stats[i],
                  isLocked: (i + 1) > data.activeSet,
                  canUnlock: (i + 1) == data.activeSet + 1 && data.canUnlock,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                  onUnlock: () async {
                    await WordService.setActiveSet(i + 1);
                    await pushTodaysWordsToWidget(effectiveDate);
                    onUnlock();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static Future<_WordSetsData> _loadData() async {
    final results = await Future.wait([
      WordService.getActiveSet(),
      WordService.canUnlockNextSet(),
      WordService.getSetStats(1),
      WordService.getSetStats(2),
      WordService.getSetStats(3),
      WordService.getSetStats(4),
    ]);
    return _WordSetsData(
      activeSet: results[0] as int,
      canUnlock: results[1] as bool,
      stats: [
        results[2] as ({int total, int recognized, double percentDone}),
        results[3] as ({int total, int recognized, double percentDone}),
        results[4] as ({int total, int recognized, double percentDone}),
        results[5] as ({int total, int recognized, double percentDone}),
      ],
    );
  }
}

class _WordSetsData {
  const _WordSetsData({
    required this.activeSet,
    required this.canUnlock,
    required this.stats,
  });
  final int activeSet;
  final bool canUnlock;
  final List<({int total, int recognized, double percentDone})> stats;
}

class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.setNum,
    required this.label,
    required this.stats,
    required this.isLocked,
    required this.canUnlock,
    required this.colorScheme,
    required this.textTheme,
    required this.onUnlock,
  });

  final int setNum;
  final String label;
  final ({int total, int recognized, double percentDone}) stats;
  final bool isLocked;
  final bool canUnlock;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final bool complete = stats.percentDone >= 0.8;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isLocked
                        ? colorScheme.onSurface.withAlpha(100)
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              if (isLocked)
                Icon(Icons.lock_outline,
                    size: 18, color: colorScheme.outline)
              else if (complete)
                Icon(Icons.check_circle_outline,
                    size: 18, color: colorScheme.primary),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.percentDone,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                isLocked ? colorScheme.outline : colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${stats.recognized} / ${stats.total} mastered',
                style: textTheme.bodySmall?.copyWith(
                  color: isLocked
                      ? colorScheme.outline.withAlpha(140)
                      : colorScheme.outline,
                ),
              ),
              const Spacer(),
              if (canUnlock)
                FilledButton.tonal(
                  onPressed: onUnlock,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Unlock Set $setNum',
                      style: textTheme.labelSmall),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Theme mode notifier
// ─────────────────────────────────────────────────────────────────────────────

class ThemeModeNotifier extends InheritedWidget {
  const ThemeModeNotifier({
    super.key,
    required this.toggle,
    required super.child,
  });

  final void Function(bool isDark) toggle;

  static ThemeModeNotifier? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ThemeModeNotifier>();
  }

  @override
  bool updateShouldNotify(ThemeModeNotifier oldWidget) => false;
}
