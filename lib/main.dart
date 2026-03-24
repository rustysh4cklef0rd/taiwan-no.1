import 'package:flutter/material.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // First-run initialisation.
  final prefs = await SharedPreferences.getInstance();
  final bool isFirstRun = !(prefs.getBool('onboarding_complete') ?? false);

  if (isFirstRun) {
    await _initializeFirstRun();
  } else {
    // Always push today's words on launch in case the date changed.
    await _pushTodaysWordsToWidget();
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
  await _pushTodaysWordsToWidget();
  // Daily WorkManager is scheduled on the native Kotlin side (DailyWordWorker).
}

/// Pushes today's 6 words to the home_widget SharedPreferences store and
/// requests a widget redraw.
Future<void> _pushTodaysWordsToWidget([DateTime? date]) async {
  try {
    final target = date ?? DateTime.now();
    final List<Word> words = await WordService.getTodaysWords(target);

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

    await HomeWidget.updateWidget(androidName: 'WordWidgetProvider4x2');
    await HomeWidget.updateWidget(androidName: 'WordWidgetProvider2x2');
    await HomeWidget.updateWidget(androidName: 'FlashcardWidgetProvider');
    await HomeWidget.updateWidget(androidName: 'FlashcardWidget2x2Provider');
  } catch (_) {
    // Silently continue — the widget will update on next WorkManager run.
  }
}

/// Determines which screen to open on launch.
///
/// Priority:
///   1. Widget tap: home_widget passes `launch_word_index` via intent extra.
///   2. Onboarding not complete → '/onboarding'
///   3. Otherwise → '/home'
Future<String> _resolveInitialRoute(SharedPreferences prefs) async {
  try {
    final dynamic tappedIndex =
        await HomeWidget.getWidgetData<int>('launch_word_index');
    if (tappedIndex != null && tappedIndex.toString().isNotEmpty) {
      // Clear after reading so the next cold start doesn't re-open detail.
      await HomeWidget.saveWidgetData<String>('launch_word_index', '');
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
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8B1C13),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
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
        return MaterialPageRoute(
          builder: (_) => const DetailScreen(),
          settings: settings,
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
    final words = await WordService.getTodaysWords(DateTime.now());
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
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日漢字'),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Today's characters",
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.9,
                      ),
                      itemCount: _words.length,
                      itemBuilder: (context, index) {
                        final w = _words[index];
                        return _WordTile(
                          word: w,
                          onTap: () => Navigator.of(context).pushNamed(
                            '/detail',
                            arguments: index,
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              word.character,
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              word.pinyin,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
