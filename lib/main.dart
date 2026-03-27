import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/word.dart';
import 'screens/detail_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'services/word_service.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Disable network font fetching — all fonts are bundled as assets.
  GoogleFonts.config.allowRuntimeFetching = false;

  // First-run initialisation.
  final prefs = await SharedPreferences.getInstance();

  // Restore persisted day offset (survives app restarts).
  simulatedDayOffset = prefs.getInt('day_offset') ?? 0;

  // Record install date once — word rotation is anchored to this so
  // every install starts from word 1 rather than mid-cycle.
  if (!prefs.containsKey('install_epoch_day')) {
    final todayEpoch = DateTime.now()
        .toUtc()
        .difference(DateTime.utc(1970, 1, 1))
        .inDays;
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
    ChineseReadingApp(
      initialRoute: initialRoute,
      ttsAvailable: ttsAvailable,
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
        target.toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;
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
      return '/detail';
    }
  } catch (_) {}

  final bool onboardingDone = prefs.getBool('onboarding_complete') ?? false;
  if (!onboardingDone) return '/onboarding';

  return '/home';
}

// ─────────────────────────────────────────────────────────────────────────────
// App root
// ─────────────────────────────────────────────────────────────────────────────

class ChineseReadingApp extends StatefulWidget {
  const ChineseReadingApp({
    super.key,
    required this.initialRoute,
    required this.ttsAvailable,
  });

  final String initialRoute;
  final bool ttsAvailable;

  @override
  State<ChineseReadingApp> createState() => _ChineseReadingAppState();
}

class _ChineseReadingAppState extends State<ChineseReadingApp> {
  bool _darkMode = false;
  bool _showTtsPrompt = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
    if (!widget.ttsAvailable) {
      _checkTtsPrompt();
    }
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _darkMode = prefs.getBool('dark_mode') ?? false;
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
      seedColor: const Color(0xFFC9372C),
      brightness: brightness,
    ).copyWith(
      primary: const Color(0xFFC9372C),
      onPrimary: Colors.white,
      surfaceContainerHighest:
          isDark ? const Color(0xFF2D2520) : Colors.white,
      // Explicitly brighten text in dark mode — auto-generated values are too
      // dim against the custom #2D2520 tile background.
      onSurface: isDark ? const Color(0xFFF2E4DF) : null,
      onSurfaceVariant: isDark ? const Color(0xFFDDC8C2) : null,
      outline: isDark ? const Color(0xFFCDB8B3) : null,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: base,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF1A1614) : const Color(0xFFFAF5EE),
      textTheme: ThemeData(useMaterial3: true, brightness: brightness)
          .textTheme
          .apply(fontFamily: 'Nunito'),
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
          builder: (_) => const DetailScreen(),
          settings: RouteSettings(name: '/detail', arguments: wordId),
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const HomeScreen(),
          settings: settings,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home screen — today's 6 words grid
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Word> _words = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // If the app was resumed on a new calendar day (main() didn't re-run),
    // _launchWords is stale — re-push so the home screen and widget stay in sync.
    final effective = effectiveDate;
    final effectiveDay =
        effective.toUtc().difference(DateTime.utc(1970, 1, 1)).inDays;
    // ignore: avoid_print
    print('[CWDBG] HomeScreen._load: effectiveDay=$effectiveDay _launchWordsDay=$_launchWordsDay _launchWords=${_launchWords?.map((w) => '${w.character}(${w.id})').toList()}');
    if ((_launchWordsDay ?? -1) != effectiveDay) {
      await pushTodaysWordsToWidget(effective);
    }
    final words = _launchWords ?? await WordService.getTodaysWords(effective);
    // ignore: avoid_print
    print('[CWDBG] HomeScreen._load: showing words=${words.map((w) => '${w.character}(${w.id})').toList()}');
    if (mounted) {
      setState(() {
        _words = words;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = effectiveDate;
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '今日漢字',
          style: const TextStyle(
            fontFamily: 'serif',
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC9372C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              months[now.month - 1].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 7,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              '${now.day}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Today's characters",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            simulatedDayOffset == 0
                                ? 'Tap any character to study'
                                : 'Day offset: ${simulatedDayOffset > 0 ? '+' : ''}$simulatedDayOffset',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: _words.length,
                      itemBuilder: (context, index) {
                        final w = _words[index];
                        return _WordTile(
                          word: w,
                          onTap: () => Navigator.of(context).pushNamed(
                            '/detail',
                            arguments: w.id,
                          ),
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

class _WordTile extends StatelessWidget {
  const _WordTile({required this.word, required this.onTap});

  final Word word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 40 : 18),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(8, 18, 8, 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  word.character,
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  word.pinyin,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.outline,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  word.meaning.split(';').first.split(',').first.trim(),
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.outline.withAlpha(160),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 3,
              decoration: const BoxDecoration(
                color: Color(0xFFC9372C),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
