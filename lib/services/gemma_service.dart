import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma/flutter_gemma.dart';

import '../clinical/prompts.dart';
import '../clinical/safety_defaults.dart';
import '../clinical/severity.dart';
import '../data/exercise_library.dart';
import '../gait/pipeline.dart';
import '../kb/retriever.dart';
import '../models/analysis_response.dart';
import '../models/appointment.dart';
import '../models/medication.dart';
import '../models/pain_entry.dart';
import 'gemma_stats.dart';
import 'notification_service.dart';
import 'storage_service.dart';

export 'gemma_stats.dart';

/// Singleton wrapper around `flutter_gemma`. Holds the loaded Gemma E2B model
/// (LiteRT, INT4) and acts as a stand-in for what the FastAPI backend used to
/// do via Ollama — except now the inference runs entirely on the user's
/// device. The Hugging Face URL is only used once (first launch) to obtain
/// the weights file; afterwards the model is loaded from local storage with
/// zero network access.
///
/// Surfaces:
///   * `chat(text)` — short conversational reply.
///   * `extractPainEntry(transcript)` — STT → function-call → Hive write.
///   * `generateWeeklySummary(entries)` — short narrative summary.
///   * `analyseGait(metrics, frames, ...)` — direct port of the backend's
///     `call_gemma4`. Multimodal (frames + measurements), JSON output,
///     severity-aware exercise filtering, hardcoded safe fallback.
///   * `chatWithGaitContext(...)` — port of `voice_chat_service.chat`,
///     conversation history + gait analysis context in the system prompt.
///
/// Function-calling contract (exposed to the model):
///   * `record_pain_entry({ pain_score, location, context })`
///   * `schedule_reminder({ title, body, in_minutes })`
class GemmaService {
  GemmaService._();
  static final GemmaService instance = GemmaService._();

  /// Gemma 4 E2B instruction-tuned, INT4-quantised LiteRT bundle. Same
  /// weights an Ollama install would pull from its registry (`gemma4:e2b`) —
  /// only the transport differs. Picked per the brief: ~1.5 GB resident at
  /// INT4 vs ~5 GB for E4B, leaving headroom for camera + MediaPipe + Flutter
  /// on the 8 GB target device.
  // Pinned to the pre-MTP revision (2026-05-04 upload, before commit 6e5c4f1
  // introduced a 3-signature vision encoder that the Android LiteRT-LM
  // runtime can't load). See DenisovAV/flutter_gemma#259. Once the bundled
  // libLiteRtLm.so on Android is rebuilt against LiteRT-LM ≥0.11.0 with
  // working multi-signature support, switch back to `resolve/main/`.
  static const _modelUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/7fa1d78473894f7e736a21d920c3aa80f950c0db/gemma-4-E2B-it.litertlm';

  // Vision is enabled for gait analysis: we attach 4 JPEGs (2 frontal + 2
  // sagittal walk frames) alongside the MediaPipe measurements so Gemma can
  // visually cross-check what the numbers describe. The companion chat path
  // still sends text only; only `analyseGait` builds a multimodal message.
  static const _supportImage = true;

  InferenceModel? _model;
  InferenceChat? _chat;
  String? _systemPrompt;
  bool _initialising = false;

  /// Stats from the most recent companion-chat or voice-chat call. Surfaced
  /// in the home / voice screens via the tokens-per-second pill so the user
  /// can see how fast Gemma is decoding.
  LlmStats? lastStats;

  bool get isReady => _model != null && _chat != null;

