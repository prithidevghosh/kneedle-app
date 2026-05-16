/// Single source of truth for which speech-to-text backend the app uses.
///
/// The default platform recognizer (`speech_to_text` package) wraps Android's
/// `SpeechRecognizer` / iOS's `SFSpeechRecognizer`. With `onDevice: true` it
/// stays offline IF the user has installed the system's offline speech pack
/// — which is gated by Google Settings on Android and not under our control.
///
/// [VoskSttService] is a fully self-contained alternative: it downloads its
/// own ~50 MB acoustic model on first launch (same flow as the Gemma weights)
/// and never touches the network again. Flip [kUseVoskStt] to true to route
/// every voice-capture call site through it; the existing platform-recognizer
/// code in [VoiceService] is left intact and dormant when the flag is on.
///
/// This is a deliberate compile-time constant rather than a runtime setting:
/// the wiring of two parallel STT engines is non-trivial and we want the
/// dead path to be tree-shaken in release builds.
const bool kUseVoskStt = false;

/// Vosk acoustic model used when [kUseVoskStt] is true.
///
/// `vosk-model-small-en-us-0.15` is ~40 MB compressed / ~50 MB on disk and
/// runs comfortably in real time on mid-range Android. For better accuracy
/// at the cost of size, swap in `vosk-model-en-us-0.22` (~1.8 GB) from
/// https://alphacephei.com/vosk/models/model-list.json.
const String kVoskModelUrl =
    'https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip';

/// Sample rate the recognizer is created with. Vosk's small English models
/// are trained on 16 kHz audio — using a different rate will silently degrade
/// transcription quality.
const int kVoskSampleRate = 16000;
