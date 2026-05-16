# Kneedle

**On-device AI companion for knee osteoarthritis — powered by Gemma 4 E2B.**

> I built this for my mom.
>
> She has knee osteoarthritis. The grim part isn't the pain itself — it's
> the in-between. Forgetting which day the pain spiked. Not knowing if her
> walk is getting worse or if she's imagining it. Sitting in front of the
> doctor and going blank when asked *"how has it been since last time?"*.
> Hesitating to "bother" the physio with a question between visits.
>
> Kneedle is the small, kind thing I wished she had in her pocket — a
> companion that listens, remembers, watches her walk, and quietly tells the
> story her knees can't. It runs entirely on her phone because her pain is
> hers, not training data.
>
> If it helps one more mom, dad, or anyone hurting — that's the whole point.

Kneedle is a Flutter app that helps people living with knee OA track pain,
test their gait, follow guided exercises, and produce a clinical-style PDF
for their physiotherapist or doctor — all running entirely on the phone,
with no servers, no accounts, and no network calls after the initial model
download.

The whole reasoning loop — natural-language understanding, function calling,
multimodal gait analysis, and the chat that lets you ask follow-up questions
about your own results — is handled by a quantised Gemma 4 E2B model
loaded through `flutter_gemma` / LiteRT.

---

## 📱 Download the APK

