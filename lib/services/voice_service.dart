import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/analysis_response.dart';
import 'gemma_service.dart';

/// One full cycle of the voice loop:
///   `mic → text → Gemma → text → speaker`
class VoiceTurn {
  const VoiceTurn({required this.transcript, required this.reply});
  final String transcript;
  final String reply;
}

/// Orchestrates `speech_to_text → GemmaService → flutter_tts`.
/// All three pieces are on-device; the loop never touches the network.
class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  Future<void> init({String localeId = 'en_US'}) async {
    if (_ready) return;
    final ok = await _stt.initialize(
      onError: (e) {
        // ignore: avoid_print
        print('[VoiceService] stt error: $e');
        // Some Android engines fire `error_no_match` / `error_speech_timeout`
        // when the recognizer hits its internal silence cap. Only treat this
        // as a leg end if the recognizer had actually started listening.
        if (_legActuallyStarted) _maybeRestartManual();
      },
      onStatus: (status) {
        // Statuses: 'listening' / 'notListening' / 'done'. We only consider a
        // leg ended if we previously saw 'listening' — otherwise an initial
        // 'notListening' (the platform's pre-listen idle state) would trigger
        // a restart loop that races the first words of the user's utterance.
        // ignore: avoid_print
        print('[VoiceService] stt status: $status');
        if (status == 'listening') {
          _legActuallyStarted = true;
        } else if ((status == 'notListening' || status == 'done') &&
            _legActuallyStarted) {
          _legActuallyStarted = false;
          _maybeRestartManual();
        }
      },
    );
    if (!ok) {
      throw StateError('Speech recognition unavailable on this device.');
    }
    await _tts.setLanguage(localeId.replaceAll('_', '-'));
    await _tts.setSpeechRate(0.45);
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  /// Records one user utterance, sends it to Gemma using the journal-extraction
  /// flow (function calling), speaks the reply, returns the [VoiceTurn].
  ///
  /// [pauseFor] / [listenFor] match SpeechToText's defaults but are tuned for
  /// elderly users who pause longer mid-sentence.
  Future<VoiceTurn> captureJournalEntry({
    Duration listenFor = const Duration(seconds: 30),
    Duration pauseFor = const Duration(seconds: 4),
    String localeId = 'en_US',
  }) async {
    await init(localeId: localeId);

    final completer = Completer<String>();
    var lastWords = '';
    await _stt.listen(
      localeId: localeId,
      listenFor: listenFor,
      pauseFor: pauseFor,
      partialResults: true,
      onResult: (SpeechRecognitionResult r) {
        lastWords = r.recognizedWords;
        if (r.finalResult && !completer.isCompleted) {
          completer.complete(r.recognizedWords);
        }
      },
    );

    // Fall-back: if STT never fires `finalResult` (some Android engines drop
    // it), resolve when listening stops.
    Timer? guard;
    guard = Timer(listenFor + const Duration(seconds: 1), () {
      if (!completer.isCompleted) completer.complete(lastWords);
    });

    final transcript = await completer.future;
    guard.cancel();
    await _stt.stop();

    if (transcript.trim().isEmpty) {
      const empty = "I didn't catch that. Could you try again?";
      await speak(empty);
      return VoiceTurn(transcript: '', reply: empty);
    }

    final reply = await GemmaService.instance.extractPainEntry(transcript);
    await speak(reply);
    return VoiceTurn(transcript: transcript, reply: reply);
  }

  /// Conversation history shared across [chatOnce] calls. Mirrors the backend's
  /// per-WebSocket session memory; trimmed to the last 8 turns by GemmaService.
  final List<Map<String, String>> _history = [];
  void resetHistory() => _history.clear();

  /// Voice round-trip — STT → Gemma → TTS. When [gaitContext] and [lang] are
  /// provided, uses the backend-equivalent system prompt with the patient's
  /// last gait analysis, so the model answers questions about real symmetry,
  /// severity, and prescribed exercises rather than generic small-talk.
  ///
  /// `lang` accepts the same codes the backend used: 'bn' / 'hi' / 'en'.
  /// `localeId` is the Android STT engine locale (e.g. 'en_US', 'hi_IN', 'bn_IN').
  Future<VoiceTurn> chatOnce({
    Duration listenFor = const Duration(seconds: 20),
    Duration pauseFor = const Duration(seconds: 3),
    String localeId = 'en_US',
    String lang = 'en',
    AnalysisResponse? gaitContext,
  }) async {
    await init(localeId: localeId);
    final transcript = await _captureOnce(
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: localeId,
    );
    if (transcript.isEmpty) {
      return const VoiceTurn(transcript: '', reply: '');
    }
    final reply = gaitContext != null
        ? await GemmaService.instance.chatWithGaitContext(
            userText: transcript,
            lang: lang,
            history: _history,
            gaitContext: gaitContext,
          )
        : await GemmaService.instance.chat(transcript);
    _history
      ..add({'role': 'user', 'content': transcript})
      ..add({'role': 'assistant', 'content': reply});
    await speak(reply);
    return VoiceTurn(transcript: transcript, reply: reply);
  }

  /// Public capture: returns the recognised transcript (trimmed, possibly
  /// empty) and stops listening. Lets a caller orchestrate the TTS/LLM steps
  /// themselves rather than going through [chatOnce].
  Future<String> captureUtterance({
    Duration listenFor = const Duration(seconds: 20),
    Duration pauseFor = const Duration(seconds: 3),
    String localeId = 'en_US',
  }) async {
    await init(localeId: localeId);
    return _captureOnce(
      listenFor: listenFor,
      pauseFor: pauseFor,
      localeId: localeId,
    );
  }

