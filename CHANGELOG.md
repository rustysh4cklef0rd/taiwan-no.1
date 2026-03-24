# Changelog

## 2026-03-24 (QA)

### Fixed
- `lib/main.dart` — `_pushTodaysWordsToWidget` now triggers update for all 4 widget providers (was missing flashcard widgets, causing "…" on first install until WorkManager ran)
- `MainActivity.kt`, `WordWidgetProvider4x2.kt`, `WordWidgetProvider2x2.kt`, `FlashcardWidgetProvider.kt`, `FlashcardWidget2x2Provider.kt` — all stale-check `enqueue()` calls replaced with `enqueueUniqueWork("daily_word_immediate", KEEP)` to prevent duplicate concurrent workers

### Reverted
- `DailyWordWorker.kt` + `lib/main.dart` — removed `+1 day` preview offset; app now pushes today's words as intended

## 2026-03-23 (implementation)

### Added
- `pubspec.yaml` — added `home_widget ^0.6.0`, `flutter_tts ^4.2.0`, `shared_preferences ^2.3.0`, `workmanager ^0.5.2`; registered `assets/data/words.json`
- `assets/data/words.json` — 200 high-frequency Traditional Chinese words with all schema fields
- `lib/models/word.dart` — `Word` model with `fromJson`/`toJson`/`toPrefsMap`/`fromPrefsMap`
- `lib/services/word_service.dart` — `loadWordList`, `getTodaysWords` (epoch-day formula), `getProgress`, `checkTtsAvailability`
- `lib/widget/background_callback.dart` — WorkManager background isolate; writes words to `home_widget` SharedPreferences, triggers widget redraw; no TTS/UI
- `lib/screens/onboarding_screen.dart` — 2-page onboarding (confirm script + widget setup instructions)
- `lib/screens/detail_screen.dart` — large character (96sp), pinyin, meaning, phrase card, TTS speaker button with graceful fallback
- `lib/screens/settings_screen.dart` — day/cycle progress bar + dark mode toggle
- `lib/main.dart` — app entry point; WorkManager init, first-run seeding, daily schedule, route resolution, `HomeScreen`, `ChineseReadingApp`
- `android/.../WordWidgetProvider4x2.kt` — 4×2 AppWidgetProvider; reads SharedPreferences, sets RemoteViews, tap PendingIntents
- `android/.../WordWidgetProvider2x2.kt` — 2×2 AppWidgetProvider (3 words)
- `android/.../MainActivity.kt` — reads `word_index` intent extra, writes to HomeWidget prefs, forwards to Flutter via MethodChannel
- `android/.../AndroidManifest.xml` — registers both AppWidgetProviders, WorkManager, HomeWidget background receiver
- `android/.../res/layout/widget_layout_4x2.xml` + `_night.xml` — 4×2 light/dark widget layouts
- `android/.../res/layout/widget_layout_2x2.xml` + `_night.xml` — 2×2 light/dark widget layouts
- `android/.../res/xml/widget_info_4x2.xml` + `widget_info_2x2.xml` — AppWidgetProviderInfo descriptors
- `android/.../res/drawable/` — 4 shape drawables for widget backgrounds (light + night)
- `android/.../res/values/strings.xml` — app name + widget description strings
- `test/word_service_test.dart` — unit tests for `Word.fromJson`, prefs map round-trip, epoch-day formula, wrap-around, cycle repeat

## 2026-03-23

### Added
- `DESIGN.md` — fully reviewed product design doc (via /office-hours + /autoplan)
  - Flutter + home_widget stack chosen
  - Word list: subtitle frequency corpus (SUBTLEX-CH), 1,000 Traditional Chinese entries
  - 4×2 and 2×2 widget sizes
  - Minimal/clean aesthetic (Noto Serif CJK TC, white/dark backgrounds)
  - Complete word entry schema (character, pinyin, meaning, phrase, phrase_pinyin, phrase_meaning)
  - Architecture diagrams: background update flow, tap-to-detail flow
  - TTS availability handling + graceful fallback
  - 18-path test plan
- `TODOS.md` — deferred features (iOS v2, mark-as-known, SRS, notifications)
