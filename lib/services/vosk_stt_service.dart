import 'dart:async';
import 'dart:convert';

import 'package:vosk_flutter_service/vosk_flutter.dart';

import 'stt_config.dart';

/// Offline speech-to-text powered by Vosk. This is the alternative backend
/// to [VoiceService]'s default `speech_to_text` path; it ships its own
/// acoustic model so it works without Google's offline speech pack.
///
/// Singleton because the underlying [VoskFlutterPlugin], [Model], [Recognizer]
/// and [SpeechService] all hold native resources. Recreating them per call
/// would re-download the model and re-allocate ~50 MB of decoder state.
///
/// Two usage shapes mirror what [VoiceService] exposes:
///
///   * [captureUtterance] — one-shot recording that auto-stops when the
///     recognizer reports a final result or [listenFor] elapses.
///   * [startManualSession] / [stopAndCollect] — long-form recording that
///     stays open until the caller chooses to stop, used for the gait-chat
///     dictation flow where older users pause mid-sentence.
///
/// Enable via [kUseVoskStt] in `stt_config.dart`.
class VoskSttService {
  VoskSttService._();
  static final VoskSttService instance = VoskSttService._();

  // Lazily-bound natives. None of these survive a [dispose]; init() rebuilds
  // them on demand so the model isn't loaded into memory until the user
  // actually invokes a voice flow.
  // _model and _recognizer are referenced only for ownership — the native
  // SpeechService holds raw pointers into both, so the Dart wrappers must
  // outlive it or the natives get GC'd out from under us.
  // ignore: unused_field
  Model? _model;
  // ignore: unused_field
  Recognizer? _recognizer;
  SpeechService? _speech;

  // Per-session bookkeeping. The speech-service streams are broadcast, so
  // we keep one subscription per active capture and tear it down when the
  // capture ends — leaking a subscription would deliver the next session's
  // partials into the wrong completer.
  StreamSubscription<String>? _resultSub;
  StreamSubscription<String>? _partialSub;

  bool _ready = false;
  Future<void>? _initFuture;

  /// Whether the model is loaded and the recognizer is ready to capture
  /// audio. Cheap to call — does not trigger initialisation.
  bool get isReady => _ready;

  /// Download (first launch only) the Vosk model, then build a recognizer
  /// and speech service against it. Subsequent calls are no-ops. Safe to
  /// invoke from multiple call sites concurrently — the [_initFuture] guard
  /// collapses overlapping inits into a single one.
  Future<void> init() async {
    if (_ready) return;
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    try {
      // `loadFromNetwork` is idempotent — it skips the download when the
      // unzipped model is already on disk, so this is effectively free on
      // every launch after the first.
      final modelPath =
          await ModelLoader().loadFromNetwork(kVoskModelUrl);
      final vosk = VoskFlutterPlugin.instance();
      final model = await vosk.createModel(modelPath);
      final recognizer = await vosk.createRecognizer(
        model: model,
        sampleRate: kVoskSampleRate,
      );
      final speech = await vosk.initSpeechService(recognizer);
      _model = model;
      _recognizer = recognizer;
      _speech = speech;
      _ready = true;
    } catch (e) {
      // Leave _ready=false so a retry can pick the failure up cleanly.
      _initFuture = null;
      rethrow;
    }
  }

  /// One-shot capture: starts the mic, returns as soon as Vosk emits a
  /// final result (silence-triggered on its side) or [listenFor] elapses,
  /// whichever comes first. Returns the trimmed transcript; empty when the
  /// user said nothing.
  Future<String> captureUtterance({
    Duration listenFor = const Duration(seconds: 20),
  }) async {
    await init();
    final completer = Completer<String>();
    var lastPartial = '';

    await _resultSub?.cancel();
    await _partialSub?.cancel();
    _resultSub = _speech!.onResult().listen((raw) {
      // Vosk emits each result as `{"text": "..."}`. Anything not parseable
      // is treated as the literal string — defensive fallback for older
      // model builds that didn't always wrap in JSON.
      final text = _extractText(raw, key: 'text');
      if (text.trim().isEmpty) return;
      if (!completer.isCompleted) completer.complete(text);
    });
    _partialSub = _speech!.onPartial().listen((raw) {
      lastPartial = _extractText(raw, key: 'partial');
    });

    final timeout = Timer(listenFor, () {
      if (!completer.isCompleted) completer.complete(lastPartial);
    });

    await _speech!.start();
    try {
      final transcript = await completer.future;
      return transcript.trim();
    } finally {
      timeout.cancel();
      await _speech!.stop();
      await _resultSub?.cancel();
      await _partialSub?.cancel();
      _resultSub = null;
      _partialSub = null;
    }
  }

