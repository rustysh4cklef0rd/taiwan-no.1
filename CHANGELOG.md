# Changelog

## 2026-03-27 (README)

### Changed
- `README.md` — replaced Flutter boilerplate with full app description: features, word sets, tech stack, install instructions

## 2026-03-27

### Added
- `LICENSE` — proprietary all-rights-reserved notice
- Code watermarks embedded across four files for ownership verification

### Fixed
- Widget SharedPreferences key — all native Kotlin code now reads from `HomeWidgetPreferences` (matching what `home_widget` package writes); previously reading from wrong file `FlutterHomeWidgetPlugin`, causing widget never to update on day nav
- `FlashcardWidgetProvider`, `FlashcardWidget2x2Provider`, `UnlockReceiver`, `DailyWordWorker` — same `HomeWidgetPreferences` fix applied to all remaining providers
- `UnlockReceiver` now registered dynamically in `MainActivity.onCreate()` — `ACTION_USER_PRESENT` cannot be declared in static manifest; flashcard was never cycling on unlock
- `_WordTile` Stack uses `StackFit.expand` — tiles were different sizes because Stack gave loose constraints to child Container
- Dark mode text — explicit `onSurface` / `outline` overrides (`#F2E4DF` / `#CDB8B3`) for better contrast on `#2D2520` tile background
- Word rotation anchored to install date — `install_epoch_day` recorded on first launch; new installs always start from word 1 instead of mid-cycle based on epoch day
- `DESIGN.md` — removed local machine path comment that exposed Windows username

### Changed
- `.gitignore` — added `android/key.properties`, `android/.gradle/`, `design-mockup-*.html`, `plan-*.html`, `android/local.properties`

## 2026-03-26 (1250 words, 4 sets, font, widget alignment)

### Added
- `assets/data/words_set1–4.json` — 1,250 high-frequency Simplified Chinese characters (from CC-CEDICT frequency list), split into 4 sequential sets (~312 words each); pinyin uses tone diacritics
- `assets/fonts/Nunito-Regular/SemiBold/Bold.ttf` — Nunito font bundled as app asset (no network download required)
- `android/app/src/main/res/font/nunito.xml` — downloadable font descriptor for Android widget
- `android/app/src/main/res/values/font_certs.xml` + `preloaded_fonts.xml` — Google Fonts provider certs for widget font

### Changed
- `lib/services/word_service.dart` — word list now loads from 4 set files; `getTodaysWords` filters pool by `active_set`; new `getActiveSet`, `setActiveSet`, `getSetStats`, `canUnlockNextSet` methods
- `DailyWordWorker.kt` — loads from 4 set files with per-file error resilience; respects `active_set` from SharedPreferences
- `lib/screens/settings_screen.dart` — added "WORD SETS" section with per-set progress bars and unlock buttons; labels updated to "1,250 characters"
- `lib/main.dart` / `lib/screens/detail_screen.dart` — Nunito applied app-wide via `textTheme.apply(fontFamily: 'Nunito')`; `GoogleFonts.config.allowRuntimeFetching = false` prevents crashes in release builds; NotoSerifSC replaced with system serif for Chinese character display
- All 8 widget XML layouts — `android:fontFamily="@font/nunito"` on all TextViews; meaning TextViews changed from `gravity="center"` to `gravity="start"` (left-aligned for readability)
- `lib/screens/detail_screen.dart` — meaning text uses adaptive alignment: centered when it fits one line, left-aligned when it wraps
- `pubspec.yaml` — replaced `words.json`/`words_201_400.json`/`words_401_600.json` with 4 set files; declared Nunito font family

### Fixed
- `lib/main.dart` — stale-check `!=` fix (was `<`): widget words now re-pushed on both forward and backward day navigation
- `lib/screens/detail_screen.dart` — empty phrase guard shows "Example phrase coming soon" placeholder for words 601–1250; TTS falls back to character when phrase is empty

### Removed
- `assets/data/words.json`, `words_201_400.json`, `words_401_600.json` — replaced by 4 set files

## 2026-03-25 (widget/app word mismatch fix)

### Fixed
- `all 4 widget providers` — tap intent now sends `word_id` (stable word ID) instead of slot index; detail screen looks up word by ID in full word list, so tapping a widget card always opens the correct word regardless of how today's list was computed
- `MainActivity.kt` — reads `word_id` extra and stores as `launch_word_id`; `onNewIntent` also updated
- `lib/main.dart` — `_resolveInitialRoute` reads `launch_word_id`; `_pendingDetailWordId` carries it to the `/detail` route; home screen now uses `_launchWords` (in-memory cache set by `_pushTodaysWordsToWidget`) guaranteeing it always shows exactly the words pushed to the widget
- `lib/main.dart` — `_pushTodaysWordsToWidget` now writes `last_epoch_day` as a String (home_widget stores all values as strings; previous `putLong` was unreadable by Flutter, causing stale-check to always fire `DailyWordWorker` and overwrite words)
- `DailyWordWorker.kt` — `last_epoch_day` migrated from `putLong` to `putString` (with `remove()` first to clear legacy Long)
- All Kotlin stale checks — read `last_epoch_day` via `getString` with `ClassCastException` fallback for legacy Long values
- `lib/screens/detail_screen.dart` — `_loadWord` looks up word by ID in full word list instead of `getTodaysWords()[index]`
- `lib/services/word_service.dart` — added `getWidgetWords()` helper that reconstructs today's word list from widget SharedPreferences by ID

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