  // ─── Manual start/stop capture ────────────────────────────────────────────
  //
  // [captureUtterance] auto-closes on a 3s silence which surprises older users
  // who pause mid-sentence. The manual variant stays open until the caller
  // explicitly calls [stopAndCollect]; STT internal timeouts are pushed out
  // to 5 minutes so the engine doesn't terminate the session itself.

  Completer<String>? _manualCompleter;
  // Words finalised across past restart cycles, joined with a single space.
  String _manualCommitted = '';
  // Partial transcript for the *current* recognizer leg only — cleared on
  // each restart since speech_to_text reports partials relative to the
  // active leg, not the whole session.
  String _manualLegPartial = '';
  Timer? _manualGuard;
  String _manualLocale = 'en_US';
  bool _restarting = false;
  // Flips to true on the platform's 'listening' status and back on
  // 'notListening' / 'done'. Used to ignore the initial 'notListening' state
  // that fires before the recognizer is actually capturing audio.
  bool _legActuallyStarted = false;

  String get _manualTranscript {
    final tail = _manualLegPartial.trim();
    if (tail.isEmpty) return _manualCommitted.trim();
    if (_manualCommitted.isEmpty) return tail;
    return '${_manualCommitted.trim()} $tail';
  }

  /// Begin a manually-controlled listening session. Resolves nothing; pair
  /// with [stopAndCollect] to read the final transcript.
  Future<void> startListening({String localeId = 'en_US'}) async {
    await init(localeId: localeId);
    if (_manualCompleter != null) {
      // Already listening — ignore.
      return;
    }
    _manualCompleter = Completer<String>();
    _manualCommitted = '';
    _manualLegPartial = '';
    _manualLocale = localeId;

    await _listenLeg();

    // Safety net: if STT silently dies and the status callback never fires,
    // resolve with whatever we heard so the UI doesn't hang forever.
    _manualGuard = Timer(const Duration(minutes: 10), () {
      final c = _manualCompleter;
      if (c != null && !c.isCompleted) c.complete(_manualTranscript);
    });
  }

  /// Start one recognizer "leg". The platform may stop this leg on its own
  /// (silence timeout, no-match error). [_maybeRestartManual] re-arms a new
  /// leg with the prior leg's words committed.
  ///
  /// IMPORTANT: we commit a leg's words EXACTLY ONCE, at the leg's boundary
  /// (restart or stop) — not on `finalResult`. The Android recognizer often
  /// fires `finalResult` and then `notListening` for the same leg, so
  /// committing in both places duplicated every phrase.
  Future<void> _listenLeg() async {
    if (_manualCompleter == null) return;
    _manualLegPartial = '';
    await _stt.listen(
      localeId: _manualLocale,
      listenFor: const Duration(minutes: 5),
      pauseFor: const Duration(minutes: 5),
      partialResults: true,
      onResult: (r) {
        // Overwrite, don't append — partials are always the full leg so far.
        _manualLegPartial = r.recognizedWords;
      },
    );
  }

  /// Append [chunk] to the committed transcript, but only if it isn't already
  /// the trailing fragment — guards against the platform firing identical
  /// results twice on the same leg.
  void _commitLeg(String chunk) {
    final tail = chunk.trim();
    if (tail.isEmpty) return;
    final existing = _manualCommitted.trim();
    if (existing.toLowerCase().endsWith(tail.toLowerCase())) return;
    _manualCommitted = existing.isEmpty ? tail : '$existing $tail';
    _manualLegPartial = '';
  }

  /// Called from the status/error callbacks when the platform recognizer
  /// ends a leg on its own. If we're still in a manual session, commit the
  /// dying leg's words and start the next leg.
  void _maybeRestartManual() {
    if (_manualCompleter == null) return;
    if (_restarting) return;
    _restarting = true;
    _commitLeg(_manualLegPartial);
    // Brief delay lets the platform recognizer fully tear down before we
    // hand it a new session — without this the second listen() can throw.
    Future<void>.delayed(const Duration(milliseconds: 300), () async {
      _restarting = false;
      if (_manualCompleter == null) return;
      try {
        await _listenLeg();
      } catch (e) {
        // ignore: avoid_print
        print('[VoiceService] manual restart failed: $e');
      }
    });
  }

  /// Stop the current manual session and return the transcript heard so far.
  /// Safe to call even if [startListening] was never invoked.
  Future<String> stopAndCollect() async {
    final completer = _manualCompleter;
    if (completer == null) return '';
    _manualCompleter = null;
    _manualGuard?.cancel();
    _manualGuard = null;
    await _stt.stop();
    if (!completer.isCompleted) completer.complete(_manualTranscript);
    final out = await completer.future;
    return out.trim();
  }

  bool get isManualListening => _manualCompleter != null;

  Future<String> _captureOnce({
    required Duration listenFor,
    required Duration pauseFor,
    required String localeId,
  }) async {
    final completer = Completer<String>();
    var last = '';
    await _stt.listen(
      localeId: localeId,
      listenFor: listenFor,
      pauseFor: pauseFor,
      partialResults: true,
      onResult: (r) {
        last = r.recognizedWords;
        if (r.finalResult && !completer.isCompleted) {
          completer.complete(r.recognizedWords);
        }
      },
    );
    final guard = Timer(listenFor + const Duration(seconds: 1), () {
      if (!completer.isCompleted) completer.complete(last);
    });
    final out = await completer.future;
    guard.cancel();
    await _stt.stop();
    return out.trim();
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> cancel() async {
    await _stt.stop();
    await _tts.stop();
  }

  bool get isListening => _stt.isListening;
}

