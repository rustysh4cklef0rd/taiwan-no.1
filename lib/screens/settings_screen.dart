import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word.dart';
import '../services/word_service.dart';

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

  // Today's review
  List<({Word word, bool tapped})> _todaysReview = [];

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

      _todaysReview = results[1] as List<({Word word, bool tapped})>;
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
                          '200 characters',
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
            'The widget cycles through all 200 characters every $cycleDays days, then starts again.',
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
  });

  final List<({Word word, bool tapped})> review;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final tappedCount = review.where((r) => r.tapped).length;
    final missedCount = review.length - tappedCount;

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
              '$tappedCount / ${review.length} reviewed',
              style: textTheme.labelSmall?.copyWith(
                color: tappedCount == review.length
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
                ),
              ],
            ],
          ),
        ),
        if (missedCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '$missedCount word${missedCount == 1 ? '' : 's'} not reviewed yet — tap them in the widget to open.',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
        ],
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.entry,
    required this.colorScheme,
    required this.textTheme,
  });

  final ({Word word, bool tapped}) entry;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(
        entry.word.character,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: entry.tapped
              ? colorScheme.onSurface
              : colorScheme.onSurface.withAlpha(100),
        ),
      ),
      title: Text(
        entry.word.pinyin,
        style: textTheme.bodyMedium?.copyWith(
          color: entry.tapped ? colorScheme.onSurface : colorScheme.outline,
        ),
      ),
      subtitle: Text(
        entry.word.meaning,
        style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.tapped
          ? Icon(Icons.check_circle_outline,
              color: colorScheme.primary, size: 20)
          : Icon(Icons.radio_button_unchecked,
              color: colorScheme.outline, size: 20),
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
