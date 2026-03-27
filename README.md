# Chinese Reading Widget

An Android app for building a daily Simplified Chinese reading habit — one character at a time, right on your home screen.

## What it does

Six high-frequency Chinese characters appear on your home screen every day via an Android widget. Tap any character to open a full detail screen with pinyin, English meaning, an example phrase, and a text-to-speech button. A new set of 6 characters rotates in each day, anchored to your install date so day 1 always starts from the beginning.

## Features

- **4 home screen widget sizes** — 4×2 (6 words), 2×2 (3 words), flashcard full-detail, compact flashcard
- **Flashcard widget** — cycles through today's 6 words automatically every 20 minutes and on each phone unlock
- **1,250 words** across 4 progressive sets, unlocked as you master each set (80% threshold)
- **Spaced repetition** — words you get wrong in the quiz resurface in future daily sets
- **Quiz mode** — test yourself on today's words; results feed back into the rotation
- **Streak tracking** — daily study streak with longest-streak record
- **Heatmap** — visual calendar of your review activity
- **Dark mode** — toggle in settings, widget respects your preference
- **TTS** — native text-to-speech for every character (falls back gracefully if Chinese TTS not installed)
- **Offline** — all 1,250 words bundled in the app, no internet required

## Word sets

| Set | Characters | IDs |
|-----|-----------|-----|
| 1 | 312 | 1–312 |
| 2 | 313 | 313–625 |
| 3 | 312 | 626–937 |
| 4 | 313 | 938–1,250 |

Words are sourced from the CC-CEDICT high-frequency Simplified Chinese corpus. Each entry includes: character, pinyin (tone diacritics), English meaning, example phrase, phrase pinyin, and phrase meaning.

## Tech stack

- **Flutter** (Dart) — UI, word logic, settings
- **Android native Kotlin** — AppWidgetProvider for all 4 widget variants, WorkManager daily refresh
- **home_widget** — bridge between Flutter and Android widgets
- **workmanager** — background midnight word refresh without requiring the app to be open
- **flutter_tts** — Chinese text-to-speech
- **Nunito** — bundled font for consistent widget and app typography

## Screenshots

_Coming soon_

## Installation

This app is not on the Play Store. To install:

1. Build the APK: `flutter build apk --release`
2. Transfer `build/app/outputs/flutter-apk/app-release.apk` to your Android device
3. Enable **Install from unknown sources** for your file manager in Android settings
4. Tap the APK to install

## License

Copyright (c) 2026 rustysh4cklef0rd. All rights reserved. See [LICENSE](LICENSE) for details.
