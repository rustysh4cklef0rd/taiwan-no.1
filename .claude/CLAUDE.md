# Chinese Learning Widget

Flutter Android app + home-screen widget for daily Traditional Chinese character practice.

## Tech Stack
- Flutter (Dart) + Android native (Kotlin)
- home_widget, workmanager, flutter_tts, shared_preferences
- Riverpod + Drift SQLite (v1.2+)

## Word ID Ranges
Set 1 = 1-312, Set 2 = 313-625, Set 3 = 626-937, Set 4 = 938-1250

## Architecture
- **Word pool**: 1,250 words across 4 sets in `assets/data/words_set1-4.json`
- **Daily rotation**: 6 words/day anchored to `install_epoch_day`; recognized words excluded
- **Day rollover**: local device time (NOT UTC)
- **Today's word IDs**: stored in prefs as `today_word_ids_<epochDay>`
- **Widget push**: `pushTodaysWordsToWidget()` in main.dart; also `WordService.pushStoredWordsToWidget()` for mid-day updates
- **Word drain order**: `getTodaysWords` priority is SRS words → unmaster queue → rotation (wrong order = wrong daily words)
- **Launch cache**: `_launchWords` / `_launchWordsDay` in main.dart — call `invalidateLaunchCache()` after any mid-day word list change or app shows stale words
- **AppLifecycleObserver**: on resume, calls `tapProvider.notifier.refresh()` + invalidates `todaysWordsProvider` — don't remove or streaks/daily words won't update

## State Management (Riverpod + Drift)
- `AppDatabase` in `lib/db/app_database.dart` — Taps table (id, wordId, tappedAt)
- `TapRepository` — heatmap, streak, today tap count, bulk insert
- Providers in `lib/providers/app_providers.dart`:
  - `appDatabaseProvider`, `tapRepositoryProvider`
  - `appSettingsProvider` — dark mode, quiz mode, hide pinyin, day offset
  - `tapProvider` — heatmap, streak, today count; `optimisticRecordTap(wordId)`
  - `writeQueueProvider` — 3-second batched SQLite writes
  - `todaysWordsProvider` — today's 6 words

## One-time Migration
On first launch after upgrade, `_migrateTapData()` reads legacy SharedPreferences into SQLite. Flag: `tap_migration_v1_complete`.

## Screens
- HomeScreen — word tile grid, streak pill, PopScope back nav
- DetailScreen — large char, pinyin, meaning, phrase card, TTS, quiz
- SettingsScreen — word sets, dark mode, streak, heatmap
- OnboardingScreen — first-run
- MasteredWordsScreen — mastered words with Unmaster

## Recognition System
- `recognized_ids` in SharedPreferences — comma-separated
- `replaceWordInToday(wordId)` — swaps recognized word for fresh one
- Unmaster priority queue: `unmaster_queue` in SharedPreferences

## Android Widgets
- 4 providers: WordWidgetProvider4x2, 2x2, FlashcardWidgetProvider, Flashcard2x2
- All read from `HomeWidgetPreferences` — `last_epoch_day` MUST be stored as String (not Long — legacy Long caused ClassCastException crash)
- DailyWordWorker.kt — native Kotlin fallback at midnight
- UnlockReceiver — cycles flashcard on phone unlock. MUST be dynamically registered in `MainActivity.onCreate()` — `ACTION_USER_PRESENT` cannot go in static AndroidManifest (silently stops working)
- Flashcard slot = `(currentTimeMillis / 1_200_000L) % 6` (20-min blocks)

## Button Design System (v1.2.1)
- Stroke: 1.5px, Glow: dual-layer BoxShadow (alpha 71/41)
- Next Day: NeonColors.pink, Neon switches matched, Unlock Set radius: 10px

## Zen Garden Redesign (approved 2026-03-28)
- Earth-tone palette: Parchment #FAF7F2, Stone #E8E0D5, Moss #3D5A3E, Clay #B85C3A
- Stone-shaped tiles, plant growth streaks, bamboo-frame phrase cards
- Keep existing Nunito + system serif fonts — NO new font deps (NotoSerifSC was removed — it caused crashes)
- Design mockup: `design-example-3-zen-garden.html`
- Full plan: `plan-zen-garden-redesign-2026-03-28.html`

## GitHub
- Private: UBFSJARVIS account (origin)
- Public: rustysh4cklef0rd account (public remote, SSH alias `github-public`)
- Commits use: `271448119+rustysh4cklef0rd@users.noreply.github.com`
- History rewritten with git filter-branch to scrub real email — do NOT rebase or re-filter naively

## Code Watermarks (DO NOT DELETE)
IP ownership proof constants embedded in code:
- `DailyWordWorker.kt`: `SCHEDULE_REF = 826`
- `FlashcardWidgetProvider.kt`: `PROVIDER_REF = 315`
- `lib/services/word_service.dart`: `_kServiceRef = 306`
- `widget_layout_4x2.xml`: comment `Build ref: 0111.`

## License
Proprietary all-rights-reserved. No copying/distribution.

## Tests
- `test/word_service_behavior_test.dart` — 60 tests

## Pending
- Debug page labels ([1]-[5]) still in app — remove before release
- Android SDK/NDK: flutter_tts requires compileSdk=36 and NDK 27.0.12077973
