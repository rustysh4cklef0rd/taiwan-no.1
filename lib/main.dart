import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db/app_database.dart';
import 'db/tap_repository.dart';
import 'models/word.dart';
import 'providers/app_providers.dart';
import 'screens/detail_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'services/word_service.dart';
import 'widgets/neon_text.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

/// Word ID stored here when the app is cold-started from a widget tap,
/// so the initial /detail route can pass the correct word to DetailScreen.
int? _pendingDetailWordId;

/// Words written to the widget prefs on this launch — the home screen reads
/// this directly so it always shows exactly what was pushed to the widget.
List<Word>? _launchWords;

/// The UTC epoch day on which [_launchWords] was last computed.
/// Used to detect app-resume on a new day (when main() doesn't re-run).
int? _launchWordsDay;

/// Clears the in-memory word cache so the next home-screen load recomputes
/// from SharedPreferences (e.g. after a word is replaced via settings).
void invalidateLaunchCache() {
  _launchWords = null;
  _launchWordsDay = null;
}

/// Number of days to add to today for day-navigation (persisted in SharedPreferences).
int simulatedDayOffset = 0;

/// Current effective date: real today + any persisted day offset.
DateTime get effectiveDate =>
    DateTime.now().add(Duration(days: simulatedDayOffset));

/// Persist a new day offset and update the in-memory value.
Future<void> saveDayOffset(int offset) async {
  simulatedDayOffset = offset;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('day_offset', offset);
}

Future<void> _migrateTapData(SharedPreferences prefs) async {
  final db = AppDatabase();
  final allKeys = prefs.getKeys();

  // Build epochDay → Set<wordId> from tapped_<wordId> keys
  final Map<int, Set<int>> dayToWords = {};
  for (final key in allKeys) {
    if (key.startsWith('tapped_')) {
      final wordId = int.tryParse(key.substring(7));
      if (wordId == null) continue;
      final day = prefs.getInt(key);
      if (day == null) continue;
      dayToWords.putIfAbsent(day, () => {}).add(wordId);
    }
  }

  // Insert rows for each daily_ key
  final rows = <({int wordId, int tappedAt})>[];
  for (final key in allKeys) {
    if (!key.startsWith('daily_')) continue;
    final epochDay = int.tryParse(key.substring(6));
    if (epochDay == null) continue;
    final count = prefs.getInt(key) ?? 0;
    final words = (dayToWords[epochDay] ?? {}).toList();
    final baseTs = epochDay * 86400000;
    for (int i = 0; i < count; i++) {
      final wordId = i < words.length ? words[i] : 0;
      rows.add((wordId: wordId, tappedAt: baseTs + i));
    }
  }

  if (rows.isNotEmpty) {
    final repo = TapRepository(db);
    await repo.insertTaps(rows);
  }
  await db.close();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Disable network font fetching — all fonts are bundled as assets.
  GoogleFonts.config.allowRuntimeFetching = false;

  // First-run initialisation.
  final prefs = await SharedPreferences.getInstance();

  // Migrate tap data from SharedPreferences to SQLite (one-time).
  final migrated = prefs.getBool('tap_migration_v1_complete') ?? false;
  if (!migrated) {
    await _migrateTapData(prefs);
    await prefs.setBool('tap_migration_v1_complete', true);
  }

  // Restore persisted day offset (survives app restarts).
  simulatedDayOffset = prefs.getInt('day_offset') ?? 0;

  // Record install date once — word rotation is anchored to this so
  // every install starts from word 1 rather than mid-cycle.
  if (!prefs.containsKey('install_epoch_day')) {
    final todayEpoch = DateTime.now().difference(DateTime(1970)).inDays;
    await prefs.setInt('install_epoch_day', todayEpoch);
  }

  final bool isFirstRun = !(prefs.getBool('onboarding_complete') ?? false);

  if (isFirstRun) {
    await _initializeFirstRun();
  } else {
    // Always push today's words on launch in case the date changed.
    await pushTodaysWordsToWidget(effectiveDate);
  }

  // Check TTS availability once and store the result.
  final bool ttsAvailable = await WordService.checkTtsAvailability();
  await prefs.setBool('tts_available', ttsAvailable);

  // Determine initial route (widget tap vs onboarding vs home).
  final String initialRoute = await _resolveInitialRoute(prefs);

  runApp(
    ProviderScope(
      child: ChineseReadingApp(
        initialRoute: initialRoute,
        ttsAvailable: ttsAvailable,
      ),
    ),
  );
}