Latest signed Android build: **[Download from GitHub Releases →](https://github.com/prithidevghosh/kneedle-app/releases/latest)**

> First launch downloads the Gemma 4 E2B weights (~1.5 GB) over Wi-Fi.
> Everything after that runs offline. Android 10+ recommended, 8 GB RAM
> for the smoothest gait analysis.

---

## Why on-device

- **Privacy.** Pain transcripts, gait videos, and prescriptions never leave
  the phone. Hive is the only persistence layer.
- **Works offline.** Once the model and (optionally) the Vosk speech pack
  are downloaded, the app runs anywhere — clinic, home, plane.
- **Cost.** No API spend, no rate limits, no per-user inference fees.

---

## Features

### "Hey Kneedle" voice agent
Tap one button, say what you want. The agent (`lib/screens/agent_screen.dart`)
runs an utterance through STT → Gemma → function calls → TTS reply. A single
sentence can chain through several tools:

- `record_pain_entry({ pain_score, location, context })`
- `schedule_reminder({ title, body, in_minutes })`
- `add_medication`, `add_appointment`, list-query tools
- Navigation intents: `start_gait_test`, `show_history`, `generate_doctor_report`

### Gait check (8-second walk test)
[lib/screens/gait_capture_screen.dart](lib/screens/gait_capture_screen.dart) +
[lib/gait/pipeline.dart](lib/gait/pipeline.dart)

1. Two 8-second clips — **frontal** (walking toward the camera) and
   **sagittal** (walking past it).
2. Google ML Kit BlazePose extracts 33 keypoints per frame **inline** in the
   camera image stream — no JPEG round-trip, no temp files.
3. A worker-isolate pipeline ([lib/services/gait_service.dart](lib/services/gait_service.dart))
   computes:
   - Left / right knee flexion angles + diff
   - Symmetry score (0–100)
   - Trunk lean angle + direction, anterior trunk lean
   - Cadence (steps per minute)
   - Stride-time asymmetry
   - KL-proxy grade (`kl_0` → `kl_3`) from the dual-video signal
4. Four representative JPEG snapshots (2 per view, mid-stride) plus the
   metrics are handed to Gemma's multimodal endpoint, which returns a
   structured `AnalysisResponse` (severity, observations, exercise plan,
   plain-language guidance).
5. The full session is persisted via Hive and re-openable from the
   Insights tab without re-running inference.

**Three ways to start recording** on the gait screen:
- Tap the on-screen **Start** button
- Say **"kneedle, start recording"** (offline STT wake phrase)
- Click a paired **Bluetooth selfie-stick remote** — handled by the native
  Android `dispatchKeyEvent` hook in [android/.../MainActivity.kt](android/app/src/main/kotlin/com/example/kneedle/MainActivity.kt),
  which forwards Volume Up / Down / Camera / Media keys to Dart via an
  EventChannel and swallows the keys so the system volume HUD doesn't
  appear mid-capture.

### Gait result + follow-up chat
[lib/screens/gait_result_screen.dart](lib/screens/gait_result_screen.dart),
[lib/screens/gait_chat_screen.dart](lib/screens/gait_chat_screen.dart)

After analysis the results screen shows the metrics, severity, observations,
and a per-exercise plan with YouTube demo thumbnails (opened externally —
embedded playback is blocked by many physio channels).

A pinned **chat session** loads the analysis JSON into Gemma's system prompt
so questions like *"What does my symmetry score mean?"* or
*"मेरा घुटना अभी कैसा है?"* are answered against the patient's own results,
not generic OA small-talk.

### Voice pain journal
[lib/screens/pain_journal_screen.dart](lib/screens/pain_journal_screen.dart)

Tap the mic, describe the pain in your own words. Gemma extracts a
`PainEntry { painScore 0–10, location, context, timestamp }` via function
calling and persists it to Hive.

### Reminders & medications
[lib/screens/reminders_screen.dart](lib/screens/reminders_screen.dart) +
[lib/services/notification_service.dart](lib/services/notification_service.dart)

Voice-driven medication and appointment management. Backed by
`flutter_local_notifications` with the Android `FLAG_INSISTENT` flag so
medication alarms behave like real alarms rather than a passive ping.

### Voice-coached exercise sessions
[lib/screens/exercise_coach_screen.dart](lib/screens/exercise_coach_screen.dart)

A periodic timer paces the user one rep at a time, TTS announces each
count, and completed sessions feed adherence into the doctor PDF.

### Doctor report (PDF)
[lib/services/pdf_service.dart](lib/services/pdf_service.dart)

Generates a clinician-formatted PDF (header, patient block, clinical
impression, objective measures table with reference ranges, observations,
pain trajectory, exercise adherence, recommendations) from local Hive data
and shares it via `share_plus`.

### Safety: red-flag detection
[lib/clinical/red_flags.dart](lib/clinical/red_flags.dart) +
[lib/screens/red_flag_screen.dart](lib/screens/red_flag_screen.dart)

Three tiers:
- **urgent** — full-screen interstitial with a "Call doctor" CTA
  (OARSI / NICE rules: severe pain + inability to bear weight, sudden
  swelling + fever, etc).
- **soon** — persistent advisory chip (rising-pain trend over 3 entries,
  severe gait + high asymmetry).
- **watch** — logged for the PDF, mentioned softly in the agent's reply.

### Grounded clinical chat (RAG-lite)
A bundled OA-guideline knowledge base (`assets/kb/oa_guidelines.json`) is
indexed at startup ([lib/kb/kb_index.dart](lib/kb/kb_index.dart)) with a
small BM25 build. Companion replies cite passages from this KB rather than
inventing references.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                          Flutter UI                              │
│   Today · Journal · Reminders · Insights · Report (bottom-nav)   │
└──────────────────────────────────────────────────────────────────┘
                │
                ▼
┌──────────────────────────────────────────────────────────────────┐
│                     Riverpod providers                           │
│  (gemmaServiceProvider, voiceServiceProvider, gaitServiceProvider│
│   + Hive view providers)                                         │
└──────────────────────────────────────────────────────────────────┘
                │
   ┌────────────┼─────────────┬──────────────┬───────────────┐
   ▼            ▼             ▼              ▼               ▼
┌──────┐  ┌──────────┐  ┌──────────┐   ┌────────────┐  ┌─────────┐
│Voice │  │  Gemma   │  │  Gait    │   │ Storage    │  │  Notif. │
│ STT  │  │ (LiteRT, │  │ pipeline │   │  (Hive)    │  │  (local │
│ TTS  │  │   INT4)  │  │ (isolate)│   │            │  │ alarms) │
└──────┘  └──────────┘  └──────────┘   └────────────┘  └─────────┘
                │             │
                │             ▼
                │       ┌──────────────┐
                │       │ ML Kit Pose  │
                │       │  (BlazePose) │
                │       └──────────────┘
                ▼
       ┌────────────────────┐
       │ KB index (BM25)    │
       │ assets/kb/*.json   │
       └────────────────────┘
```

### The Gemma engine gate

LiteRT-LM allows **one** `generateChatResponse` in flight per process across
*all* `InferenceChat` objects (companion, gait analysis, gait follow-up
chat). Every entry point chains through `GemmaService.runOnEngine`, which
serialises calls behind a static `Future` gate and applies a 90-second
timeout so a stuck native call surfaces fast instead of hanging silently.
See [lib/services/gemma_service.dart](lib/services/gemma_service.dart) for
the rationale.

### Why Gemma 4 E2B specifically

INT4-quantised E2B is ~1.5 GB resident — leaves headroom for the camera
preview, ML Kit pose, and the Flutter engine on an 8 GB device. E4B (~5 GB)
does not. The model URL is pinned to a pre-MTP revision because newer
multi-signature vision encoders aren't yet loadable on the bundled
Android LiteRT-LM runtime (see the pinned hash + comment in
[lib/services/gemma_service.dart](lib/services/gemma_service.dart)).

### `flutter_gemma` pin

`flutter_gemma` is pinned to `0.15.0`. `0.15.1` bumps the native LiteRT
runtime to v0.11.0-b, which made the GPU/OpenCL command queue much more
sensitive to other clients (camera, ML Kit pose) and broke multimodal gait
analysis with `CL_INVALID_COMMAND_QUEUE (-36)` mid-decode. Revisit once
upstream stabilises that runtime.

---

## Project layout

```
lib/
├─ main.dart                    # FlutterGemma.init, Hive, KB, gait isolate boot
├─ app.dart                     # Splash + bootstrap + RootShell
├─ clinical/                    # Severity, red flags, safety defaults, prompts
├─ core/theme.dart              # Sage/cream palette, spacing, radii
├─ data/exercise_library.dart   # Reference exercise catalog + YouTube demos
├─ gait/                        # Pose → metrics pipeline (frontal + sagittal)
│   ├─ pipeline.dart            # Top-level entry, GaitMetrics dataclass
│   ├─ frontal.dart, sagittal.dart, temporal.dart
│   ├─ knee_phase.dart, heel_strike.dart, kl_score.dart
│   └─ frame_jpeg.dart          # CameraImage → JPEG snapshots for Gemma
├─ kb/                          # BM25 retriever over OA guideline corpus
├─ models/                      # Hive-adapted: PainEntry, GaitSession, ...
├─ providers/providers.dart     # Riverpod wiring
├─ screens/                     # One file per top-level surface
├─ services/
│   ├─ gemma_service.dart       # All LLM entry points + engine gate
│   ├─ gait_service.dart        # Worker-isolate gait analyser
│   ├─ voice_service.dart       # STT + TTS orchestration
│   ├─ vosk_stt_service.dart    # Optional offline-only STT
│   ├─ stt_config.dart          # Compile-time STT backend switch
│   ├─ notification_service.dart
│   ├─ pdf_service.dart         # Clinician-style assessment PDF
│   ├─ shutter_button_service.dart  # BT selfie-stick remote bridge
│   └─ storage_service.dart     # Hive bootstrap + queries
└─ widgets/                     # Shared k_* primitives (cards, mic, segmented)

android/app/src/main/kotlin/com/example/kneedle/MainActivity.kt
   # dispatchKeyEvent override — Bluetooth shutter remote → EventChannel

assets/
├─ kb/oa_guidelines.json        # RAG corpus
└─ prompts/companion_system.txt # Base system prompt for the chat path
```

---

## Getting started

### Prerequisites
- Flutter `>=3.22.0`, Dart `>=3.4.0 <4.0.0`
- A real Android device (the gait pipeline needs a camera and the GPU
  delegate; the emulator works for non-gait screens but is slow)
- ~2 GB of free storage for the Gemma weights + (optional) Vosk model
- A Hugging Face account is **not** required — the LiteRT-LM bundles used
  are public reads

### Run

```bash
flutter pub get
flutter run
```

First launch will:
1. Download the Gemma 4 E2B LiteRT bundle (~1.5 GB). A progress bar is
   shown on the splash screen.
2. Initialise Hive, the OA-guidelines BM25 index, and the gait worker
   isolate.

Subsequent launches are fully offline.

### Switching the STT backend
Default is the platform recognizer (`speech_to_text` package, on-device
mode when the OS speech pack is installed). To use the fully self-contained
Vosk engine instead:

```dart
// lib/services/stt_config.dart
const bool kUseVoskStt = true;
```

Adds a ~50 MB acoustic model download on first launch; removes any
dependency on Google's offline speech pack.

---

## Permissions

Android `AndroidManifest.xml` requests:

- `CAMERA` — gait capture
- `RECORD_AUDIO` — voice agent, pain journal, gait wake phrase
- `INTERNET` — first-launch model download only
- `POST_NOTIFICATIONS` (Android 13+) — medication / appointment alarms
- `SCHEDULE_EXACT_ALARM` — alarm-style insistent reminders

iOS Info.plist mirrors the equivalents (`NSCameraUsageDescription`,
`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).

---

## Privacy

Everything in the app — pain transcripts, gait videos and pose data,
medication lists, generated PDFs — is stored in Hive in the app's private
storage. There is no cloud backend, no analytics SDK, and no account.
The only network traffic the app generates is:

1. The initial Gemma weights download (Hugging Face).
2. The optional first-launch Vosk model download (alphacephei.com), if the
   Vosk STT path is enabled.
3. Tapping a YouTube exercise demo opens the external YouTube app or
   browser — Kneedle itself does not embed playback.

---

## Disclaimer

Kneedle is a **companion tool**, not a medical device. It does not
diagnose, treat, or prescribe. The red-flag detection is a heuristic
safety net, not a substitute for professional triage. Always defer to
your physiotherapist or doctor.
