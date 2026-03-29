import 'package:flutter/material.dart';

enum NeonMode { flicker, pulse }

class NeonText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color glowColor;
  final NeonMode mode;

  const NeonText({
    super.key,
    required this.text,
    this.style,
    required this.glowColor,
    this.mode = NeonMode.flicker,
  });

  @override
  State<NeonText> createState() => _NeonTextState();
}

class _NeonTextState extends State<NeonText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _intensity;

  @override
  void initState() {
    super.initState();

    if (widget.mode == NeonMode.flicker) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 4),
      );
      // Mirrors the CSS neon-flicker keyframes:
      // steady glow with brief flicker-offs at 20%, 24%, and 55%.
      _intensity = TweenSequence<double>([
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 19),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 2),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 29),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
        TweenSequenceItem(tween: ConstantTween(1.0), weight: 44),
      ]).animate(_controller);
    } else {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 3),
      );
      _intensity = CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      );
    }

    _controller.repeat(reverse: widget.mode == NeonMode.pulse);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Dark mode: vivid neon glow
  List<Shadow> _buildDarkShadows(double t) {
    final c = widget.glowColor;
    return [
      Shadow(color: c.withValues(alpha: 1.0 * t), blurRadius: 6),
      Shadow(color: c.withValues(alpha: 1.0 * t), blurRadius: 14),
      Shadow(color: c.withValues(alpha: 0.7 * t), blurRadius: 28),
      Shadow(color: c.withValues(alpha: 0.4 * t), blurRadius: 50),
    ];
  }

  // Light mode: soft cyan glow using the neon day palette accent
  static const _lightGlow = Color(0xFF00BFCC);

  List<Shadow> _buildLightShadows(double t) {
    return [
      Shadow(color: _lightGlow.withValues(alpha: 0.8 * t), blurRadius: 6),
      Shadow(color: _lightGlow.withValues(alpha: 0.5 * t), blurRadius: 16),
      Shadow(color: _lightGlow.withValues(alpha: 0.3 * t), blurRadius: 32),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _intensity,
      builder: (context, child) {
        final t = _intensity.value;
        final shadows =
            isDark ? _buildDarkShadows(t) : _buildLightShadows(t);
        return Opacity(
          opacity: isDark && t < 0.5 ? 0.85 : 1.0,
          child: Text(
            widget.text,
            style: widget.style?.copyWith(shadows: shadows) ??
                TextStyle(shadows: shadows),
          ),
        );
      },
    );
  }
}