/// Called once on first launch to seed widget data and schedule daily updates.
Future<void> _initializeFirstRun() async {
  await pushTodaysWordsToWidget();
  // Daily WorkManager is scheduled on the native Kotlin side (DailyWordWorker).
}

/// Pushes today's 6 words to the home_widget SharedPreferences store and
/// requests a widget redraw.
Future<void> pushTodaysWordsToWidget([DateTime? date]) async {
  try {
    final target = date ?? DateTime.now();
    final List<Word> words = await WordService.getTodaysWords(target);

    final epochDay =
        target.difference(DateTime(1970)).inDays;
    _launchWords = words; // cache so HomeScreen uses the exact same list
    _launchWordsDay = epochDay; // track the day so stale cache can be detected
    // ignore: avoid_print
    print('[CWDBG] pushTodaysWordsToWidget: epochDay=$epochDay words=${words.map((w) => '${w.character}(${w.id})').toList()}');

    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      await HomeWidget.saveWidgetData<String>('word_${i}_char', w.character);
      await HomeWidget.saveWidgetData<String>('word_${i}_pinyin', w.pinyin);
      await HomeWidget.saveWidgetData<String>('word_${i}_meaning', w.meaning);
      await HomeWidget.saveWidgetData<String>('word_${i}_phrase', w.phrase);
      await HomeWidget.saveWidgetData<String>(
          'word_${i}_phrase_pinyin', w.phrasePinyin);
      await HomeWidget.saveWidgetData<String>(
          'word_${i}_phrase_meaning', w.phraseMeaning);
      await HomeWidget.saveWidgetData<String>(
          'word_${i}_id', w.id.toString());
    }

    await HomeWidget.saveWidgetData<String>(
        'last_updated', target.toIso8601String());
    await HomeWidget.saveWidgetData<String>(
        'last_epoch_day', epochDay.toString());

    // Directly call native to update all widget instances synchronously,
    // bypassing home_widget's async broadcast which can arrive too late.
    const widgetOpsChannel = MethodChannel('com.chinesewidget/widget_ops');
    await widgetOpsChannel.invokeMethod('forceUpdate');
    // ignore: avoid_print
    print('[CWDBG] pushTodaysWordsToWidget: done, forceUpdate called');
  } catch (e, st) {
    // ignore: avoid_print
    print('[CWDBG] pushTodaysWordsToWidget FAILED: $e\n$st');
  }
}

/// Determines which screen to open on launch.
///
/// Priority:
///   1. Widget tap: home_widget passes `launch_word_id` via intent extra.
///   2. Onboarding not complete → '/onboarding'
///   3. Otherwise → '/home'
Future<String> _resolveInitialRoute(SharedPreferences prefs) async {
  try {
    final dynamic wordId =
        await HomeWidget.getWidgetData<int>('launch_word_id');
    if (wordId is int && wordId > 0) {
      _pendingDetailWordId = wordId;
      // Clear so the next cold start doesn't re-open detail.
      await HomeWidget.saveWidgetData<int>('launch_word_id', -1);
      // IMPORTANT: Always return '/' here, never '/detail'.
      // If initialRoute is '/detail', Flutter pre-pushes '/' first, creating TWO
      // HomeScreen instances in the back stack — causing the "extra home page on back" bug.
      // The default route handler below reads _pendingDetailWordId and passes it to HomeScreen.
      return '/';
    }
  } catch (_) {}

  final bool onboardingDone = prefs.getBool('onboarding_complete') ?? false;
  if (!onboardingDone) return '/onboarding';

  return '/';
}

// ─────────────────────────────────────────────────────────────────────────────
// Neon Night Market colour palette (shared across screens)
// ─────────────────────────────────────────────────────────────────────────────

class NeonColors {
  NeonColors._();

  // Backgrounds
  static const night     = Color(0xFF0D0D0F);
  static const nightMid  = Color(0xFF13131A);
  static const nightLift = Color(0xFF1A1A26);

  // Accents
  static const pink   = Color(0xFFFF2E63);
  static const cyan   = Color(0xFF00F5FF);
  static const orange = Color(0xFFFF6B35);

  // Light-mode accents
  static const cyanDay = Color(0xFF00BFCC); // light-mode muted teal

