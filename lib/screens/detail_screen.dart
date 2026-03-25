import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/word.dart';
import '../services/word_service.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
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
    final args = ModalRoute.of(context)?.settings.arguments;
    // Arguments are always a word ID (int) — set by HomeScreen or widget tap.
    final int? wordId = args is int ? args : null;

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
      await WordService.recordTap(word.id);
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
    await _tts!.speak(_word!.phrase);
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
      await WordService.markRecognized(word.id);
      if (mounted) {
        setState(() => _isRecognized = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${word.character} marked as mastered — won\'t appear in widget'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _recordQuizResult({required bool correct}) async {
    final word = _word;
    if (word == null) return;
    await WordService.recordQuizResult(word.id, correct: correct);
    if (mounted) Navigator.of(context).maybePop();
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

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
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
                    ? colorScheme.primary
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.character,
              style: TextStyle(
                fontSize: 120,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
                height: 1.0,
              ),
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
            FilledButton(
              onPressed: () => setState(() => _revealed = true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 52),
              ),
              child: const Text('Reveal', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Full detail (after reveal or quiz mode off) ───────────────────────────

  Widget _buildContent(ColorScheme colorScheme, TextTheme textTheme) {
    final word = _word!;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Character ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                word.character,
                style: TextStyle(
                  fontSize: 96,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                  height: 1.1,
                ),
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

          // ── Pinyin ─────────────────────────────────────────────────────
          Text(
            word.pinyin,
            style: TextStyle(
              fontSize: 24,
              color: colorScheme.outline,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),

          // ── Meaning ────────────────────────────────────────────────────
          Text(
            word.meaning,
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
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
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _recordQuizResult(correct: false),
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Still learning'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: colorScheme.error,
                      side: BorderSide(color: colorScheme.error),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _recordQuizResult(correct: true),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Got it'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      backgroundColor: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // ── Recognized button ──────────────────────────────────────────
          const SizedBox(height: 16),
          _isRecognized
              ? FilledButton.icon(
                  onPressed: _toggleRecognized,
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Mastered — tap to undo'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: _toggleRecognized,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('I know this word'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Example Phrase',
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.outline,
              letterSpacing: 1.2,
            ),
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
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.phrasePinyin,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.outline,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      word.phraseMeaning,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
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
