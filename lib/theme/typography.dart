import 'package:flutter/material.dart';

/// App typography tokens — Nunito for UI, Noto Sans TC for CJK.
abstract class AppTypography {
  static const _fontFamily = 'Nunito';

  static const heading1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
    letterSpacing: -0.5,
  );

  static const heading2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.35,
    letterSpacing: -0.3,
  );

  static const bodyRegular = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const bodyDetail = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.6,
    letterSpacing: 0.1,
  );

  static const labelUi = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.2,
  );

  static const caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    letterSpacing: 0.3,
  );
}

/// CJK character display styles — embedded Noto Sans TC.
abstract class CjkStyle {
  static const _fontFamily = 'NotoSansTC';

  static const characterLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 112,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );

  static const characterQuiz = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 120,
    fontWeight: FontWeight.w500,
    height: 1.0,
  );

  static const characterTile = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 52,
    height: 1.0,
  );

  static const characterPhrase = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  static const appTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 32,
    letterSpacing: 4,
  );
}
