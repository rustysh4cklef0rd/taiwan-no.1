# MEMORY — Chinese Reading Widget

_Last updated: 2026-03-23_

## Project overview

Android home screen widget that shows 6 Traditional Chinese characters per day from a 1 000-word frequency list. The user is a fluent Mandarin speaker learning to READ characters, not vocabulary. TTS pronunciation is available in the foreground detail screen.

## Tech stack

| Concern | Package |
|---|---|
| Widget rendering | `home_widget ^0.6.0` |
| TTS | `flutter_tts ^4.2.0` |
| Persistence | `shared_preferences ^2.3.0` |
| Background scheduling | `workmanager ^0.5.2` |

Flutter SDK constraint: `^3.7.0`

## Word data

- File: `assets/data/words.json`
- 200 entries (representative subset of final 1 000-word list)
- Schema: `id`, `character`, `pinyin`, `meaning`, `phrase`, `phrase_pinyin`, `phrase_meaning`, `frequency_rank`

## Daily rotation formula

```
epochDay  = UTC days since 1970-01-01
startIdx  = (epochDay * 6) % totalWords
words     = list[startIdx .. startIdx+5]  (wrapping)
```

Deterministic and stateless — no DB needed. Full cycle with 200 words: 100 days (gcd(200,6)=2).

## Key files

| File | Purpose |
|---|---|
| `lib/main.dart` | Entry point; WorkManager init, first-run seed, route resolution, `HomeScreen`, `ChineseReadingApp` |
| `lib/models/word.dart` | `Word` model; `fromJson`/`toJson`/`toPrefsMap`/`fromPrefsMap` |
| `lib/services/word_service.dart` | `loadWordList`, `getTodaysWords`, `getProgress`, `checkTtsAvailability` |
| `lib/widget/background_callback.dart` | WorkManager callback (separate Dart isolate); writes to `home_widget` prefs; **no TTS, no UI** |
| `lib/screens/detail_screen.dart` | Character detail with TTS; receives `word_index` as route arg (int) |
| `lib/screens/settings_screen.dart` | Progress display + dark mode toggle via `ThemeModeNotifier` |
| `lib/screens/onboarding_screen.dart` | 2-page onboarding flow |
| `android/.../WordWidgetProvider4x2.kt` | 4×2 AppWidgetProvider (6 words) |
| `android/.../WordWidgetProvider2x2.kt` | 2×2 AppWidgetProvider (3 words, slots 0-2) |
| `android/.../MainActivity.kt` | Reads `word_index` from widget tap intent; writes to `FlutterHomeWidgetPlugin` prefs; notifies Flutter via `com.chinesewidget/widget_tap` MethodChannel |

## SharedPreferences keys (namespace: `FlutterHomeWidgetPlugin`)

- `word_N_char` / `word_N_pinyin` / `word_N_meaning` / `word_N_phrase` / `word_N_phrase_pinyin` / `word_N_phrase_meaning` / `word_N_id` — for N = 0..5
- `last_updated` — ISO 8601 timestamp of last widget data write
- `launch_word_index` — set by `MainActivity.kt` on widget tap; read by Flutter on startup to route to `/detail`
- `dark_mode` — bool, written by settings screen

## WorkManager task

- Name: `daily_word_update`
- Period: 24 hours, `ExistingWorkPolicy.keep`
- Background isolate must NOT use TTS or any method channel that requires main thread

## Routes

| Route | Screen |
|---|---|
| `/onboarding` | `OnboardingScreen` (first run) |
| `/home` | `HomeScreen` (6-word grid + settings) |
| `/detail` | `DetailScreen` (arg: `int` word index 0-5) |

## Widget layouts

| File | Usage |
|---|---|
| `widget_layout_4x2.xml` | 4×2 light |
| `widget_layout_4x2_night.xml` | 4×2 dark |
| `widget_layout_2x2.xml` | 2×2 light |
| `widget_layout_2x2_night.xml` | 2×2 dark |

Background drawables: `widget_background.xml`, `word_cell_background.xml` (and `_night` variants).

## Known limitations / future work

- Word list is 200 words; expand to 1 000 for production
- `targetCellWidth`/`targetCellHeight` in `widget_info_*.xml` requires API 31+; pre-31 devices use `minWidth`/`minHeight`
- WorkManager is not guaranteed to run at exact midnight on all OEMs (Doze mode)
- iOS widget support deferred to v2
- Mark-as-known, SRS, notifications — see `TODOS.md`