  Future<void> initialise({
    void Function(double progress)? onDownloadProgress,
  }) async {
    if (isReady || _initialising) return;
    _initialising = true;
    try {
      // ignore: avoid_print
      print('[GemmaService] init step 1/4: loading system prompt asset');
      _systemPrompt =
          await rootBundle.loadString('assets/prompts/companion_system.txt');

      // ignore: avoid_print
      print('[GemmaService] init step 2/4: installing model from network '
          '(first launch downloads ~1.5 GB)');
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      )
          .fromNetwork(_modelUrl)
          .withProgress((p) {
            onDownloadProgress?.call(p / 100.0);
            // Throttle: only log every ~10% so the console doesn't flood.
            final whole = p.toInt();
            if (whole % 10 == 0 && whole != _lastLoggedPct) {
              _lastLoggedPct = whole;
              // ignore: avoid_print
              print('[GemmaService] download progress: $whole%');
            }
          })
          .install();
      // ignore: avoid_print
      print('[GemmaService] init step 2/4: download complete');

      // ignore: avoid_print
      print('[GemmaService] init step 3/4: loading model into runtime');
      _model = await _loadModelWithFallback();

      // ignore: avoid_print
      print('[GemmaService] init step 4/4: creating chat session');
      _chat = await _model!.createChat(
        temperature: 0.6,
        topK: 40,
        topP: 0.95,
        tokenBuffer: 256,
        supportsFunctionCalls: true,
        tools: _toolDefinitions,
      );

      await _chat!.addQueryChunk(
        Message.text(text: _systemPrompt!, isUser: true),
      );

      // Warm the session: force the model to prefill the system prompt now,
      // during the loading screen, instead of paying ~20s on the user's first
      // real message. The system prompt asks the model to acknowledge with a
      // single token ("Ready."), so the discarded decode is ~1 chunk. After
      // this returns, subsequent turns prefill incrementally over the cached
      // system-prompt KV.
      // ignore: avoid_print
      print('[GemmaService] init step 4/4: warming session (prefilling system prompt)');
      final warmSw = Stopwatch()..start();
      try {
        final warm = await _chat!.generateChatResponse();
        final preview = warm is TextResponse ? warm.token : '';
        // ignore: avoid_print
        print('[GemmaService] warmup done in ${warmSw.elapsedMilliseconds}ms '
            '(model said: "${preview.trim()}")');
      } catch (e) {
        // ignore: avoid_print
        print('[GemmaService] warmup failed (non-fatal): $e');
      }
      // ignore: avoid_print
      print('[GemmaService] init complete — model ready');
    } catch (e, st) {
      // ignore: avoid_print
      print('[GemmaService] init FAILED: $e\n$st');
      rethrow;
    } finally {
      _initialising = false;
    }
  }

  int _lastLoggedPct = -1;

  // ── Perf levers (flip these per device, with caution) ──────────────────
  //
  //  * _useNpu: requires Qualcomm QNN / Google Tensor / MediaTek dispatch
  //    libs to be present. Most mid-range Android phones lack them; the
  //    plugin won't throw on absence, it just logs "No dispatch library
  //    found" and silently keeps NPU as the preferred backend — which then
  //    causes a hard crash mid-init. Only enable on a device you've
  //    confirmed has the dispatch libs (flagship SD 8 Gen 2+, Tensor G3+,
  //    Dimensity 9200+).
  //  * _useSpeculativeDecoding: MTP. Gives ~1.5–2× decode speedup BUT loads
  //    a draft model alongside the main one (extra ~400–600 MB). On 4–6 GB
  //    devices this can OOM. Safe to leave off; turn on when targeting
  //    ≥8 GB hardware.
  static const bool _useNpu = false;
  static const bool _useSpeculativeDecoding = false;

  Future<InferenceModel> _loadModelWithFallback() async {
    const backend = _useNpu ? PreferredBackend.npu : PreferredBackend.gpu;
    // ignore: avoid_print
    print('[GemmaService] loading model: backend=$backend '
        'speculative=$_useSpeculativeDecoding');
    return FlutterGemma.getActiveModel(
      preferredBackend: backend,
      // will change later — lowered from 8192 to fit 4 GB test device.
      // 4096 is still > the trimmed analysis prompt (~1.6–2k tokens) with
      // generation headroom. Bump back up once we test on ≥8 GB hardware.
      maxTokens: 4096,
      supportImage: _supportImage,
      // 4 = the gait-analysis bundle (2 frontal + 2 sagittal). Companion chat
      // never sends images, so this is a strict upper bound for the only
      // multimodal path we have.
      maxNumImages: _supportImage ? 4 : null,
      enableSpeculativeDecoding: _useSpeculativeDecoding ? true : null,
    );
  }

  // ─── Companion: free chat ────────────────────────────────────────────────

  Future<String> chat(String userText) async {
    _ensure();
    lastToolCalls.clear();
    // ignore: avoid_print
    print('[GemmaService] chat INPUT (${userText.length} chars): $userText');
    final sw = Stopwatch()..start();
    await _chat!.addQueryChunk(Message.text(text: userText, isUser: true));
    final response = await _chat!.generateChatResponse();
    final reply = await _handleResponse(response, originalUserText: userText);
    sw.stop();
    final stats = LlmStats(
      inputChars: userText.length,
      outputChars: reply.length,
      outputTokens: (reply.length / 4).round(), // BPE ≈ 4 chars/token
      generationMs: sw.elapsedMilliseconds,
    );
    lastStats = stats;
    // ignore: avoid_print
    print('[GemmaService] chat OUTPUT (${reply.length} chars): $reply');
    // ignore: avoid_print
    print('[GemmaService] chat STATS ${stats.summary()} '
        '(token count approx — function-call path is not streamed)');
    return reply;
  }

  Future<String> extractPainEntry(String voiceTranscript) async {
    _ensure();
    const instruction = 'The user just spoke about their pain. Call '
        'record_pain_entry with the extracted fields, then briefly '
        'acknowledge in one sentence.';
    await _chat!.addQueryChunk(Message.text(
      text: '$instruction\n\nUser said: "$voiceTranscript"',
      isUser: true,
    ));
    final response = await _chat!.generateChatResponse();
    return _handleResponse(response, originalUserText: voiceTranscript);
  }

  Future<String> generateWeeklySummary(List<PainEntry> entries) async {
    _ensure();
    if (entries.isEmpty) {
      return 'No pain entries this week. Keep up the gentle movement.';
    }
    final json = jsonEncode([for (final e in entries) e.toJson()]);
    await _chat!.addQueryChunk(Message.text(
      text:
          'Summarise this past week of pain entries in 2 short paragraphs. '
          'Tone: warm, non-medical, factual. Highlight any worsening or '
          'improving trend, dominant location, and one practical suggestion.\n\n'
          'Entries (JSON): $json',
      isUser: true,
    ));
    final response = await _chat!.generateChatResponse();
    if (response is TextResponse) return response.token;
    return 'Summary unavailable.';
  }

  // ─── Gait analysis — port of gemma_client.call_gemma4 ────────────────────

  /// Run the full multimodal clinical analysis. Behaviour-equivalent to the
  /// FastAPI backend's `call_gemma4`:
  ///
  ///  1. Severity tier is computed deterministically from the metrics.
  ///  2. Exercise library is filtered by severity BEFORE the model sees it.
  ///  3. The (severity, prompt, library, frames) bundle is sent to Gemma.
  ///  4. The JSON reply is parsed; the model's exercise picks are restricted
  ///     to the filtered set; one contraindication=="None" entry is guaranteed.
  ///  5. Bilingual safety defaults fill any field the model omits.
  ///  6. On any failure we drop into a severity-aware hardcoded response so
  ///     the patient is never left without guidance.
  ///
  /// Multimodal: the model receives metrics + the severity-filtered exercise
  /// library AND up to 4 JPEG snapshots from the walking video (2 frontal,
  /// 2 sagittal). Vision tokens add ~600 prefill tokens per frame on E2B, so
  /// the caller is expected to keep the bundle ≤4 frames.
  Future<AnalysisResponse> analyseGait({
    required GaitMetrics metrics,
    required String age,
    required String knee,
    required String lang,
    required int sessionNumber,
    List<Uint8List> frontalFrames = const [],
    List<Uint8List> sagittalFrames = const [],
    void Function(GemmaAnalysisEvent event)? onEvent,
  }) async {
    final totalSw = Stopwatch()..start();
    void emit(String stage,
        {String message = '', String partial = '', LlmStats? stats}) {
      onEvent?.call(GemmaAnalysisEvent(
        stage: stage,
        message: message,
        partial: partial,
        stats: stats,
      ));
    }

    emit('prepare', message: 'Reading pose metrics…');
    final severity = assessSeverity(metrics);
    final symBand = computeSymmetryBand(metrics.symmetryScore);
    final library = filterLibraryBySeverity(severity);
    final safety = safetyFor(lang);

    // Cap at 4 frames total (2 frontal + 2 sagittal) regardless of what the
    // caller hands us — extra frames just burn prefill tokens.
    final fFrames =
        frontalFrames.length > 2 ? frontalFrames.sublist(0, 2) : frontalFrames;
    final sFrames = sagittalFrames.length > 2
        ? sagittalFrames.sublist(0, 2)
        : sagittalFrames;
    final attachedImages = <Uint8List>[...fFrames, ...sFrames];

    final systemPrompt = buildAnalysisSystemPrompt(lang);
    final userPrompt = buildAnalysisUserPrompt(
      metrics: metrics,
      age: age,
      knee: knee,
      severity: severity,
      library: library,
      frontalFrameCount: fFrames.length,
      sagittalFrameCount: sFrames.length,
    );

    try {
      _ensure();

      // Use a fresh chat session so the analysis prompt isn't polluted by the
      // companion conversation history. The model is shared; sessions are not.
      emit('prefill', message: 'Loading clinical context into Gemma…');
      final sessionSw = Stopwatch()..start();
      final session = await _model!.createChat(
        temperature: 0.4,
        topK: 40,
        topP: 0.9,
        // Function calling explicitly OFF — clinical mode wants strict JSON.
        supportsFunctionCalls: false,
        tools: const [],
        supportImage: attachedImages.isNotEmpty,
      );
      // ignore: avoid_print
      print('[GemmaService] analyseGait createChat: '
          '${sessionSw.elapsedMilliseconds}ms');
      try {
        // Detailed input log — full prompts go in so a developer reproducing a
        // bad output can see exactly what the model saw. Prompts are clamped
        // when the analysis is run live (no PII beyond age + knee) so logging
        // them is fine for an on-device app.
        // ignore: avoid_print
        print('[GemmaService] analyseGait INPUT severity=$severity '
            'symBand=$symBand age=$age knee=$knee lang=$lang '
            'sessionNumber=$sessionNumber');
        // ignore: avoid_print
        print('[GemmaService] analyseGait INPUT system_prompt '
            '(${systemPrompt.length} chars):\n$systemPrompt');
        // ignore: avoid_print
        print('[GemmaService] analyseGait INPUT user_prompt '
            '(${userPrompt.length} chars):\n$userPrompt');
        if (attachedImages.isNotEmpty) {
          final sizes =
              attachedImages.map((b) => '${b.length}B').join(', ');
          // ignore: avoid_print
          print('[GemmaService] analyseGait INPUT frames=${attachedImages.length} '
              '(${fFrames.length} frontal + ${sFrames.length} sagittal) '
              'sizes=[$sizes]');
        }

        final prefillSw = Stopwatch()..start();
        await session.addQueryChunk(
          Message.text(text: systemPrompt, isUser: true),
        );
        // flutter_gemma 0.15 carries one image per Message. To pass 4, we
        // chunk them one at a time with a short label, then the text prompt
        // closes the user turn. Labels live in their own image-only chunk so
        // the model can associate each image with frontal/sagittal context
        // before it reads the metrics block.
        for (var i = 0; i < fFrames.length; i++) {
          await session.addQueryChunk(Message.withImage(
            text: 'Frontal walk frame ${i + 1} of ${fFrames.length}.',
            imageBytes: fFrames[i],
            isUser: true,
          ));
        }
        for (var i = 0; i < sFrames.length; i++) {
          await session.addQueryChunk(Message.withImage(
            text: 'Sagittal walk frame ${i + 1} of ${sFrames.length}.',
            imageBytes: sFrames[i],
            isUser: true,
          ));
        }
        await session.addQueryChunk(
          Message.text(text: userPrompt, isUser: true),
        );
        prefillSw.stop();
        // ignore: avoid_print
        print('[GemmaService] analyseGait queue done in '
            '${prefillSw.elapsedMilliseconds}ms — starting stream');

        emit(
          'streaming',
          message: attachedImages.isEmpty
              ? 'Gemma is reading your metrics…'
              : 'Gemma is looking at your walk frames…',
        );

        final stats = LlmStats(
          inputChars: systemPrompt.length + userPrompt.length,
          imageCount: attachedImages.length,
        );
        final genSw = Stopwatch()..start();
        final firstTokenSw = Stopwatch()..start();
        final buf = StringBuffer();
        await for (final r in session.generateChatResponseAsync()) {
          if (r is TextResponse) {
            if (firstTokenSw.isRunning) {
              firstTokenSw.stop();
              stats.firstTokenMs = firstTokenSw.elapsedMilliseconds;
              stats.prefillMs =
                  prefillSw.elapsedMilliseconds + stats.firstTokenMs;
              // Re-base generation timer so prefill ms doesn't pollute TPS.
              genSw
                ..reset()
                ..start();
            }
            buf.write(r.token);
            stats.outputTokens++;
            stats.outputChars = buf.length;
            stats.generationMs = genSw.elapsedMilliseconds;
            // Throttle UI updates to ~every 4 tokens so we don't drown the
            // event bus on a 30 tok/s stream.
            if (stats.outputTokens % 4 == 0) {
              emit('streaming',
                  partial: buf.toString(),
                  stats: stats,
                  message: 'Gemma is drafting your plan…');
            }
          }
        }
        genSw.stop();
        if (firstTokenSw.isRunning) {
          firstTokenSw.stop();
          stats.firstTokenMs = firstTokenSw.elapsedMilliseconds;
          stats.prefillMs =
              prefillSw.elapsedMilliseconds + stats.firstTokenMs;
        }
        final text = buf.toString();
        // ignore: avoid_print
        print('[GemmaService] analyseGait OUTPUT (${text.length} chars):\n'
            '$text');
        // ignore: avoid_print
        print('[GemmaService] analyseGait STATS ${stats.summary()} '
            '· total ${totalSw.elapsedMilliseconds}ms');
        emit('parse',
            message: 'Building your personalised plan…',
            partial: text,
            stats: stats);
        final parsed = _parseAnalysisJson(
          raw: text,
          metrics: metrics,
          library: library,
          severity: severity,
          symBand: symBand,
          lang: lang,
          sessionNumber: sessionNumber,
          safety: safety,
        );
        final enriched = parsed.copyWith(stats: stats);
        emit('done',
            message: 'Done', partial: text, stats: stats);
        return enriched;
      } finally {
        // Best-effort cleanup; the plugin variants disagree on the close API.
        try {
          // ignore: avoid_dynamic_calls
          await (session as dynamic).close();
        } catch (_) {/* no-op */}
      }
    } catch (e, st) {
      // Surface parse/inference failures so you can see them in `flutter run`
      // logs instead of silently rendering the safety-default response.
      // ignore: avoid_print
      print('[GemmaService] analyseGait fallback engaged: $e\n$st');
      return _fallbackAnalysis(
        metrics: metrics,
        lang: lang,
        sessionNumber: sessionNumber,
        error: e.toString(),
      );
    }
  }

  /// Open a long-lived chat session pre-loaded with the patient's gait
  /// analysis. Use this when the user is in a sustained Q&A on the result
  /// screen — each [GaitChatSession.ask] call reuses the same KV cache, so
  /// follow-up questions only prefill the new user message (~50 tokens)
  /// instead of re-prefilling system + context + history every turn
  /// (~2k tokens). The first call still pays full cold prefill, but we kick
  /// off a background warmup here so most of it happens while the user is
  /// still reading the screen.
  ///
  /// MUST be paired with [GaitChatSession.close] on screen dispose — the
  /// session holds ~150–250 MB of KV cache.
  Future<GaitChatSession> openGaitChat({
    required AnalysisResponse response,
    required String lang,
  }) async {
    _ensure();
    final ctxBlock =
        formatGaitContextBlock(response.toContextJson(), lang);
    final sys = buildVoiceChatSystemPrompt(
      lang: lang,
      gaitContextBlock: ctxBlock,
    );

    final chat = await _model!.createChat(
      temperature: 0.7,
      topK: 40,
      topP: 0.9,
      supportsFunctionCalls: false,
      tools: const [],
    );

    // Queue the system prompt + a 1-token warmup elicitation. The first call
    // to generateChatResponse triggers native prefill of everything queued so
    // far — we run it eagerly in the background here so the user's first
    // real question pays only its own (~50-token) prefill.
    await chat.addQueryChunk(Message.text(
      text:
          '$sys\n\nWhen you have read this report and are ready to answer '
          "questions about it, reply with exactly one word: Ready.",
      isUser: true,
    ));

    final warmSw = Stopwatch()..start();
    final warmupFuture = chat.generateChatResponse().then((r) {
      final txt = r is TextResponse ? r.token.trim() : '';
      // ignore: avoid_print
      print('[GemmaService] gait chat warmup done in '
          '${warmSw.elapsedMilliseconds}ms (model said: "$txt")');
    }).catchError((Object e) {
      // ignore: avoid_print
      print('[GemmaService] gait chat warmup failed (non-fatal): $e');
    });

    return GaitChatSession._(chat: chat, warmupFuture: warmupFuture);
  }

  /// Voice-chat with the patient's last gait analysis baked into the system
  /// prompt. Direct port of `voice_chat_service.chat`. `history` is a list of
  /// `{role: 'user'|'assistant', content: '...'}` maps; rotate it via
  /// `trimHistory`.
  ///
  /// Prefer [openGaitChat] for multi-turn flows — it keeps one session alive
  /// across questions instead of rebuilding the prefill every turn. This
  /// transient-session variant remains for one-shot uses.
  Future<String> chatWithGaitContext({
    required String userText,
    required String lang,
    required List<Map<String, String>> history,
    AnalysisResponse? gaitContext,
  }) async {
    _ensure();
    final ctxBlock = gaitContext == null
        ? null
        : formatGaitContextBlock(gaitContext.toContextJson(), lang);
    final sys = buildVoiceChatSystemPrompt(
      lang: lang,
      gaitContextBlock: ctxBlock,
    );

    // Like the backend, we run this in a transient session that does NOT see
    // the companion's tools — voice chat replies are pure text.
    final session = await _model!.createChat(
      temperature: 0.7,
      topK: 40,
      topP: 0.9,
      supportsFunctionCalls: false,
      tools: const [],
    );
    try {
      // ignore: avoid_print
      print('[GemmaService] chatWithGaitContext INPUT '
          '(sys=${sys.length} chars, user=${userText.length} chars, '
          'history=${history.length})');
      final prefillSw = Stopwatch()..start();
      await session.addQueryChunk(Message.text(text: sys, isUser: true));
      for (final m in trimHistory(history)) {
        final isUser = m['role'] == 'user';
        await session.addQueryChunk(
          Message.text(text: m['content'] ?? '', isUser: isUser),
        );
      }
      await session.addQueryChunk(Message.text(text: userText, isUser: true));
      prefillSw.stop();

      final stats = LlmStats(inputChars: sys.length + userText.length);
      final firstTokenSw = Stopwatch()..start();
      final genSw = Stopwatch()..start();
      final buf = StringBuffer();
      await for (final r in session.generateChatResponseAsync()) {
        if (r is TextResponse) {
          if (firstTokenSw.isRunning) {
            firstTokenSw.stop();
            stats.firstTokenMs = firstTokenSw.elapsedMilliseconds;
            stats.prefillMs =
                prefillSw.elapsedMilliseconds + stats.firstTokenMs;
            genSw
              ..reset()
              ..start();
          }
          buf.write(r.token);
          stats.outputTokens++;
          stats.generationMs = genSw.elapsedMilliseconds;
        }
      }
      genSw.stop();
      final reply = _stripThink(buf.toString());
      stats.outputChars = reply.length;
      lastStats = stats;
      // ignore: avoid_print
      print('[GemmaService] chatWithGaitContext OUTPUT '
          '(${reply.length} chars): $reply');
      // ignore: avoid_print
      print('[GemmaService] chatWithGaitContext STATS ${stats.summary()}');
      return reply;
    } finally {
      try {
        // ignore: avoid_dynamic_calls
        await (session as dynamic).close();
      } catch (_) {/* no-op */}
    }
  }

  /// Cap conversation memory — same `MAX_HISTORY_MESSAGES = 8` policy as the
  /// backend (4 user + 4 assistant turns).
  static List<Map<String, String>> trimHistory(List<Map<String, String>> h) {
    const maxMsgs = 8;
    if (h.length <= maxMsgs) return List.from(h);
    return h.sublist(h.length - maxMsgs);
  }

  // ─── Voice / journal tool dispatch ───────────────────────────────────────

  // Tool schemas are sent to the model as part of the chat prefill. Every
  // extra token here adds latency to *every* turn — keep descriptions terse
  // and let the system prompt cover when-to-call routing.
  static const List<Tool> _toolDefinitions = [
    Tool(
      name: 'record_pain_entry',
      description:
          'Log a pain entry when the user describes their current pain '
          '(intensity 0–10 and/or body location).',
      parameters: {
        'type': 'object',
        'properties': {
          'pain_score': {'type': 'integer', 'minimum': 0, 'maximum': 10},
          'location': {'type': 'string'},
          'context': {'type': 'string'},
        },
        'required': ['pain_score', 'location'],
      },
    ),
    Tool(
      name: 'schedule_reminder',
      description:
          'One-shot nudge N minutes from now, e.g. "remind me in 20 minutes '
          'to ice my knee". Use ONLY for relative "in N minutes" requests, '
          'not daily routines (use add_medication) and not appointments '
          '(use add_appointment).',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'body': {'type': 'string'},
          'in_minutes': {'type': 'integer', 'minimum': 1},
        },
        'required': ['title', 'in_minutes'],
      },
    ),
    Tool(
      name: 'add_medication',
      description:
          'Daily recurring medication reminder at a fixed time of day. '
          'Use when the user wants a routine like "every day at 10:35" '
          'or "remind me to take X at 8am". hour+minute are 24h.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'dose': {'type': 'string'},
          'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23},
          'minute': {'type': 'integer', 'minimum': 0, 'maximum': 59},
        },
        'required': ['name', 'hour', 'minute'],
      },
    ),
    Tool(
      name: 'add_appointment',
      description:
          'Single upcoming doctor / physio / scan visit. when_iso must be '
          'an absolute ISO-8601 datetime in the future. Notifies 1h before.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
          'when_iso': {
            'type': 'string',
            'description': 'Absolute ISO-8601 datetime.',
          },
          'location': {'type': 'string'},
        },
        'required': ['title', 'when_iso'],
      },
    ),
    Tool(
      name: 'list_medications',
      description:
          'Return the user\'s active daily medication reminders. Use when '
          'they ask what meds they take or what is scheduled.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    Tool(
      name: 'list_appointments',
      description:
          'Return upcoming appointments. Use when they ask about their next '
          'visit / doctor / physio.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    Tool(
      name: 'remove_medication',
      description:
          'Delete a daily medication reminder by name. Use when the user '
          'asks to stop / cancel / remove a recurring medication, e.g. '
          '"remove my thyroid reminder", "stop the metformin alarm". Matches '
          'the name as a case-insensitive substring; if multiple medications '
          'match, the tool returns the candidates so you can ask which one.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'required': ['name'],
      },
    ),
    Tool(
      name: 'remove_appointment',
      description:
          'Delete an upcoming appointment by title. Use when the user asks '
          'to cancel / remove / drop a doctor / physio / scan visit. Matches '
          'the title as a case-insensitive substring; if multiple match, the '
          'tool returns the candidates so you can ask which one.',
      parameters: {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
        },
        'required': ['title'],
      },
    ),
    Tool(
      name: 'start_gait_test',
      description:
          'Launch the on-device walking analysis. Use when the user wants '
          'to "do a gait check", "run a walk test", "check how I walk", or '
          'similar. Takes no arguments.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    Tool(
      name: 'show_history',
      description:
          "Open the patient's trends / history view. Use when they ask "
          '"how have I been", "show my history", "show my pain trend", '
          'or want to see past results. `weeks` defaults to 4.',
      parameters: {
        'type': 'object',
        'properties': {
          'weeks': {'type': 'integer', 'minimum': 1, 'maximum': 12},
        },
      },
    ),
    Tool(
      name: 'generate_doctor_report',
      description:
          'Build a clinician-ready PDF of the recent pain, gait, and '
          'exercise history. Use when the user wants to "share with my '
          'doctor", "make a report", "export for the doctor".',
      parameters: {'type': 'object', 'properties': {}},
    ),
  ];

  /// Tools whose `acknowledgement` string is already user-ready. After these
  /// fire we skip the second model round-trip (the model would otherwise
  /// spend 10–15s paraphrasing the same sentence). The tool response is still
  /// buffered into the chat so the next user turn has full context — we just
  /// don't pay for a follow-up generation.
  static const _terminalAckTools = {
    'record_pain_entry',
    'schedule_reminder',
    'add_medication',
    'add_appointment',
    'remove_medication',
    'remove_appointment',
    'start_gait_test',
    'show_history',
    'generate_doctor_report',
  };

  /// One entry per tool call made during the most recent `chat()` /
  /// `extractPainEntry()` round-trip. Cleared at the start of each call.
  /// Read by `AgentScreen` to render the tool-execution timeline and to
  /// dispatch any navigation intents (start_gait_test, show_history,
  /// generate_doctor_report) after the modal closes.
  final List<AgentToolCall> lastToolCalls = [];

  Future<String> _handleResponse(
    ModelResponse response, {
    required String originalUserText,
  }) async {
    if (response is TextResponse) {
      final stripped = _stripThink(response.token);
      // Workaround for flutter_gemma 0.15.1 + Gemma 4: native function calls
      // leak through as raw `<|tool_call>call:NAME{...}` markup inside a
      // TextResponse instead of being parsed into a FunctionCallResponse.
      // We detect that markup here and route through the existing tool
      // dispatcher so the user sees the same outcome as the well-typed path.
      final inline = _parseInlineToolCall(stripped);
      if (inline != null) {
        return _runInlineToolCall(
          name: inline.name,
          args: inline.args,
          originalUserText: originalUserText,
        );
      }
      return stripped;
    }
    if (response is FunctionCallResponse) {
      return _runInlineToolCall(
        name: response.name,
        args: Map<String, Object?>.from(response.args),
        originalUserText: originalUserText,
        bufferToolResponse: true,
      );
    }
    return '';
  }

  /// Shared dispatch path for both the well-typed [FunctionCallResponse]
  /// branch and the inline-markup workaround. Centralising it means a tool
  /// that gets called via the leaky text path produces exactly the same
  /// `lastToolCalls` entry, acknowledgement, and chat-session bookkeeping
  /// as one that came through cleanly — the agent timeline can't tell the
  /// difference.
  Future<String> _runInlineToolCall({
    required String name,
    required Map<String, Object?> args,
    required String originalUserText,
    bool bufferToolResponse = false,
  }) async {
    // ignore: avoid_print
    print('[GemmaService] tool dispatch: $name args=$args '
        '(${bufferToolResponse ? "typed" : "inline-markup"})');
    final toolResult = await _dispatchTool(
      name: name,
      args: args,
      originalUserText: originalUserText,
    );
    lastToolCalls.add(AgentToolCall(
      name: name,
      args: args,
      result: Map<String, Object?>.from(toolResult),
    ));
    // Buffer the tool response into the chat so the next user turn has full
    // context. We only do this for the typed path because the inline-markup
    // path already left the model's own tool-call tokens in the KV cache —
    // adding a toolResponse on top can confuse some flutter_gemma builds.
    if (bufferToolResponse) {
      try {
        await _chat!.addQueryChunk(
          Message.toolResponse(toolName: name, response: toolResult),
        );
      } catch (e) {
        // ignore: avoid_print
        print('[GemmaService] tool-response buffer failed (non-fatal): $e');
      }
    }
    final ack = toolResult['acknowledgement'] as String?;
    final ok = toolResult['ok'] == true;
    if (ok &&
        ack != null &&
        ack.isNotEmpty &&
        _terminalAckTools.contains(name)) {
      return ack;
    }
    // Non-terminal path: ask the model to paraphrase. Only safe when the
    // session is in a state that accepts another generate. The inline path
    // generally is not, so we just return the ack/error there.
    if (!bufferToolResponse) return ack ?? '';
    try {
      final follow = await _chat!.generateChatResponse();
      if (follow is TextResponse) return _stripThink(follow.token);
    } catch (e) {
      // ignore: avoid_print
      print('[GemmaService] follow-up generate failed (non-fatal): $e');
    }
    return ack ?? '';
  }

  // ─── Inline tool-call markup parser ───────────────────────────────────────
  //
  // Gemma 4 emits function calls in a Gemma-specific grammar:
  //   <|tool_call>call:TOOL_NAME{key:VALUE, key:VALUE, ...}
  // String values are wrapped in Gemma's own quote token <|"|>...<|"|>.
  // flutter_gemma 0.15.1 sometimes fails to parse this and returns the raw
  // markup as a TextResponse. The helpers below extract that markup back
  // into a normal tool dispatch.

  static final RegExp _inlineToolCallPattern = RegExp(
    r'<\|tool_call\|?>\s*call\s*:\s*([A-Za-z_][A-Za-z0-9_]*)\s*\{([^}]*)\}',
    dotAll: true,
  );

  /// Gemma 4's own string-quote token. Note this is exactly five characters:
  /// `<`, `|`, `"`, `|`, `>`.
  static const String _gemma4QuoteToken = '<|"|>';

  /// Return `null` when [raw] contains no recognisable tool-call markup,
  /// otherwise return the parsed `(name, args)` pair.
  static ({String name, Map<String, Object?> args})? _parseInlineToolCall(
    String raw,
  ) {
    final m = _inlineToolCallPattern.firstMatch(raw);
    if (m == null) return null;
    final name = m.group(1)!;
    final body = m.group(2) ?? '';
    return (name: name, args: _parseGemma4ArgBody(body));
  }

  /// Parse the body of `{ ... }` into a map of arg-name → value. Tolerant of
  /// whitespace, missing quotes around numbers/booleans, and the Gemma 4
  /// `<|"|>` quote token (which is treated like a regular `"`). On malformed
  /// input we return whatever could be parsed up to the failure point rather
  /// than throwing — partial args are better than dropping the call entirely.
  static Map<String, Object?> _parseGemma4ArgBody(String body) {
    final out = <String, Object?>{};
    final s = body;
    var i = 0;
    final n = s.length;
    while (i < n) {
      // Skip whitespace and separators.
      while (i < n && (s[i] == ',' || _isWs(s[i]))) {
        i++;
      }
      if (i >= n) break;
      // Read key up to the next ':'.
      final colon = s.indexOf(':', i);
      if (colon < 0) break;
      final key = s.substring(i, colon).trim();
      i = colon + 1;
      // Skip whitespace before value.
      while (i < n && _isWs(s[i])) {
        i++;
      }
      if (i >= n) {
        if (key.isNotEmpty) out[key] = '';
        break;
      }
      Object? value;
      if (_startsWithAt(s, i, _gemma4QuoteToken)) {
        // String value delimited by Gemma 4's quote token.
        i += _gemma4QuoteToken.length;
        final end = s.indexOf(_gemma4QuoteToken, i);
        if (end < 0) {
          value = s.substring(i);
          i = n;
        } else {
          value = s.substring(i, end);
          i = end + _gemma4QuoteToken.length;
        }
      } else if (i < n && (s[i] == '"' || s[i] == "'")) {
        // Standard quoted string fallback.
        final quote = s[i];
        final end = s.indexOf(quote, i + 1);
        if (end < 0) {
          value = s.substring(i + 1);
          i = n;
        } else {
          value = s.substring(i + 1, end);
          i = end + 1;
        }
      } else {
        // Bareword: number, boolean, or unquoted token. Read up to the next
        // unescaped comma.
        final comma = s.indexOf(',', i);
        final endIdx = comma < 0 ? n : comma;
        final tok = s.substring(i, endIdx).trim();
        value = _coerceBareword(tok);
        i = endIdx;
      }
      if (key.isNotEmpty) out[key] = value;
    }
    return out;
  }

  static bool _isWs(String ch) =>
      ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

  static bool _startsWithAt(String s, int i, String needle) {
    if (i + needle.length > s.length) return false;
    for (var j = 0; j < needle.length; j++) {
      if (s[i + j] != needle[j]) return false;
    }
    return true;
  }

  static Object? _coerceBareword(String tok) {
    if (tok.isEmpty) return tok;
    final lower = tok.toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    if (lower == 'null') return null;
    final asInt = int.tryParse(tok);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(tok);
    if (asDouble != null) return asDouble;
    // Strip stray surrounding quotes if any survived.
    if (tok.length >= 2) {
      final first = tok[0];
      final last = tok[tok.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return tok.substring(1, tok.length - 1);
      }
    }
    return tok;
  }

  Future<Map<String, Object?>> _dispatchTool({
    required String name,
    required Map<String, Object?> args,
    required String originalUserText,
  }) async {
    switch (name) {
      case 'record_pain_entry':
        final score = (args['pain_score'] as num?)?.toInt() ?? 0;
        final location = (args['location'] as String?)?.trim() ?? 'unspecified';
        final context = (args['context'] as String?)?.trim() ?? '';
        final now = DateTime.now();
        final entry = PainEntry(
          id: now.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff,
          painScore: score.clamp(0, 10),
          location: location,
          context: context,
          timestamp: now,
          transcript: originalUserText,
        );
        await StorageService.savePainEntry(entry);
        return {
          'ok': true,
          'acknowledgement':
              'Logged: $score/10 at $location. Take it easy today.',
        };

      case 'schedule_reminder':
        final title = (args['title'] as String?) ?? 'Kneedle reminder';
        final body = (args['body'] as String?) ?? '';
        final mins = (args['in_minutes'] as num?)?.toInt() ?? 60;
        final when = DateTime.now().add(Duration(minutes: mins));
        final id = when.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff;
        await NotificationService.scheduleReminder(
          id: id,
          title: title,
          body: body,
          when: when,
        );
        return {
          'ok': true,
          'acknowledgement':
              'Reminder set for ${_formatWhen(when)}: $title.',
        };

      case 'add_medication':
        final medName = (args['name'] as String?)?.trim() ?? '';
        if (medName.isEmpty) {
          return {'ok': false, 'error': 'name_required'};
        }
        final dose = (args['dose'] as String?)?.trim() ?? '';
        final hour = ((args['hour'] as num?)?.toInt() ?? 8).clamp(0, 23);
        final minute = ((args['minute'] as num?)?.toInt() ?? 0).clamp(0, 59);
        final notes = (args['notes'] as String?)?.trim();
        final now = DateTime.now();
        final medId = now.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff;
        final med = Medication(
          id: medId,
          name: medName,
          dose: dose,
          hour: hour,
          minute: minute,
          createdAt: now,
          notes: (notes == null || notes.isEmpty) ? null : notes,
        );
        await StorageService.saveMedication(med);
        await NotificationService.scheduleDaily(
          id: medId,
          title: 'Time for $medName',
          body: dose.isEmpty ? 'Daily reminder' : 'Take $dose',
          hour: hour,
          minute: minute,
        );
        return {
          'ok': true,
          'acknowledgement':
              'Daily reminder set for $medName at ${med.timeLabel}.',
        };

      case 'add_appointment':
        final apptTitle =
            (args['title'] as String?)?.trim() ?? 'Appointment';
        final iso = (args['when_iso'] as String?)?.trim() ?? '';
        DateTime? whenAppt;
        try {
          whenAppt = DateTime.parse(iso);
        } catch (_) {
          whenAppt = null;
        }
        if (whenAppt == null || whenAppt.isBefore(DateTime.now())) {
          return {
            'ok': false,
            'error': 'invalid_or_past_datetime',
            'acknowledgement':
                'I need a future date and time for that appointment. Could you say it again?',
          };
        }
        final apptLoc = (args['location'] as String?)?.trim();
        final apptNotes = (args['notes'] as String?)?.trim();
        final apptId =
            whenAppt.millisecondsSinceEpoch ~/ 1000 & 0x7fffffff;
        final appt = Appointment(
          id: apptId,
          title: apptTitle,
          when: whenAppt,
          createdAt: DateTime.now(),
          location: (apptLoc == null || apptLoc.isEmpty) ? null : apptLoc,
          notes: (apptNotes == null || apptNotes.isEmpty) ? null : apptNotes,
        );
        await StorageService.saveAppointment(appt);
        final notifyAt = whenAppt.subtract(const Duration(hours: 1));
        if (notifyAt.isAfter(DateTime.now())) {
          await NotificationService.scheduleReminder(
            id: apptId,
            title: 'Upcoming: $apptTitle',
            body: apptLoc == null || apptLoc.isEmpty
                ? 'In 1 hour'
                : 'In 1 hour at $apptLoc',
            when: notifyAt,
          );
        }
        return {
          'ok': true,
          'acknowledgement':
              'Saved: $apptTitle on ${_formatDate(whenAppt)} at '
              '${_formatWhen(whenAppt)}.',
        };

      case 'list_medications':
        final meds = StorageService.allMedications();
        return {
          'ok': true,
          'count': meds.length,
          'medications': [for (final m in meds) m.toJson()],
        };

      case 'list_appointments':
        final appts = StorageService.upcomingAppointments();
        return {
          'ok': true,
          'count': appts.length,
          'now': DateTime.now().toIso8601String(),
          'appointments': [for (final a in appts) a.toJson()],
        };

      case 'remove_medication':
        final query = (args['name'] as String?)?.trim().toLowerCase() ?? '';
        if (query.isEmpty) {
          return {
            'ok': false,
            'error': 'name_required',
            'acknowledgement':
                'Which medication should I remove? Tell me the name.',
          };
        }
        final all = StorageService.allMedications();
        final matches =
            all.where((m) => m.name.toLowerCase().contains(query)).toList();
        if (matches.isEmpty) {
          return {
            'ok': false,
            'error': 'not_found',
            'acknowledgement':
                'I don\'t see a medication called "${args['name']}". '
                'Say "list medications" to check what\'s saved.',
          };
        }
        if (matches.length > 1) {
          // Ambiguous — fall through to model (ok=false skips the terminal
          // short-circuit) so it can ask which one. We return the candidates
          // so the follow-up has full context.
          return {
            'ok': false,
            'error': 'ambiguous',
            'candidates': [for (final m in matches) m.toJson()],
            'acknowledgement':
                'You have ${matches.length} medications matching '
                '"${args['name']}": '
                '${matches.map((m) => '${m.name} at ${m.timeLabel}').join(', ')}. '
                'Which one should I remove?',
          };
        }
        final target = matches.single;
        await NotificationService.cancel(target.id);
        await StorageService.deleteMedication(target.id);
        return {
          'ok': true,
          'acknowledgement':
              'Removed your daily reminder for ${target.name} '
              '(${target.timeLabel}).',
        };

      case 'remove_appointment':
        final query = (args['title'] as String?)?.trim().toLowerCase() ?? '';
        if (query.isEmpty) {
          return {
            'ok': false,
            'error': 'title_required',
            'acknowledgement':
                'Which appointment should I remove? Tell me the title.',
          };
        }
        final all = StorageService.upcomingAppointments();
        final matches =
            all.where((a) => a.title.toLowerCase().contains(query)).toList();
        if (matches.isEmpty) {
          return {
            'ok': false,
            'error': 'not_found',
            'acknowledgement':
                'I don\'t see an upcoming appointment matching '
                '"${args['title']}".',
          };
        }
        if (matches.length > 1) {
          return {
            'ok': false,
            'error': 'ambiguous',
            'candidates': [for (final a in matches) a.toJson()],
            'acknowledgement':
                'You have ${matches.length} appointments matching '
                '"${args['title']}": '
                '${matches.map((a) => '${a.title} on ${_formatDate(a.when)} at ${_formatWhen(a.when)}').join(', ')}. '
                'Which one should I remove?',
          };
        }
        final apptTarget = matches.single;
        await NotificationService.cancel(apptTarget.id);
        await StorageService.deleteAppointment(apptTarget.id);
        return {
          'ok': true,
          'acknowledgement':
              'Removed: ${apptTarget.title} on '
              '${_formatDate(apptTarget.when)} at '
              '${_formatWhen(apptTarget.when)}.',
        };

      case 'start_gait_test':
        return {
          'ok': true,
          'nav': 'gait_capture',
          'acknowledgement':
              "Opening the walking test — stand 8 feet from the camera "
              'and tap start when you\'re ready.',
        };

      case 'show_history':
        final weeks = ((args['weeks'] as num?)?.toInt() ?? 4).clamp(1, 12);
        return {
          'ok': true,
          'nav': 'history',
          'weeks': weeks,
          'acknowledgement':
              'Opening your $weeks-week trend view.',
        };

      case 'generate_doctor_report':
        return {
          'ok': true,
          'nav': 'doctor_report',
          'acknowledgement':
              'Building your doctor report — you can share it from the '
              'next screen.',
        };

      default:
        return {'ok': false, 'error': 'unknown_tool:$name'};
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Strip a leading `<think>...</think>` block — matches the backend's
  /// `voice_chat_service.chat` behaviour. The thinking markup leaks through
  /// some Gemma instruction-tuned variants.
  /// Forgiving JSON extractor for on-device Gemma output. Handles:
  ///   * fenced output (```json ... ```),
  ///   * orphan commas between fields (",\n  ,\n  \"key\":"),
  ///   * trailing commas before } or ],
  ///   * truncation mid-array — pads with the right number of }/] closers.
  /// Throws FormatException if no salvageable JSON object can be found.
  static Map<String, Object?> _looseParseJson(String raw) {
    // 1. Drop ```json / ``` fences.
    var s = raw.replaceAll(RegExp(r'```json\s*', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'```'), '');
    // 2. Find the outermost { ... up to the last } we can see; if there's no
    //    closing } at all, start from the first { and let the balancer below
    //    close it.
    final start = s.indexOf('{');
    if (start < 0) throw const FormatException('No JSON object in response');
    var body = s.substring(start);
    final lastClose = body.lastIndexOf('}');
    if (lastClose >= 0) body = body.substring(0, lastClose + 1);

    // 3. Strip C/JS line comments — sometimes the model emits "// note".
    body = body.replaceAll(RegExp(r'//[^\n]*'), '');

    // 4. Repair array elements with a missing opening quote — on-device Gemma
    //    sometimes drops the leading `"` on items 2+ of a JSON array, e.g.
    //      [
    //        "first",
    //        Second item.",          ← missing leading "
    //        Third item."
    //      ]
    //    Pattern: after `,` or `[`, optional whitespace/newline, a letter,
    //    then content ending in `",` or `"\n`/`"\s*]`. We re-insert the `"`.
    body = body.replaceAllMapped(
      RegExp(r'([,\[])(\s*\n\s*)([A-Za-z][^"\n]*?")(\s*[,\]\n])'),
      (m) => '${m[1]}${m[2]}"${m[3]}${m[4]}',
    );

    // 5. Collapse orphan commas — `, ,` or a comma on its own line between
    //    a value and the next key. Also handle the on-device-Gemma quirk
    //    where it emits a stray empty/garbage token between fields, e.g.
    //    `"k": "v",  " ,\n  "next": ...` (an unterminated phantom string).
    //    We drop any `"..."` token that sits between a `,` and a `,`/`"key":`.
    body = body.replaceAll(RegExp(r',\s*"[^"\n]*"\s*,'), ',');
    body = body.replaceAll(RegExp(r',\s*,'), ',');
    body = body.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);

    // 5. If the model was truncated, jsonDecode will throw. Walk the string
    //    and close any open " then any open [ / { in reverse order.
    Map<String, Object?> tryDecode(String candidate) {
      final v = jsonDecode(candidate);
      if (v is Map<String, Object?>) return v;
      if (v is Map) return v.cast<String, Object?>();
      throw const FormatException('Top-level JSON is not an object');
    }

    try {
      return tryDecode(body);
    } catch (_) {
      // 5a. Truncated mid-string: trim back to the last clean "key": value,
      //     drop trailing partial entries, then balance brackets.
      var candidate = body;
      // Trim back to a comma/brace boundary that doesn't sit inside a string.
      final tail =
          RegExp(r'[,{\[]\s*"[^"]*$').firstMatch(candidate);
      if (tail != null) candidate = candidate.substring(0, tail.start);
      // Re-strip trailing commas exposed by the trim.
      candidate = candidate.replaceAll(RegExp(r',\s*$'), '');

      final stack = <String>[];
      var inString = false;
      var escape = false;
      for (final ch in candidate.runes) {
        final c = String.fromCharCode(ch);
        if (escape) {
          escape = false;
          continue;
        }
        if (c == r'\') {
          escape = true;
          continue;
        }
        if (c == '"') {
          inString = !inString;
          continue;
        }
        if (inString) continue;
        if (c == '{' || c == '[') stack.add(c);
        if ((c == '}' || c == ']') && stack.isNotEmpty) stack.removeLast();
      }
      if (inString) candidate += '"';
      for (final open in stack.reversed) {
        candidate += open == '{' ? '}' : ']';
      }
      candidate = candidate.replaceAllMapped(RegExp(r',\s*([}\]])'), (m) => m[1]!);
      return tryDecode(candidate);
    }
  }

  static String _stripThink(String raw) {
    final s = raw.trimLeft();
    if (s.startsWith('<think>') && s.contains('</think>')) {
      return s.substring(s.indexOf('</think>') + '</think>'.length).trim();
    }
    return raw.trim();
  }

  void _ensure() {
    if (!isReady) {
      throw StateError('GemmaService not initialised. Call initialise() first.');
    }
  }

  String _formatWhen(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatDate(DateTime t) => '${_months[t.month - 1]} ${t.day}';

  AnalysisResponse _parseAnalysisJson({
    required String raw,
    required GaitMetrics metrics,
    required List<ExerciseDef> library,
    required String severity,
    required String symBand,
    required String lang,
    required int sessionNumber,
    required SafetyText safety,
  }) {
    // The on-device Gemma sometimes emits malformed JSON: stray commas
    // between fields ("…": "…",\n  ,\n  "next":…), trailing commas before
    // closers, and truncation mid-array when the decode loop ends early.
    // We strip the fences, then run a forgiving normaliser, then attempt to
    // close any unbalanced braces/brackets so jsonDecode succeeds and the
    // safety-defaults layer can patch over whatever the model dropped.
    final data = _looseParseJson(raw);

    // Restrict the model's selection to the severity-filtered library so it
    // can't smuggle a contraindicated exercise back in.
    final allowedIds = {for (final e in library) e.id};
    final picked =
        ((data['selected_exercise_ids'] as List?) ?? const []).cast<Object?>();
    final reasons =
        ((data['exercise_reasons'] as List?) ?? const []).cast<Object?>();

    final exercises = <PrescribedExercise>[];
    final chosenIds = <String>{};
    for (var i = 0; i < picked.length && exercises.length < 4; i++) {
      final id = picked[i]?.toString();
      if (id == null || !allowedIds.contains(id)) continue;
      final def = getExerciseById(id);
      if (def == null) continue;
      final reason = i < reasons.length ? (reasons[i]?.toString() ?? '') : '';
      exercises.add(PrescribedExercise(def: def, reason: reason));
      chosenIds.add(id);
    }

    // Guarantee one safe (contraindication == "None") entry.
    final hasSafe = exercises.any((e) => e.def.contraindication == 'None');
    if (!hasSafe) {
      final safeCand = exerciseLibrary.firstWhere(
        (e) =>
            e.contraindication == 'None' && !chosenIds.contains(e.id),
        orElse: () => exerciseLibrary.first,
      );
      exercises.add(PrescribedExercise(def: safeCand, reason: ''));
      chosenIds.add(safeCand.id);
    }

    // Top up to at least 3 from the severity-filtered library.
    if (exercises.length < 3) {
      for (final cand in library) {
        if (chosenIds.contains(cand.id)) continue;
        exercises.add(PrescribedExercise(def: cand, reason: ''));
        chosenIds.add(cand.id);
        if (exercises.length >= 3) break;
      }
    }

    String localized(String key, String fallback) {
      final v = data[key];
      if (v is String && v.trim().isNotEmpty) return v;
      return fallback;
    }

    final symDefault = switch (symBand) {
      'good' => safety.symGood,
      'fair' => safety.symFair,
      'poor' => safety.symPoor,
      _ => safety.symUnknown,
    };
    final symDefaultEn = switch (symBand) {
      'good' => safetyEn.symGood,
      'fair' => safetyEn.symFair,
      'poor' => safetyEn.symPoor,
      _ => safetyEn.symUnknown,
    };

    final referralRecommended = severity == 'severe';
    final referralText = referralRecommended ? safety.referralSevere : '';
    final referralTextEn = referralRecommended ? safetyEn.referralSevere : '';

    return AnalysisResponse(
      observation: (data['observation'] as String?) ?? '',
      observationEn: (data['observation_en'] as String?) ?? '',
      fixTitle: (data['fix_title'] as String?) ?? '',
      fixDesc: (data['fix_desc'] as String?) ?? '',
      fixTitleEn: (data['fix_title_en'] as String?) ?? '',
      fixDescEn: (data['fix_desc_en'] as String?) ?? '',
      exercises: exercises,
      activeJoint:
          (data['active_joint'] as String?) ?? getActiveJoint(metrics),
      symmetryScore: metrics.symmetryScore ?? 0,
      sessionNumber: sessionNumber,
      thinking: data['thinking_summary'] as String?,
      metrics: metrics,
      severity: severity,
      symmetryBand: symBand,
      symmetryMeaning: localized('symmetry_meaning', symDefault),
      symmetryMeaningEn: localized('symmetry_meaning_en', symDefaultEn),
      empathyLine: localized('empathy_line', safety.empathy),
      empathyLineEn: localized('empathy_line_en', safetyEn.empathy),
      frequency: localized('frequency', safety.frequency),
      frequencyEn: localized('frequency_en', safetyEn.frequency),
      painRule: localized('pain_rule', safety.painRule),
      painRuleEn: localized('pain_rule_en', safetyEn.painRule),
      redFlags: localized('red_flags', safety.redFlags),
      redFlagsEn: localized('red_flags_en', safetyEn.redFlags),
      referralRecommended: referralRecommended,
      referralText: referralText,
      referralTextEn: referralTextEn,
      complementaryActions:
          localized('complementary_actions', safety.complementary),
      complementaryActionsEn:
          localized('complementary_actions_en', safetyEn.complementary),
      klProxyGrade: metrics.klProxyGrade,
      clinicalFlags: metrics.clinicalFlags,
      bilateralPatternDetected: metrics.bilateralPatternDetected,
      primaryViewConfidence: metrics.confidence,
    );
  }

  /// Severity-aware hardcoded fallback. 1:1 with `_fallback_response` in
  /// `gemma_client.py` — guarantees the patient still gets a usable plan when
  /// the model is unreachable or outputs unparseable text.
  AnalysisResponse _fallbackAnalysis({
    required GaitMetrics metrics,
    required String lang,
    required int sessionNumber,
    required String error,
  }) {
    final severity = assessSeverity(metrics);
    final symBand = computeSymmetryBand(metrics.symmetryScore);
    final safety = safetyFor(lang);

    String obs;
    String obsEn;
    String fixT;
    String fixD;
    String fixTEn;
    String fixDEn;

    switch (lang) {
      case 'bn':
        obs = 'আপনার হাঁটার ধরন বিশ্লেষণ করা হয়েছে। ডান হাঁটুতে কিছুটা বেশি চাপ পড়ছে।';
        obsEn =
            'Your gait has been analysed. Your right knee is taking slightly more load.';
        fixT = 'পায়ের আঙুল সামান্য বাইরে রাখুন';
        fixD =
            'হাঁটার সময় পায়ের আঙুল ১০° বাইরের দিকে রাখুন। এতে হাঁটুর চাপ কমবে।';
        fixTEn = 'Point toes slightly outward';
        fixDEn =
            'While walking, point your toes 10° outward. This reduces knee load.';
        break;
      case 'hi':
        obs = 'आपकी चाल का विश्लेषण किया गया है। दाएं घुटने पर थोड़ा अधिक दबाव है।';
        obsEn =
            'Your gait has been analysed. Your right knee is taking slightly more load.';
        fixT = 'पैर की उंगलियां थोड़ी बाहर रखें';
        fixD =
            'चलते समय पैर की उंगलियां १०° बाहर की तरफ रखें। इससे घुटने का दबाव कम होगा।';
        fixTEn = 'Point toes slightly outward';
        fixDEn = 'While walking, point your toes 10° outward.';
        break;
      default:
        obs =
            'Your gait has been analysed. Your right knee is taking slightly more load than the left.';
        obsEn = obs;
        fixT = 'Point toes slightly outward';
        fixD =
            'While walking, point your toes 10° outward. This reduces the load on your knee.';
        fixTEn = fixT;
        fixDEn = fixD;
    }

    final fallbackIds = switch (severity) {
      'severe' => const ['quad_set', 'seated_marching', 'heel_slide'],
      'moderate' => const [
          'seated_marching',
          'straight_leg_raise',
          'side_lying_hip_abduction',
        ],
      _ => const ['seated_marching', 'straight_leg_raise', 'calf_raise'],
    };
    final exercises = <PrescribedExercise>[
      for (final id in fallbackIds)
        if (getExerciseById(id) != null)
          PrescribedExercise(def: getExerciseById(id)!, reason: ''),
    ];

    final symMeaning = switch (symBand) {
      'good' => safety.symGood,
      'fair' => safety.symFair,
      'poor' => safety.symPoor,
      _ => safety.symUnknown,
    };
    final symMeaningEn = switch (symBand) {
      'good' => safetyEn.symGood,
      'fair' => safetyEn.symFair,
      'poor' => safetyEn.symPoor,
      _ => safetyEn.symUnknown,
    };

    final referralRecommended = severity == 'severe';

    return AnalysisResponse(
      observation: obs,
      observationEn: obsEn,
      fixTitle: fixT,
      fixDesc: fixD,
      fixTitleEn: fixTEn,
      fixDescEn: fixDEn,
      exercises: exercises,
      activeJoint: getActiveJoint(metrics),
      symmetryScore: metrics.symmetryScore ?? 50,
      sessionNumber: sessionNumber,
      thinking: 'Fallback used due to: $error',
      metrics: metrics,
      severity: severity,
      symmetryBand: symBand,
      symmetryMeaning: symMeaning,
      symmetryMeaningEn: symMeaningEn,
      empathyLine: safety.empathy,
      empathyLineEn: safetyEn.empathy,
      frequency: safety.frequency,
      frequencyEn: safetyEn.frequency,
      painRule: safety.painRule,
      painRuleEn: safetyEn.painRule,
      redFlags: safety.redFlags,
      redFlagsEn: safetyEn.redFlags,
      referralRecommended: referralRecommended,
      referralText: referralRecommended ? safety.referralSevere : '',
      referralTextEn: referralRecommended ? safetyEn.referralSevere : '',
      complementaryActions: safety.complementary,
      complementaryActionsEn: safetyEn.complementary,
      klProxyGrade: metrics.klProxyGrade,
      clinicalFlags: metrics.clinicalFlags,
      bilateralPatternDetected: metrics.bilateralPatternDetected,
      primaryViewConfidence: metrics.confidence,
    );
  }

  Future<void> dispose() async {
    await _model?.close();
    _chat = null;
    _model = null;
  }
}

/// Persistent chat session preloaded with one patient's gait analysis. Backs
/// [GemmaService.openGaitChat] — owns an [InferenceChat] that lives for the
/// duration of the gait-result Q&A screen. Call [close] on screen dispose to
/// release the underlying KV cache (~150–250 MB on Gemma 4 E2B INT4).
/// One executed function call, captured for the Agent screen's tool timeline.
/// Plain data — never holds references to Gemma internals or UI state.
class AgentToolCall {
  AgentToolCall({
    required this.name,
    required this.args,
    required this.result,
  });

  /// Tool name as defined in `_toolDefinitions` (e.g. `record_pain_entry`).
  final String name;

  /// Args the model emitted. Already de-typed to `Map<String, Object?>`.
  final Map<String, Object?> args;

  /// Dispatcher result. Reliable fields:
  ///   * `ok` (bool) — true on success.
  ///   * `acknowledgement` (String?) — user-facing one-line summary.
  ///   * `nav` (String?) — set by navigation-intent tools
  ///     (`start_gait_test` → 'gait_capture', `show_history` → 'history',
  ///     `generate_doctor_report` → 'doctor_report').
  final Map<String, Object?> result;

  bool get ok => result['ok'] == true;
  String? get acknowledgement => result['acknowledgement'] as String?;
  String? get nav => result['nav'] as String?;
}

class GaitChatSession {
  GaitChatSession._({
    required InferenceChat chat,
    required Future<void> warmupFuture,
  })  : _chat = chat,
        _warmupFuture = warmupFuture;

  final InferenceChat _chat;
  final Future<void> _warmupFuture;
  bool _disposed = false;

  /// Stats from the most recent `ask` call. Surfaced in the chat UI's
  /// assistant bubble so the patient (and developer) can see decode speed.
  LlmStats? lastStats;

  /// Last retrieval result for the most recent `ask` call. The chat UI reads
  /// this to render the citation chips below the assistant bubble. Reset on
  /// every call; empty result on a query the retriever doesn't hit.
  KbRetrievalResult lastRetrieval = const KbRetrievalResult(
    hits: [],
    evidenceBlock: '',
  );

  /// Ask one question. Waits for the background warmup to finish on the very
  /// first call, then prefills only the new user message + previous reply —
  /// the system prompt + gait context are already in the KV cache. Streams
  /// the reply, optionally emitting partials via [onChunk]; populates
  /// [lastStats] before returning.
  ///
  /// RAG: before sending the user turn we run [Retriever.retrieve] over the
  /// raw question; any hits are spliced into the prompt as an EVIDENCE block
  /// that the system prompt's citation rule references. On miss we send the
  /// user text verbatim and the model answers without citations.
  Future<String> ask(
    String userText, {
    void Function(String partial, LlmStats stats)? onChunk,
  }) async {
    if (_disposed) {
      throw StateError('GaitChatSession is closed');
    }
    if (userText.trim().isEmpty) return '';
    // Block on the warmup prefill before the first user turn; on every later
    // turn this future is already complete so it's a no-op.
    await _warmupFuture;

    final retrieval = Retriever.retrieve(userText, k: 3);
    lastRetrieval = retrieval;
    final composed = retrieval.isEmpty
        ? userText
        : '${retrieval.evidenceBlock}\n\nPATIENT ASKS:\n$userText';
    // ignore: avoid_print
    print('[GaitChatSession] ask INPUT (${userText.length} chars, '
        'evidence=${retrieval.hits.length}): $userText');

    final prefillSw = Stopwatch()..start();
    await _chat.addQueryChunk(Message.text(text: composed, isUser: true));
    prefillSw.stop();

    final stats = LlmStats(inputChars: userText.length);
    final firstTokenSw = Stopwatch()..start();
    final genSw = Stopwatch()..start();
    final buf = StringBuffer();
    await for (final r in _chat.generateChatResponseAsync()) {
      if (r is TextResponse) {
        if (firstTokenSw.isRunning) {
          firstTokenSw.stop();
          stats.firstTokenMs = firstTokenSw.elapsedMilliseconds;
          stats.prefillMs =
              prefillSw.elapsedMilliseconds + stats.firstTokenMs;
          genSw
            ..reset()
            ..start();
        }
        buf.write(r.token);
        stats.outputTokens++;
        stats.outputChars = buf.length;
        stats.generationMs = genSw.elapsedMilliseconds;
        if (stats.outputTokens % 3 == 0) {
          onChunk?.call(buf.toString(), stats);
        }
      }
    }
    genSw.stop();
    if (firstTokenSw.isRunning) {
      firstTokenSw.stop();
      stats.firstTokenMs = firstTokenSw.elapsedMilliseconds;
      stats.prefillMs =
          prefillSw.elapsedMilliseconds + stats.firstTokenMs;
    }
    final text = GemmaService._stripThink(buf.toString());
    stats.outputChars = text.length;
    lastStats = stats;
    // ignore: avoid_print
    print('[GaitChatSession] ask OUTPUT (${text.length} chars): $text');
    // ignore: avoid_print
    print('[GaitChatSession] ask STATS ${stats.summary()}');
    onChunk?.call(text, stats);
    return text;
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    try {
      // ignore: avoid_dynamic_calls
      await (_chat as dynamic).close();
    } catch (_) {/* InferenceChat variants disagree on close API */}
  }
}
