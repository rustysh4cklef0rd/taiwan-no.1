import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word.dart';
import '../providers/app_providers.dart';
import '../services/word_service.dart';
import 'mastered_words_screen.dart';
import 'package:chinese_reading_widget/main.dart'
    show pushTodaysWordsToWidget, simulatedDayOffset, saveDayOffset, effectiveDate, invalidateLaunchCache, NeonColors;

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    super.key,
    this.embedded = false,
    this.onDayChanged,
  });

  final bool embedded;
  final VoidCallback? onDayChanged;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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
  bool _darkMode = true; // mirrors app default (dark on first launch)
  bool _widgetDarkMode = false; // widget defaults to light
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
      // Use UTC epoch day to match TapRepository.epochDay() key format
      _todayEpochDay =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;

      _darkMode = prefs.getBool('dark_mode') ?? true; // dark by default on first launch
      _widgetDarkMode = prefs.getBool('widget_dark_mode') ?? false;
      _quizMode = prefs.getBool('quiz_mode') ?? false;
      _hidePinyin = prefs.getBool('hide_pinyin') ?? false;
      _loading = false;
    });
  }

  Future<void> _toggleRecognized(Word word, bool currentlyRecognized) async {
    if (currentlyRecognized) {
      await WordService.unmarkRecognized(word.id);
    } else {
      ref.read(tapProvider.notifier).optimisticRecordTap(word.id);
      await WordService.markRecognized(word.id);
      await WordService.replaceWordInToday(word.id);
    }
    invalidateLaunchCache();
    // Refresh home page cards and widget
    widget.onDayChanged?.call();
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


  Future<void> _toggleWidgetDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('widget_dark_mode', value);
    await HomeWidget.saveWidgetData<bool>('widget_dark_mode', value);
    await HomeWidget.updateWidget(
      androidName: 'WordWidgetProvider4x2',
    );
    await HomeWidget.updateWidget(
      androidName: 'WordWidgetProvider2x2',
    );
    await HomeWidget.updateWidget(
      androidName: 'FlashcardWidgetProvider',
    );
    await HomeWidget.updateWidget(
      androidName: 'FlashcardWidget2x2Provider',
    );
    setState(() => _widgetDarkMode = value);
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

  /// Returns either a glass-styled Container (dark) or a regular Card (light).
  Widget _glassCard(BuildContext context, {required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (isDark) {
      return Container(
        decoration: BoxDecoration(
          color: NeonColors.glassBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NeonColors.glassBorder),
        ),
        child: child,
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: child,
    );
  }

  Widget _sectionLabel(BuildContext context, String text, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(
          text,
          style: textTheme.labelSmall?.copyWith(
            color: isError
                ? colorScheme.error
                : colorScheme.outline,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [Colors.white.withAlpha(20), Colors.transparent]
                    : [colorScheme.outlineVariant, Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Always watch unconditionally so subscription is never dropped
    final tapState = ref.watch(tapProvider);
    final todayEpochDay =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Progress'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: !widget.embedded,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // ── Streak card ─────────────────────────────────────────
                _StreakCard(
                  current: tapState.valueOrNull?.streakCurrent ?? _streakCurrent,
                  longest: tapState.valueOrNull?.streakLongest ?? _streakLongest,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
                const SizedBox(height: 24),

                // ── Stats row ───────────────────────────────────────────
                _StatsRow(
                  wordsSeen: _totalWordsSeen,
                  daysStudied: _totalDaysStudied,
                  longestStreak: tapState.valueOrNull?.streakLongest ?? _streakLongest,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
                const SizedBox(height: 24),

                // ── Heatmap ─────────────────────────────────────────────
                _sectionLabel(context, 'ACTIVITY'),
                const SizedBox(height: 8),
                _HeatmapCard(
                  data: tapState.valueOrNull?.heatmapData ?? _heatmapData,
                  today: todayEpochDay,
                  colorScheme: colorScheme,
                ),
                const SizedBox(height: 32),

                // ── Word sets ────────────────────────────────────────────
                _sectionLabel(context, 'WORD SETS'),
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
                _sectionLabel(context, 'MASTERED WORDS'),
                const SizedBox(height: 8),
                _glassCard(
                  context,
                  child: Column(
                    children: [
                      ListTile(
                        onTap: _masteredCount > 0
                            ? () => Navigator.of(context)
                                .push(MaterialPageRoute(
                                  builder: (_) => const MasteredWordsScreen(),
                                ))
                                .then((_) => _loadData())
                            : null,
                        leading: Icon(Icons.check_circle_outline,
                            color: isDark ? NeonColors.cyan : colorScheme.primary),
                        title: Text(
                          'Words mastered',
                          style: TextStyle(
                            color: isDark ? NeonColors.white : null,
                          ),
                        ),
                        subtitle: Text(
                          'These are skipped in the widget rotation',
                          style: TextStyle(
                            color: isDark ? NeonColors.whiteDim : null,
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: _masteredCount > 0
                                ? (isDark
                                    ? NeonColors.glassBg
                                    : colorScheme.primaryContainer)
                                : (isDark
                                    ? NeonColors.glassBg
                                    : colorScheme.surfaceContainerHighest),
                            borderRadius: BorderRadius.circular(12),
                            border: isDark
                                ? Border.all(color: NeonColors.glassBorder)
                                : null,
                          ),
                          child: Text(
                            '$_masteredCount',
                            style: textTheme.labelLarge?.copyWith(
                              color: _masteredCount > 0
                                  ? (isDark
                                      ? NeonColors.cyan
                                      : colorScheme.onPrimaryContainer)
                                  : (isDark
                                      ? NeonColors.whiteDim
                                      : colorScheme.onSurfaceVariant),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      // "Clear all" moved to Mastered Words screen
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Learning settings ─────────────────────────────────────
                _sectionLabel(context, 'LEARNING'),
                const SizedBox(height: 8),
                _glassCard(
                  context,
                  child: Column(
                    children: [
                      _NeonSwitchListTile(
                        title: Text(
                          'Quiz mode',
                          style: TextStyle(
                            color: isDark ? NeonColors.white : null,
                          ),
                        ),
                        subtitle: Text(
                          'Hide meaning until you tap Reveal in detail view',
                          style: TextStyle(
                            color: isDark ? NeonColors.whiteDim : null,
                          ),
                        ),
                        secondary: Icon(Icons.quiz_outlined,
                            color: isDark ? NeonColors.cyan : colorScheme.primary),
                        value: _quizMode,
                        onChanged: _toggleQuizMode,
                      ),
                      const Divider(height: 1, indent: 56),
                      _NeonSwitchListTile(
                        title: Text(
                          'Hide pinyin in widget',
                          style: TextStyle(
                            color: isDark ? NeonColors.white : null,
                          ),
                        ),
                        subtitle: Text(
                          'Test character recognition on your home screen',
                          style: TextStyle(
                            color: isDark ? NeonColors.whiteDim : null,
                          ),
                        ),
                        secondary: Icon(Icons.abc_outlined,
                            color: isDark ? NeonColors.cyan : colorScheme.primary),
                        value: _hidePinyin,
                        onChanged: _toggleHidePinyin,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Display settings ─────────────────────────────────────
                _sectionLabel(context, 'DISPLAY'),
                const SizedBox(height: 8),
                _glassCard(
                  context,
                  child: _NeonSwitchListTile(
                    title: Text(
                      'Dark mode',
                      style: TextStyle(
                        color: isDark ? NeonColors.white : null,
                      ),
                    ),
                    subtitle: Text(
                      'Switch app to dark theme',
                      style: TextStyle(
                        color: isDark ? NeonColors.whiteDim : null,
                      ),
                    ),
                    secondary: Icon(
                      _darkMode
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      color: isDark ? NeonColors.cyan : colorScheme.primary,
                    ),
                    value: _darkMode,
                    onChanged: _toggleDarkMode,
                  ),
                ),
                const SizedBox(height: 8),
                _glassCard(
                  context,
                  child: _NeonSwitchListTile(
                    title: Text(
                      'Widget dark mode',
                      style: TextStyle(
                        color: isDark ? NeonColors.white : null,
                      ),
                    ),
                    subtitle: Text(
                      'Switch home screen widget to dark theme',
                      style: TextStyle(
                        color: isDark ? NeonColors.whiteDim : null,
                      ),
                    ),
                    secondary: Icon(
                      _widgetDarkMode
                          ? Icons.widgets
                          : Icons.widgets_outlined,
                      color: isDark ? NeonColors.cyan : colorScheme.primary,
                    ),
                    value: _widgetDarkMode,
                    onChanged: _toggleWidgetDarkMode,
                  ),
                ),
                const SizedBox(height: 32),

                // ── About ─────────────────────────────────────────────────
                _sectionLabel(context, 'ABOUT'),
                const SizedBox(height: 8),
                _glassCard(
                  context,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline,
                            color: isDark ? NeonColors.cyan : colorScheme.primary),
                        title: Text(
                          'Word list',
                          style: TextStyle(
                            color: isDark ? NeonColors.white : null,
                          ),
                        ),
                        trailing: Text(
                          '1,250 characters',
                          style: textTheme.bodySmall?.copyWith(
                            color: isDark ? NeonColors.whiteDim : colorScheme.outline,
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: Icon(Icons.refresh_outlined,
                            color: isDark ? NeonColors.cyan : colorScheme.primary),
                        title: Text(
                          'Widget updates',
                          style: TextStyle(
                            color: isDark ? NeonColors.white : null,
                          ),
                        ),
                        trailing: Text(
                          'Daily + on app open',
                          style: textTheme.bodySmall?.copyWith(
                            color: isDark ? NeonColors.whiteDim : colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Day navigation (debug) ────────────────────────────────
                _sectionLabel(context, 'DAY NAVIGATION'),
                const SizedBox(height: 8),
                _glassCard(
                  context,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  await saveDayOffset(simulatedDayOffset - 1);
                                  await pushTodaysWordsToWidget(effectiveDate);
                                  if (!mounted) return;
                                  if (widget.embedded) {
                                    widget.onDayChanged?.call();
                                    _loadData();
                                  } else {
                                    Navigator.of(context)
                                        .pushNamedAndRemoveUntil(
                                            '/home', (_) => false);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(
                                      color: isDark ? NeonColors.cyan : NeonColors.cyanDay,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (isDark ? NeonColors.cyan : NeonColors.cyanDay).withAlpha(71),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                      BoxShadow(
                                        color: (isDark ? NeonColors.cyan : NeonColors.cyanDay).withAlpha(41),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.arrow_back, size: 14, color: isDark ? NeonColors.cyan : NeonColors.cyanDay),
                                      const SizedBox(width: 6),
                                      Text('Prev day', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? NeonColors.cyan : NeonColors.cyanDay)),
                                    ],
                                  ),
                                ),
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
                                      ? (isDark ? NeonColors.whiteDim : colorScheme.outline)
                                      : colorScheme.error,
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  await saveDayOffset(simulatedDayOffset + 1);
                                  await pushTodaysWordsToWidget(effectiveDate);
                                  if (!mounted) return;
                                  if (widget.embedded) {
                                    widget.onDayChanged?.call();
                                    _loadData();
                                  } else {
                                    Navigator.of(context)
                                        .pushNamedAndRemoveUntil(
                                            '/home', (_) => false);
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(
                                      color: NeonColors.pink,
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: NeonColors.pink.withAlpha(71),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                      BoxShadow(
                                        color: NeonColors.pink.withAlpha(41),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Next day', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: NeonColors.pink)),
                                      const SizedBox(width: 6),
                                      Icon(Icons.arrow_forward, size: 14, color: NeonColors.pink),
                                    ],
                                  ),
                                ),
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
                          title: Text(
                            'Reset to today',
                            style: TextStyle(
                              color: isDark ? NeonColors.white : null,
                            ),
                          ),
                          onTap: () async {
                            await saveDayOffset(0);
                            await pushTodaysWordsToWidget(effectiveDate);
                            if (!mounted) return;
                            if (widget.embedded) {
                              widget.onDayChanged?.call();
                              _loadData();
                            } else {
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                  '/home', (_) => false);
                            }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isDark
            ? NeonColors.glassBg
            : (current > 0
                ? colorScheme.tertiaryContainer
                : colorScheme.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: NeonColors.glassBorder) : null,
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
                      : '$current',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? NeonColors.orange
                        : (current > 0
                            ? colorScheme.onTertiaryContainer
                            : colorScheme.onSurfaceVariant),
                    shadows: isDark && current > 0
                        ? [Shadow(color: NeonColors.orange, blurRadius: 10)]
                        : null,
                  ),
                ),
                if (current > 0)
                  Text(
                    'day streak',
                    style: textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? NeonColors.whiteDim
                          : colorScheme.onTertiaryContainer,
                    ),
                  ),
                if (longest > 0)
                  Text(
                    'Best: $longest day${longest == 1 ? '' : 's'}',
                    style: textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? NeonColors.whiteDim
                          : (current > 0
                              ? colorScheme.onTertiaryContainer.withAlpha(180)
                              : colorScheme.outline),
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
          neonColor: NeonColors.pink,
        ),
        const SizedBox(width: 12),
        _StatTile(
          value: '$daysStudied',
          label: 'Days\nstudied',
          colorScheme: colorScheme,
          textTheme: textTheme,
          neonColor: NeonColors.cyan,
        ),
        const SizedBox(width: 12),
        _StatTile(
          value: '$longestStreak',
          label: 'Best\nstreak',
          colorScheme: colorScheme,
          textTheme: textTheme,
          neonColor: NeonColors.orange,
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
    this.neonColor,
  });

  final String value;
  final String label;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final Color? neonColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? NeonColors.glassBg : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: isDark ? Border.all(color: NeonColors.glassBorder) : null,
        ),
        child: Column(
          children: [
            Text(
              value,
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isDark && neonColor != null
                    ? neonColor
                    : colorScheme.onSurface,
                shadows: isDark && neonColor != null
                    ? [Shadow(color: neonColor!, blurRadius: 10)]
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.labelSmall?.copyWith(
                color: isDark ? NeonColors.whiteDim : colorScheme.outline,
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

  Color _colorForCount(int count, bool isDark) {
    if (isDark) {
      if (count == 0) return Colors.white.withAlpha(15);      // h0
      if (count <= 2) return NeonColors.cyan.withAlpha(51);   // h1 — cyan 20%
      if (count <= 4) return NeonColors.cyan.withAlpha(102);  // h2 — cyan 40%
      if (count <= 5) return NeonColors.cyan.withAlpha(166);  // h3 — cyan 65%
      if (count <= 7) return NeonColors.pink.withAlpha(179);  // h4 — pink 70%
      return NeonColors.pink;                                  // h5 — full pink
    }
    if (count == 0) return colorScheme.surfaceContainerHighest;
    if (count <= 2) return colorScheme.primary.withAlpha(80);
    if (count <= 4) return colorScheme.primary.withAlpha(150);
    if (count <= 6) return colorScheme.primary.withAlpha(200);
    return colorScheme.primary.withAlpha(230);
  }

  List<BoxShadow>? _shadowForCount(int count, bool isDark) {
    if (!isDark || count == 0) return null;
    if (count > 7) {
      return [
        BoxShadow(color: NeonColors.pink.withAlpha(153), blurRadius: 12),
        BoxShadow(color: NeonColors.pink.withAlpha(102), blurRadius: 20),
      ];
    }
    if (count > 5) {
      return [BoxShadow(color: NeonColors.pink.withAlpha(102), blurRadius: 10)];
    }
    return [BoxShadow(color: NeonColors.cyan.withAlpha(51), blurRadius: 4 + (count * 0.5).toDouble())];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 84 days = 12 weeks. Display as columns of 7 (one column = one week).
    const totalDays = 84;
    const weeks = totalDays ~/ 7; // 12

    final cardChild = Padding(
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
                      color: isDark ? NeonColors.whiteDim : colorScheme.outline,
                    ),
              ),
              Text(
                '${data.values.fold(0, (a, b) => a + b)} reviews',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark ? NeonColors.whiteDim : colorScheme.outline,
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
                                color: _colorForCount(count, isDark),
                                borderRadius: BorderRadius.circular(2),
                                border: isToday
                                    ? Border.all(
                                        color: isDark
                                            ? NeonColors.pink
                                            : colorScheme.primary,
                                        width: 1.5,
                                      )
                                    : null,
                                boxShadow: isToday && isDark
                                    ? [
                                        BoxShadow(
                                          color: NeonColors.pink,
                                          blurRadius: 14,
                                        )
                                      ]
                                    : _shadowForCount(count, isDark),
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
                      ?.copyWith(
                          color: isDark ? NeonColors.whiteDim : colorScheme.outline,
                          fontSize: 10)),
              const SizedBox(width: 4),
              if (isDark) ...[
                for (final alpha in [15, 51, 102, 166, 179, 255])
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: alpha == 15
                          ? Colors.white.withAlpha(15)
                          : (alpha >= 179
                              ? NeonColors.pink.withAlpha(alpha)
                              : NeonColors.cyan.withAlpha(alpha)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ] else ...[
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
              ],
              const SizedBox(width: 4),
              Text('More',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(
                          color: isDark ? NeonColors.whiteDim : colorScheme.outline,
                          fontSize: 10)),
            ],
          ),
        ],
      ),
    );

    if (isDark) {
      return Container(
        decoration: BoxDecoration(
          color: NeonColors.glassBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NeonColors.glassBorder),
        ),
        child: cardChild,
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: cardChild,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? NeonColors.glassBg : colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
        border: isDark ? Border.all(color: NeonColors.glassBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day $dayOfCycle of $cycleDays',
            style: textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? NeonColors.cyan : colorScheme.onPrimaryContainer,
              shadows: isDark
                  ? [Shadow(color: NeonColors.cyan, blurRadius: 10)]
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "You're ${percent.toStringAsFixed(0)}% through the word list cycle",
            style: textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? NeonColors.white
                  : colorScheme.onPrimaryContainer.withAlpha(200),
            ),
          ),
          const SizedBox(height: 20),
          if (isDark) ...[
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: percent / 100,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0x80FF2E63), NeonColors.pink],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(color: NeonColors.pink.withAlpha(153), blurRadius: 8),
                      BoxShadow(color: NeonColors.pink.withAlpha(77), blurRadius: 16),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
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
          ],
          const SizedBox(height: 12),
          Text(
            'The widget cycles through all 1,250 characters every $cycleDays days, then starts again.',
            style: textTheme.bodySmall?.copyWith(
              color: isDark
                  ? NeonColors.whiteDim
                  : colorScheme.onPrimaryContainer.withAlpha(160),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [Colors.white.withAlpha(20), Colors.transparent]
                        : [colorScheme.outlineVariant, Colors.transparent],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$knownCount / ${review.length} known',
              style: textTheme.labelSmall?.copyWith(
                color: knownCount == review.length
                    ? (isDark ? NeonColors.cyan : colorScheme.primary)
                    : (isDark ? NeonColors.whiteDim : colorScheme.outline),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isDark)
          Container(
            decoration: BoxDecoration(
              color: NeonColors.glassBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NeonColors.glassBorder),
            ),
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
          )
        else
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      onTap: () => onToggle(entry.word, entry.recognized),
      leading: Text(
        entry.word.character,
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: isDark
              ? (entry.recognized ? NeonColors.white : NeonColors.whiteDim)
              : (entry.recognized
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withAlpha(100)),
        ),
      ),
      title: Text(
        entry.word.pinyin,
        style: textTheme.bodyMedium?.copyWith(
          color: isDark
              ? (entry.recognized ? NeonColors.white : NeonColors.whiteDim)
              : (entry.recognized ? colorScheme.onSurface : colorScheme.outline),
        ),
      ),
      subtitle: Text(
        entry.word.meaning,
        style: textTheme.bodySmall?.copyWith(
          color: isDark ? NeonColors.whiteDim : colorScheme.outline,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.recognized
          ? Icon(Icons.check_circle_outline,
              color: isDark ? NeonColors.cyan : colorScheme.primary, size: 20)
          : Icon(Icons.radio_button_unchecked,
              color: isDark ? NeonColors.whiteDim : colorScheme.outline, size: 20),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<_WordSetsData>(
      future: _loadData(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (isDark) {
            return Container(
              decoration: BoxDecoration(
                color: NeonColors.glassBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NeonColors.glassBorder),
              ),
              child: const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          return const Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final data = snapshot.data!;
        final child = Column(
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
        );

        if (isDark) {
          return Container(
            decoration: BoxDecoration(
              color: NeonColors.glassBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: NeonColors.glassBorder),
            ),
            child: child,
          );
        }
        return Card(
          margin: EdgeInsets.zero,
          child: child,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                        ? (isDark
                            ? NeonColors.whiteDim.withAlpha(100)
                            : colorScheme.onSurface.withAlpha(100))
                        : (isDark ? NeonColors.white : colorScheme.onSurface),
                  ),
                ),
              ),
              if (isLocked)
                Icon(Icons.lock_outline,
                    size: 18,
                    color: isDark ? NeonColors.whiteDim : colorScheme.outline)
              else if (complete)
                Icon(Icons.check_circle_outline,
                    size: 18,
                    color: isDark ? NeonColors.cyan : colorScheme.primary),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.percentDone,
              minHeight: 6,
              backgroundColor: isDark
                  ? Colors.white.withAlpha(18)
                  : colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                isLocked
                    ? (isDark ? NeonColors.whiteDim : colorScheme.outline)
                    : (isDark ? NeonColors.cyan : colorScheme.primary),
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
                      ? (isDark
                          ? NeonColors.whiteDim.withAlpha(140)
                          : colorScheme.outline.withAlpha(140))
                      : (isDark ? NeonColors.whiteDim : colorScheme.outline),
                ),
              ),
              const Spacer(),
              if (canUnlock)
                GestureDetector(
                  onTap: onUnlock,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? NeonColors.cyan.withAlpha(20) : NeonColors.cyanDay.withAlpha(20),
                      border: Border.all(color: isDark ? NeonColors.cyan.withAlpha(80) : NeonColors.cyanDay.withAlpha(80), width: 1.5),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isDark
                          ? [
                              BoxShadow(color: NeonColors.cyan.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                              BoxShadow(color: NeonColors.cyan.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                            ]
                          : [
                              BoxShadow(color: NeonColors.cyanDay.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                              BoxShadow(color: NeonColors.cyanDay.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                            ],
                    ),
                    child: Text(
                      'Unlock Set $setNum',
                      style: textTheme.labelSmall?.copyWith(
                        color: isDark ? NeonColors.cyan : NeonColors.cyanDay,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Neon glow switch — outline track with glow when on
// ─────────────────────────────────────────────────────────────────────────────

class _NeonSwitchListTile extends StatelessWidget {
  const _NeonSwitchListTile({
    required this.title,
    this.subtitle,
    this.secondary,
    required this.value,
    required this.onChanged,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: secondary,
      title: title,
      subtitle: subtitle,
      trailing: _NeonSwitch(value: value, onChanged: onChanged),
      onTap: onChanged != null ? () => onChanged!(!value) : null,
    );
  }
}

class _NeonSwitch extends StatelessWidget {
  const _NeonSwitch({required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onColor = isDark ? NeonColors.cyan : NeonColors.cyanDay;
    final offColor = isDark ? NeonColors.whiteDim : NeonColors.inkDim;
    final glowColor = value ? onColor : offColor;

    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: glowColor,
            width: 1.5,
          ),
          boxShadow: value
              ? [
                  BoxShadow(
                    color: onColor.withAlpha(71),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: onColor.withAlpha(41),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: glowColor,
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: onColor.withAlpha(150),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
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