  // ── Manual long-form capture ──────────────────────────────────────────
  //
  // Mirrors VoiceService.startListening / stopAndCollect. The transcript is
  // assembled across many partials + finals because Vosk emits a final
  // every time it detects a sentence boundary, then resets and continues.

  final StringBuffer _manualCommitted = StringBuffer();
  String _manualPartial = '';
  Completer<String>? _manualCompleter;

  bool get isManualListening => _manualCompleter != null;

  /// Begin a long-form capture. The transcript keeps appending until
  /// [stopAndCollect] is called. Subsequent calls without stopping reset
  /// the buffer — matches VoiceService's "one session at a time" contract.
  Future<void> startManualSession() async {
    await init();
    if (isManualListening) {
      // Already running. Reset would lose the in-flight transcript; treat
      // as a no-op the same way VoiceService does.
      return;
    }
    _manualCommitted.clear();
    _manualPartial = '';
    _manualCompleter = Completer<String>();

    await _resultSub?.cancel();
    await _partialSub?.cancel();
    _resultSub = _speech!.onResult().listen((raw) {
      final text = _extractText(raw, key: 'text');
      if (text.trim().isEmpty) return;
      if (_manualCommitted.isNotEmpty) _manualCommitted.write(' ');
      _manualCommitted.write(text.trim());
      _manualPartial = '';
    });
    _partialSub = _speech!.onPartial().listen((raw) {
      _manualPartial = _extractText(raw, key: 'partial');
    });
    await _speech!.start();
  }

  /// Stop the manual session and return everything heard so far. Safe to
  /// call when no session is running — returns the empty string.
  Future<String> stopAndCollect() async {
    final completer = _manualCompleter;
    if (completer == null) return '';
    _manualCompleter = null;
    try {
      await _speech!.stop();
    } catch (_) {/* best-effort */}
    // Flush any trailing partial that wasn't promoted to a final by Vosk's
    // internal silence detector before we stopped.
    final tail = _manualPartial.trim();
    if (tail.isNotEmpty) {
      if (_manualCommitted.isNotEmpty) _manualCommitted.write(' ');
      _manualCommitted.write(tail);
    }
    await _resultSub?.cancel();
    await _partialSub?.cancel();
    _resultSub = null;
    _partialSub = null;
    final out = _manualCommitted.toString().trim();
    if (!completer.isCompleted) completer.complete(out);
    return out;
  }

  /// Cancel a pending manual session without collecting. Used when the
  /// caller wants to abort (eg. user navigated away mid-recording).
  Future<void> cancel() async {
    try {
      await _speech?.cancel();
    } catch (_) {/* best-effort */}
    await _resultSub?.cancel();
    await _partialSub?.cancel();
    _resultSub = null;
    _partialSub = null;
    final completer = _manualCompleter;
    _manualCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete('');
  }

  /// Release every native resource. Call from app teardown; subsequent
  /// captures will re-init transparently.
  Future<void> dispose() async {
    await cancel();
    try {
      await _speech?.dispose();
    } catch (_) {/* best-effort */}
    _speech = null;
    _recognizer = null;
    _model = null;
    _ready = false;
    _initFuture = null;
  }

  /// Pull `text` (final) or `partial` (interim) out of Vosk's JSON envelope.
  /// Falls back to the raw string when JSON parsing fails so a malformed
  /// frame doesn't drop the user's utterance entirely.
  static String _extractText(String raw, {required String key}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final v = decoded[key];
        if (v is String) return v;
      }
    } catch (_) {/* fall through */}
    return raw;
  }
}
