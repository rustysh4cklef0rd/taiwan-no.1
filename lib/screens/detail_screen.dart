import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show invalidateLaunchCache, NeonColors;
import '../models/word.dart';
import '../providers/app_providers.dart';
import '../services/word_service.dart';
import '../widgets/neon_text.dart';

class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({
    super.key,
    this.wordId,
    this.embedded = false,
    this.onBack,
  });

  final int? wordId;
  final bool embedded;
  final VoidCallback? onBack;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  FlutterTts? _tts;
  bool _ttsAvailable = false;
  bool _isSpeaking = false;
  bool _loading = true;

  Word? _word;
  String? _error;
  bool _isRecognized = false;

  // Quiz mode state
  bool _quizModeEnabled = false;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _initTts();
    _loadQuizSetting();
  }

  Future<void> _initTts() async {
    final available = await WordService.checkTtsAvailability();
    if (!mounted) return;

    if (available) {
      final tts = FlutterTts();
      await tts.setLanguage('zh-TW');
      await tts.setSpeechRate(0.5);
      await tts.setVolume(1.0);
      await tts.setPitch(1.0);

      tts.setStartHandler(() {
        if (mounted) setState(() => _isSpeaking = true);
      });
      tts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      tts.setErrorHandler((_) {
        if (mounted) setState(() => _isSpeaking = false);
      });

      _tts = tts;
      _ttsAvailable = true;
    }

    if (mounted) setState(() {});
  }

  Future<void> _loadQuizSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _quizModeEnabled = prefs.getBool('quiz_mode') ?? false;
        _revealed = !_quizModeEnabled;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) {
      _loadWord();
    }
  }

  Future<void> _loadWord() async {
    // Prefer explicit wordId param (embedded mode); fall back to route arguments.
    final int? wordId = widget.wordId ??
        (ModalRoute.of(context)?.settings.arguments is int
            ? ModalRoute.of(context)!.settings.arguments as int
            : null);

    try {
      Word word;
      if (wordId != null) {
        final allWords = await WordService.loadWordList();
        word = allWords.firstWhere(
          (w) => w.id == wordId,
          orElse: () => allWords.first,
        );
      } else {
        final todaysWords = await WordService.getTodaysWords(DateTime.now());
        word = todaysWords.first;
      }
      // CANONICAL tap-recording point for all paths that open a word for review.
      // This covers: home tile tap, widget tap (cold/warm), direct navigation.
      // Do NOT add a second optimisticRecordTap call at the call site — it will double-count.
      ref.read(tapProvider.notifier).optimisticRecordTap(word.id);
      final recognized = await WordService.isRecognized(word.id);
      if (mounted) {
        setState(() {
          _word = word;
          _isRecognized = recognized;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load word.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _speak() async {
    if (_tts == null || _word == null) return;
    if (_isSpeaking) {
      await _tts!.stop();
      return;
    }
    await _tts!.speak(_word!.character);
  }

  Future<void> _speakPhrase() async {
    if (_tts == null || _word == null) return;
    if (_isSpeaking) {
      await _tts!.stop();
      return;
    }
    final textToSpeak = _word!.phrase.isNotEmpty ? _word!.phrase : _word!.character;
    await _tts!.speak(textToSpeak);
  }

  Future<void> _toggleRecognized() async {
    final word = _word;
    if (word == null) return;
    if (_isRecognized) {
      await WordService.unmarkRecognized(word.id);
      if (mounted) {
        setState(() => _isRecognized = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from mastered words'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      ref.read(tapProvider.notifier).optimisticRecordTap(word.id);
      await WordService.markRecognized(word.id);
      await WordService.replaceWordInToday(word.id);
      invalidateLaunchCache();
      if (mounted) {
        setState(() => _isRecognized = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${word.character} marked as mastered — won\'t appear in widget'),
            duration: const Duration(seconds: 3),
          ),
        );
        widget.onBack?.call();
      }
    }
  }

  Future<void> _recordQuizResult({required bool correct}) async {
    final word = _word;
    if (word == null) return;
    await WordService.recordQuizResult(word.id, correct: correct);
    if (!mounted) return;
    if (widget.embedded) {
      widget.onBack?.call();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  static String _getToneName(int tone) {
    const names = ['First Tone · 第一聲', 'Second Tone · 第二聲', 'Third Tone · 第三聲', 'Fourth Tone · 第四聲', 'Neutral Tone · 輕聲'];
    if (tone >= 1 && tone <= 4) return names[tone - 1];
    return names[4]; // neutral
  }

  static int _getToneNumber(String pinyin) {
    for (final c in pinyin.runes) {
      final ch = String.fromCharCode(c);
      if ('āēīōūǖ'.contains(ch)) return 1;
      if ('áéíóúǘ'.contains(ch)) return 2;
      if ('ǎěǐǒǔǚ'.contains(ch)) return 3;
      if ('àèìòùǜ'.contains(ch)) return 4;
    }
    return 5;
  }

  @override
  void dispose() {
    _tts?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const SizedBox.shrink(),
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: widget.embedded
            ? null
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: isDark
                    ? GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: NeonColors.glassBg,
                            border: Border.all(color: NeonColors.glassBorder, width: 1.5),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: Colors.white.withAlpha(10), blurRadius: 10, spreadRadius: 1),
                              BoxShadow(color: Colors.white.withAlpha(5), blurRadius: 20, spreadRadius: 2),
                            ],
                          ),
                          child: Text(
                            '← 返回',
                            style: TextStyle(
                              fontSize: 12,
                              color: NeonColors.cyan,
                              shadows: [Shadow(color: NeonColors.cyan.withAlpha(102), blurRadius: 6)],
                            ),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(184),
                            border: Border.all(color: NeonColors.cyanDay.withAlpha(41), width: 1.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '← 返回',
                            style: TextStyle(
                              fontSize: 12,
                              color: NeonColors.cyanDay,
                            ),
                          ),
                        ),
                      ),
              ),
        actions: [
          // Quiz mode toggle in app bar
          Tooltip(
            message: _quizModeEnabled ? 'Quiz mode on' : 'Quiz mode off',
            child: IconButton(
              icon: Icon(
                _quizModeEnabled
                    ? Icons.quiz
                    : Icons.quiz_outlined,
                color: _quizModeEnabled
                    ? (isDark ? NeonColors.cyan : colorScheme.primary)
                    : colorScheme.outline,
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final newVal = !_quizModeEnabled;
                await prefs.setBool('quiz_mode', newVal);
                if (mounted) {
                  setState(() {
                    _quizModeEnabled = newVal;
                    _revealed = !newVal;
                  });
                }
              },
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _quizModeEnabled && !_revealed
                  ? _buildQuizCard(colorScheme, textTheme)
                  : _buildContent(colorScheme, textTheme),
    );
  }

  // ── Quiz card (before reveal) ─────────────────────────────────────────────

  Widget _buildQuizCard(ColorScheme colorScheme, TextTheme textTheme) {
    final word = _word!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeonText(
              text: word.character,
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 120,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                height: 1.0,
              ),
              glowColor: const Color(0xFFFF2E63),
              mode: NeonMode.flicker,
            ),
            const SizedBox(height: 16),
            if (_ttsAvailable)
              IconButton(
                icon: Icon(
                  _isSpeaking
                      ? Icons.stop_circle_outlined
                      : Icons.volume_up_outlined,
                  color: colorScheme.primary,
                  size: 32,
                ),
                onPressed: _speak,
              ),
            const SizedBox(height: 40),
            Text(
              'What does this character mean?',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => setState(() => _revealed = true),
              child: Container(
                width: 200,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? NeonColors.pink.withAlpha(31) : NeonColors.cyanDay.withAlpha(20),
                  border: Border.all(
                    color: isDark ? NeonColors.pink.withAlpha(102) : NeonColors.cyanDay.withAlpha(102),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? NeonColors.pink.withAlpha(71) : NeonColors.cyanDay.withAlpha(71),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: isDark ? NeonColors.pink.withAlpha(41) : NeonColors.cyanDay.withAlpha(41),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Text(
                  'Reveal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? NeonColors.pink : NeonColors.cyanDay,
                    shadows: [
                      Shadow(
                        color: isDark ? NeonColors.pink.withAlpha(128) : NeonColors.cyanDay.withAlpha(100),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Full detail (after reveal or quiz mode off) ───────────────────────────

  Widget _buildContent(ColorScheme colorScheme, TextTheme textTheme) {
    final word = _word!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Character ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                colors: isDark
                    ? [NeonColors.pink.withAlpha(20), Colors.transparent]
                    : [NeonColors.pink.withAlpha(18), Colors.transparent],
                radius: 0.7,
              ),
              border: Border.all(
                color: isDark
                    ? NeonColors.pink.withAlpha(38)
                    : NeonColors.pink.withAlpha(46),
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  children: [
                    NeonText(
                      text: word.character,
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 112,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onSurface,
                        height: 1.0,
                      ),
                      glowColor: const Color(0xFFFF2E63),
                      mode: NeonMode.flicker,
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                _SpeakButton(
                  onPressed: _ttsAvailable ? _speak : null,
                  isSpeaking: _isSpeaking,
                  ttsAvailable: _ttsAvailable,
                  size: 44,
                ),
              ],
            ),
          ),

          // ── Pinyin ─────────────────────────────────────────────────────
          Text(
            word.pinyin,
            style: TextStyle(
              fontSize: 24,
              color: isDark ? NeonColors.cyan : NeonColors.inkDay,
              letterSpacing: 3,
              fontWeight: FontWeight.w300,
              shadows: isDark
                  ? [
                      Shadow(
                        color: NeonColors.cyan.withAlpha(128),
                        blurRadius: 10,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          isDark
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: NeonColors.cyan.withAlpha(25),
                    border: Border.all(color: NeonColors.cyan.withAlpha(64)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _getToneName(_getToneNumber(word.pinyin)),
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: NeonColors.cyan,
                    ),
                  ),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: NeonColors.cyanDay.withAlpha(26),
                    border: Border.all(color: NeonColors.cyanDay.withAlpha(71)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _getToneName(_getToneNumber(word.pinyin)),
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: NeonColors.cyanDay,
                    ),
                  ),
                ),
          const SizedBox(height: 12),

          // ── Meaning ────────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'MEANING',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: isDark ? NeonColors.whiteDim : NeonColors.inkDim,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? NeonColors.glassBg : Colors.white.withAlpha(184),
              border: Border.all(color: isDark ? NeonColors.glassBorder : NeonColors.cyanDay.withAlpha(41)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final style = textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 16,
                );
                final tp = TextPainter(
                  text: TextSpan(text: word.meaning, style: style),
                  maxLines: 1,
                  textDirection: TextDirection.ltr,
                )..layout(maxWidth: constraints.maxWidth);
                final align =
                    tp.didExceedMaxLines ? TextAlign.left : TextAlign.center;
                return Text(
                  word.meaning,
                  style: style,
                  textAlign: align,
                );
              },
            ),
          ),
          const SizedBox(height: 40),

          // ── Example phrase card ────────────────────────────────────────
          _PhraseCard(
            word: word,
            onSpeak: _ttsAvailable ? _speakPhrase : null,
            isSpeaking: _isSpeaking,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),

          // ── Quiz result buttons (shown after reveal in quiz mode) ──────
          if (_quizModeEnabled && _revealed) ...[
            const SizedBox(height: 24),
            if (isDark) ...[
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _recordQuizResult(correct: false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: NeonColors.pink.withAlpha(38),
                          border: Border.all(
                              color: NeonColors.pink.withAlpha(115), width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: NeonColors.pink.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                            BoxShadow(color: NeonColors.pink.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('↻ ', style: TextStyle(color: NeonColors.pink, fontSize: 16, shadows: [Shadow(color: Color(0x80FF2E63), blurRadius: 6)])),
                            Text('Again', style: TextStyle(color: NeonColors.pink, fontSize: 15, fontWeight: FontWeight.w600, shadows: [Shadow(color: Color(0x80FF2E63), blurRadius: 6)])),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _recordQuizResult(correct: true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: NeonColors.cyan.withAlpha(31),
                          border: Border.all(
                              color: NeonColors.cyan.withAlpha(102), width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: NeonColors.cyan.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                            BoxShadow(color: NeonColors.cyan.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('✓ ', style: TextStyle(color: NeonColors.cyan, fontSize: 16, shadows: [Shadow(color: Color(0x8000F5FF), blurRadius: 6)])),
                            Text('Good ✓', style: TextStyle(color: NeonColors.cyan, fontSize: 15, fontWeight: FontWeight.w600, shadows: [Shadow(color: Color(0x8000F5FF), blurRadius: 6)])),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final word = _word;
                  if (word == null) return;
                  ref.read(tapProvider.notifier).optimisticRecordTap(word.id);
                  await WordService.markRecognized(word.id);
                  await WordService.replaceWordInToday(word.id);
                  invalidateLaunchCache();
                  if (!mounted) return;
                  if (widget.embedded) {
                    widget.onBack?.call();
                  } else {
                    Navigator.of(context).maybePop();
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: NeonColors.orange.withAlpha(31),
                    border: Border.all(
                        color: NeonColors.orange.withAlpha(102), width: 1.5),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(color: NeonColors.orange.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                      BoxShadow(color: NeonColors.orange.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('⚡ ', style: TextStyle(color: NeonColors.orange, fontSize: 16, shadows: [Shadow(color: Color(0x80FF6B35), blurRadius: 6)])),
                      Text('Easy — Mastered ⚡', style: TextStyle(color: NeonColors.orange, fontSize: 15, fontWeight: FontWeight.w600, shadows: [Shadow(color: Color(0x80FF6B35), blurRadius: 6)])),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _recordQuizResult(correct: false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: NeonColors.pink.withAlpha(20),
                          border: Border.all(color: NeonColors.pink.withAlpha(80), width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: NeonColors.pink.withAlpha(36), blurRadius: 10, spreadRadius: 1),
                            BoxShadow(color: NeonColors.pink.withAlpha(20), blurRadius: 20, spreadRadius: 2),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('↻ ', style: TextStyle(color: NeonColors.pink, fontSize: 16)),
                            Text('Again', style: TextStyle(color: NeonColors.pink, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _recordQuizResult(correct: true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: NeonColors.cyanDay.withAlpha(20),
                          border: Border.all(color: NeonColors.cyanDay.withAlpha(80), width: 1.5),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: NeonColors.cyanDay.withAlpha(36), blurRadius: 10, spreadRadius: 1),
                            BoxShadow(color: NeonColors.cyanDay.withAlpha(20), blurRadius: 20, spreadRadius: 2),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('✓ ', style: TextStyle(color: NeonColors.cyanDay, fontSize: 16)),
                            Text('Good ✓', style: TextStyle(color: NeonColors.cyanDay, fontSize: 15, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],

          // ── Recognized button ──────────────────────────────────────────
          const SizedBox(height: 16),
          if (_isRecognized)
            isDark
                ? GestureDetector(
                    onTap: _toggleRecognized,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: NeonColors.glassBg,
                        border: Border.all(
                          color: NeonColors.pink.withAlpha(102),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: NeonColors.pink.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                          BoxShadow(color: NeonColors.pink.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, size: 18, color: NeonColors.pink),
                          SizedBox(width: 8),
                          Text(
                            'Mastered — tap to undo',
                            style: TextStyle(
                              color: NeonColors.pink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: _toggleRecognized,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: NeonColors.pink.withAlpha(20),
                        border: Border.all(color: NeonColors.pink.withAlpha(80), width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: NeonColors.pink.withAlpha(36), blurRadius: 10, spreadRadius: 1),
                          BoxShadow(color: NeonColors.pink.withAlpha(20), blurRadius: 20, spreadRadius: 2),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, size: 18, color: NeonColors.pink),
                          const SizedBox(width: 8),
                          Text(
                            'Mastered — tap to undo',
                            style: TextStyle(
                              color: NeonColors.pink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
          else
            isDark
                ? GestureDetector(
                    onTap: _toggleRecognized,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: NeonColors.glassBg,
                        border: Border.all(color: NeonColors.cyan.withAlpha(102), width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: NeonColors.cyan.withAlpha(71), blurRadius: 10, spreadRadius: 1),
                          BoxShadow(color: NeonColors.cyan.withAlpha(41), blurRadius: 20, spreadRadius: 2),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 18, color: NeonColors.cyan),
                          SizedBox(width: 8),
                          Text(
                            'I know this word',
                            style: TextStyle(
                              color: NeonColors.cyan,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : GestureDetector(
                    onTap: _toggleRecognized,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: NeonColors.cyanDay.withAlpha(20),
                        border: Border.all(color: NeonColors.cyanDay.withAlpha(80), width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: NeonColors.cyanDay.withAlpha(36), blurRadius: 10, spreadRadius: 1),
                          BoxShadow(color: NeonColors.cyanDay.withAlpha(20), blurRadius: 20, spreadRadius: 2),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 18, color: NeonColors.cyanDay),
                          const SizedBox(width: 8),
                          Text(
                            'I know this word',
                            style: TextStyle(
                              color: NeonColors.cyanDay,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

          // ── TTS unavailable notice ─────────────────────────────────────
          if (!_ttsAvailable) ...[
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer.withAlpha(80),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.volume_off,
                      color: colorScheme.onErrorContainer, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chinese TTS voice not installed. Install a Traditional Chinese (zh-TW) voice in your device\'s Text-to-Speech settings.',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phrase card
// ─────────────────────────────────────────────────────────────────────────────

class _PhraseCard extends StatelessWidget {
  const _PhraseCard({
    required this.word,
    required this.onSpeak,
    required this.isSpeaking,
    required this.colorScheme,
    required this.textTheme,
  });

  final Word word;
  final VoidCallback? onSpeak;
  final bool isSpeaking;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (word.phrase.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Center(
          child: Text(
            'Example phrase coming soon',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.outline),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: isDark
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  NeonColors.orange.withAlpha(20),
                  NeonColors.pink.withAlpha(13),
                ],
              ),
              border: Border.all(color: NeonColors.orange.withAlpha(64)),
              borderRadius: BorderRadius.circular(16),
            )
          : BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: const Border(
                left: BorderSide(
                  color: Color(0xFF00BFCC),
                  width: 3,
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isDark)
                Container(
                  width: 3,
                  height: 16,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [NeonColors.orange, NeonColors.pink],
                    ),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: NeonColors.orange,
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              Text(
                'Example Phrase',
                style: textTheme.labelSmall?.copyWith(
                  color: isDark ? NeonColors.orange : colorScheme.outline,
                  letterSpacing: 1.2,
                  shadows: isDark
                      ? [
                          Shadow(
                            color: NeonColors.orange.withAlpha(102),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      word.phrase,
                      style: TextStyle(
                        fontFamily: 'serif',
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.phrasePinyin,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? NeonColors.cyan.withAlpha(204)
                            : colorScheme.outline,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.phraseMeaning,
                      style: textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? NeonColors.whiteDim
                            : colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              _SpeakButton(
                onPressed: onSpeak,
                isSpeaking: isSpeaking,
                ttsAvailable: onSpeak != null,
                size: 36,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Speak button
// ─────────────────────────────────────────────────────────────────────────────

class _SpeakButton extends StatelessWidget {
  const _SpeakButton({
    required this.onPressed,
    required this.isSpeaking,
    required this.ttsAvailable,
    required this.size,
  });

  final VoidCallback? onPressed;
  final bool isSpeaking;
  final bool ttsAvailable;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!ttsAvailable) {
      return Icon(
        Icons.volume_off,
        size: size * 0.7,
        color: colorScheme.outline,
      );
    }

    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          isSpeaking ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
          key: ValueKey(isSpeaking),
          color: colorScheme.primary,
          size: size * 0.75,
        ),
      ),
      iconSize: size,
      onPressed: onPressed,
      tooltip: isSpeaking ? 'Stop' : 'Play pronunciation',
    );
  }
}
