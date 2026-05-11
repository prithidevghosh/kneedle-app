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
      onError: (_) {},
      onStatus: (_) {},
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