  // Light-mode ink
  static const inkDay = Color(0xFF1A1A2E); // --ink
  static const inkMid = Color(0xFF3A3A5C); // --ink-mid
  static const inkDim = Color(0xFF6B6B8A); // --ink-dim

  // Text
  static const white    = Color(0xFFE8E8E8);
  static const whiteDim = Color(0xFFA0A0B0);

  // Glass surfaces
  static const glassBg     = Color(0x0AFFFFFF); // rgba(255,255,255,0.04)
  static const glassBorder = Color(0x1AFFFFFF); // rgba(255,255,255,0.10)
}

// ─────────────────────────────────────────────────────────────────────────────
// App root
// ─────────────────────────────────────────────────────────────────────────────

class ChineseReadingApp extends ConsumerStatefulWidget {
  const ChineseReadingApp({
    super.key,
    required this.initialRoute,
    required this.ttsAvailable,
  });

  final String initialRoute;
  final bool ttsAvailable;

  @override
  ConsumerState<ChineseReadingApp> createState() => _ChineseReadingAppState();
}

class _ChineseReadingAppState extends ConsumerState<ChineseReadingApp>
    with WidgetsBindingObserver {
  bool _darkMode = true; // default to dark; overridden by saved pref
  bool _showTtsPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTheme();
    if (!widget.ttsAvailable) {
      _checkTtsPrompt();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      ref.read(tapProvider.notifier).refresh();
      ref.invalidate(todaysWordsProvider);
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _darkMode = prefs.getBool('dark_mode') ?? true;
      });
    }
  }

  Future<void> _checkTtsPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final bool shown = prefs.getBool('tts_prompt_shown') ?? false;
    if (!shown && mounted) {
      setState(() => _showTtsPrompt = true);
      await prefs.setBool('tts_prompt_shown', true);
    }
  }

  void _toggleDarkMode(bool isDark) async {
    setState(() => _darkMode = isDark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', isDark);
  }

  @override
  Widget build(BuildContext context) {
    return ThemeModeNotifier(
      toggle: _toggleDarkMode,
      child: MaterialApp(
        title: 'Chinese Reading Widget',
        debugShowCheckedModeBanner: false,
        themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        initialRoute: widget.initialRoute,
        onGenerateRoute: _onGenerateRoute,
        builder: (context, child) {
          if (_showTtsPrompt) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _showTtsPrompt = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Chinese TTS voice not found. Install a zh-TW voice in '
                    'Settings > Accessibility > Text-to-Speech for pronunciation.',
                  ),
                  duration: Duration(seconds: 6),
                ),
              );
            });
          }
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: isDark ? NeonColors.pink : const Color(0xFF00BFCC),
      brightness: brightness,
    ).copyWith(
      primary: isDark ? NeonColors.pink : const Color(0xFF00BFCC),
      onPrimary: Colors.white,
      secondary: isDark ? NeonColors.cyan : null,
      tertiary: isDark ? NeonColors.orange : null,
      surfaceContainerHighest:
          isDark ? NeonColors.nightLift : Colors.white,
      onSurface: isDark ? NeonColors.white : null,
      onSurfaceVariant: isDark ? NeonColors.white : null,
      outline: isDark ? NeonColors.whiteDim : null,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: base,
      scaffoldBackgroundColor:
          isDark ? NeonColors.night : const Color(0xFFF0F1F5),
      textTheme: ThemeData(useMaterial3: true, brightness: brightness)
          .textTheme
          .apply(fontFamily: 'Nunito'),
      switchTheme: isDark
          ? SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return NeonColors.cyan;
                }
                return NeonColors.whiteDim;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                return Colors.transparent;
              }),
              trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return NeonColors.cyan;
                }
                return NeonColors.whiteDim.withAlpha(100);
              }),
              trackOutlineWidth: WidgetStateProperty.all(1.5),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return NeonColors.cyan.withAlpha(30);
                }
                return null;
              }),
            )
          : null,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/onboarding':
        return MaterialPageRoute(
          builder: (_) => const OnboardingScreen(),
          settings: settings,
        );
      case '/home':
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
      case '/detail':
        // Prefer explicit route argument; fall back to cold-start pending ID.
        final wordId = (settings.arguments is int)
            ? settings.arguments as int
            : _pendingDetailWordId;
        _pendingDetailWordId = null; // consume
        return MaterialPageRoute(
          builder: (_) => HomeScreen(initialDetailWordId: wordId),
          settings: settings,
        );
      default:
        // IMPORTANT: Consume _pendingDetailWordId here (set by widget tap cold-start).
        // This is the only route pushed on launch — passing the word ID directly avoids
        // the duplicate HomeScreen back-stack bug caused by using '/detail' as initialRoute.
        final pending = _pendingDetailWordId;
        _pendingDetailWordId = null;
        return MaterialPageRoute(
          builder: (_) => HomeScreen(initialDetailWordId: pending),
          settings: settings,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home screen — today's 6 words grid
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialDetailWordId});

  final int? initialDetailWordId;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Word> _words = [];
  bool _loading = true;
  int _streakCurrent = 0;

  // Persistent nav state
  int _selectedIndex = 0;
  int? _reviewWordId;
  int _settingsRefreshSeed = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialDetailWordId != null) {
      _reviewWordId = widget.initialDetailWordId;
      _selectedIndex = 1;
    }
    _load();
  }

  // Map nav index (0-3) to page index (0-2): Stats(2) and Settings(3) share SettingsScreen
  int get _effectivePageIndex {
    if (_selectedIndex <= 1) return _selectedIndex;
    return 2;
  }

  Future<void> _load() async {
    final effective = effectiveDate;
    final effectiveDay = effective.difference(DateTime(1970)).inDays;
    if ((_launchWordsDay ?? -1) != effectiveDay) {
      await pushTodaysWordsToWidget(effective);
    }
    final words = _launchWords ?? await WordService.getTodaysWords(effective);
    final streak = await WordService.getStreakData();
    if (mounted) {
      setState(() {
        _words = words;
        _streakCurrent = streak.current;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      // canPop: allow exit only when already on the home tab
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _effectivePageIndex,
                children: [
                  _buildHomeBody(context),
                  _reviewWordId != null
                      ? DetailScreen(
                          key: ValueKey(_reviewWordId),
                          wordId: _reviewWordId,
                          embedded: true,
                          onBack: () {
                            _load();
                            setState(() {
                              _selectedIndex = 0;
                              _settingsRefreshSeed++;
                            });
                          },
                        )
                      : const SizedBox.shrink(),
                  SettingsScreen(
                    key: ValueKey(_settingsRefreshSeed),
                    embedded: true,
                    onDayChanged: _load,
                  ),
                ],
              ),
        bottomNavigationBar: _buildNavBar(isDark, colorScheme),
      ),
    );
  }

  Widget _buildNavBar(bool isDark, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? NeonColors.night.withAlpha(204)
            : colorScheme.surface.withAlpha(225),
        border: Border(
          top: BorderSide(
            color: isDark ? NeonColors.glassBorder : NeonColors.cyanDay.withAlpha(36),
          ),
        ),
      ),
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: '⬡',
            label: 'Home',
            active: _selectedIndex == 0,
            onTap: () => setState(() => _selectedIndex = 0),
          ),
          _NavItem(
            icon: '◈',
            label: 'Review',
            active: _selectedIndex == 1,
            onTap: () {
              if (_words.isNotEmpty) {
                setState(() {
                  _reviewWordId ??= _words.first.id;
                  _selectedIndex = 1;
                });
              }
            },
          ),
          _NavItem(
            icon: '◉',
            label: 'Stats',
            active: _selectedIndex == 2,
            onTap: () => setState(() => _selectedIndex = 2),
          ),
          _NavItem(
            icon: '◎',
            label: 'Settings',
            active: _selectedIndex == 3,
            onTap: () => setState(() => _selectedIndex = 3),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = effectiveDate;
    const zhMonths = ['一月','二月','三月','四月','五月','六月','七月','八月','九月','十月','十一月','十二月'];
    const zhWeekdays = ['週一','週二','週三','週四','週五','週六','週日'];

    // Tile accent colours cycle: pink, cyan, orange
    const tileAccents = [NeonColors.pink, NeonColors.cyan, NeonColors.orange];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            // ── App header ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 20),
              child: Column(
                children: [
                  NeonText(
                    text: '學字',
                    style: const TextStyle(
                      fontFamily: 'serif',
                      fontSize: 32,
                      letterSpacing: 4,
                    ),
                    glowColor: NeonColors.pink,
                    mode: NeonMode.flicker,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Learn Chinese · 每日六字',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 3,
                      color: isDark
                          ? NeonColors.cyan.withAlpha(204)
                          : colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),

            // ── Date row ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Date pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? NeonColors.glassBg
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    border: isDark
                        ? Border.all(color: NeonColors.glassBorder)
                        : null,
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${zhMonths[now.month - 1]} ',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? NeonColors.whiteDim
                                : NeonColors.inkDim,
                          ),
                        ),
                        TextSpan(
                          text: '${now.day}日',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? NeonColors.cyan
                                : NeonColors.cyanDay,
                            shadows: isDark
                                ? [
                                    Shadow(
                                      color: NeonColors.cyan.withAlpha(128),
                                      blurRadius: 6,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        TextSpan(
                          text: ' · ${zhWeekdays[now.weekday - 1]}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? NeonColors.whiteDim
                                : NeonColors.inkDim,
                          ),
                        ),
                        TextSpan(
                          text: simulatedDayOffset != 0
                              ? '  (${simulatedDayOffset > 0 ? '+' : ''}$simulatedDayOffset)'
                              : '',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? NeonColors.whiteDim
                                : NeonColors.inkDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Streak pill
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark
                        ? NeonColors.orange.withAlpha(31)
                        : colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: isDark
                        ? Border.all(
                            color: NeonColors.orange.withAlpha(89))
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🔥', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '${ref.watch(tapProvider).valueOrNull?.streakCurrent ?? _streakCurrent}天 streak',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? NeonColors.orange
                              : colorScheme.onTertiaryContainer,
                          shadows: isDark
                              ? [
                                  Shadow(
                                    color:
                                        NeonColors.orange.withAlpha(153),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Section label ──────────────────────────────────
            Row(
              children: [
                Text(
                  "TODAY'S CHARACTERS",
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 3,
                    color: isDark
                        ? NeonColors.whiteDim
                        : colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                Colors.white.withAlpha(20),
                                Colors.transparent,
                              ]
                            : [
                                NeonColors.cyanDay.withAlpha(64),
                                Colors.transparent,
                              ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── 2-column character grid ───────────────────────
            Expanded(
              child: GridView.builder(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.95,
                ),
                itemCount: _words.length,
                itemBuilder: (context, index) {
                  final w = _words[index];
                  return _WordTile(
                    word: w,
                    accent: tileAccents[index % tileAccents.length],
                    onTap: () {
                      // NOTE: do NOT call optimisticRecordTap here.
                      // DetailScreen._loadWord() records the tap when built with a new key.
                      // Calling it here AND there causes every tile tap to count as 2 taps.
                      setState(() {
                        _reviewWordId = w.id;
                        _selectedIndex = 1;
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom nav item ───────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = active
        ? (isDark ? NeonColors.cyan : NeonColors.cyanDay)
        : (isDark ? NeonColors.whiteDim : NeonColors.inkDim);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            icon,
            style: TextStyle(
              fontSize: 18,
              color: color,
              shadows: active
                  ? (isDark
                      ? [Shadow(color: NeonColors.cyan, blurRadius: 8)]
                      : [Shadow(color: NeonColors.cyanDay.withAlpha(153), blurRadius: 8)])
                  : null,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 0.5,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Word tile (glass morphism) ────────────────────────────────────────────

class _WordTile extends StatelessWidget {
  const _WordTile({
    required this.word,
    required this.accent,
    required this.onTap,
  });

  final Word word;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? NeonColors.glassBg : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? NeonColors.glassBorder : NeonColors.cyanDay.withAlpha(41),
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(18),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              word.character,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 52,
                height: 1,
                color: isDark ? NeonColors.white : colorScheme.onSurface,
                shadows: isDark
                    ? [
                        Shadow(
                          color: Colors.white.withAlpha(51),
                          blurRadius: 4,
                        ),
                      ]
                    : [
                        Shadow(
                          color: NeonColors.inkDay.withAlpha(31),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              word.pinyin,
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 1,
                color: isDark ? NeonColors.cyan : NeonColors.inkDay,
                shadows: isDark
                    ? [
                        Shadow(
                          color: NeonColors.cyan.withAlpha(128),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              word.meaning.split(';').first.split(',').first.trim(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.3,
                color: isDark ? NeonColors.whiteDim : colorScheme.outline,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
