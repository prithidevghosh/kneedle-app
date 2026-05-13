import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma/flutter_gemma.dart';

import '../clinical/prompts.dart';
import '../clinical/safety_defaults.dart';
import '../clinical/severity.dart';
import '../data/exercise_library.dart';
import '../gait/pipeline.dart';
import '../models/analysis_response.dart';
import '../models/appointment.dart';
import '../models/medication.dart';
import '../models/pain_entry.dart';
import 'notification_service.dart';
import 'storage_service.dart';

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

  // Vision path is disabled — gait analysis is text-only (metrics + library),
  // and the companion chat doesn't accept images. Keeping this off reduces
  // model memory and avoids loading the vision encoder.
  static const _supportImage = false;

  InferenceModel? _model;
  InferenceChat? _chat;
  String? _systemPrompt;
  bool _initialising = false;

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
      enableSpeculativeDecoding: _useSpeculativeDecoding ? true : null,
    );
  }

  // ─── Companion: free chat ────────────────────────────────────────────────

  Future<String> chat(String userText) async {
    _ensure();
    await _chat!.addQueryChunk(Message.text(text: userText, isUser: true));
    final response = await _chat!.generateChatResponse();
    return _handleResponse(response, originalUserText: userText);
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
  /// Text-only: the model receives metrics + the severity-filtered exercise
  /// library, never raw video frames. Vision tokens add ~600 prefill tokens
  /// per frame on E2B and didn't measurably improve picks in our tests.
  Future<AnalysisResponse> analyseGait({
    required GaitMetrics metrics,
    required String age,
    required String knee,
    required String lang,
    required int sessionNumber,
  }) async {
    final severity = assessSeverity(metrics);
    final symBand = computeSymmetryBand(metrics.symmetryScore);
    final library = filterLibraryBySeverity(severity);
    final safety = safetyFor(lang);

    final systemPrompt = buildAnalysisSystemPrompt(lang);
    final userPrompt = buildAnalysisUserPrompt(
      metrics: metrics,
      age: age,
      knee: knee,
      severity: severity,
      library: library,
    );

    try {
      _ensure();

      // Use a fresh chat session so the analysis prompt isn't polluted by the
      // companion conversation history. The model is shared; sessions are not.
      final session = await _model!.createChat(
        temperature: 0.4,
        topK: 40,
        topP: 0.9,
        // Function calling explicitly OFF — clinical mode wants strict JSON.
        supportsFunctionCalls: false,
        tools: const [],
      );
      try {
        await session.addQueryChunk(
          Message.text(text: systemPrompt, isUser: true),
        );
        await session.addQueryChunk(
          Message.text(text: userPrompt, isUser: true),
        );
        // ignore: avoid_print
        print('[GemmaService] analyseGait prefill payload (text-only): '
            'system=${systemPrompt.length} chars, '
            'user=${userPrompt.length} chars');
        final raw = await session.generateChatResponse();
        final text = raw is TextResponse ? raw.token : raw.toString();
        return _parseAnalysisJson(
          raw: text,
          metrics: metrics,
          library: library,
          severity: severity,
          symBand: symBand,
          lang: lang,
          sessionNumber: sessionNumber,
          safety: safety,
        );
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
      await session.addQueryChunk(Message.text(text: sys, isUser: true));
      for (final m in trimHistory(history)) {
        final isUser = m['role'] == 'user';
        await session.addQueryChunk(
          Message.text(text: m['content'] ?? '', isUser: isUser),
        );
      }
      await session.addQueryChunk(Message.text(text: userText, isUser: true));
      final response = await session.generateChatResponse();
      final raw = response is TextResponse ? response.token : response.toString();
      return _stripThink(raw);
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
  };

  Future<String> _handleResponse(
    ModelResponse response, {
    required String originalUserText,
  }) async {
    if (response is TextResponse) return _stripThink(response.token);
    if (response is FunctionCallResponse) {
      final toolResult = await _dispatchTool(
        name: response.name,
        args: response.args,
        originalUserText: originalUserText,
      );
      // Buffer the tool response into the chat so the next user turn has
      // full context, but skip the follow-up generate for terminal tools —
      // their `acknowledgement` is already a complete, user-facing sentence
      // and re-running the model to paraphrase it costs 10–15s on CPU.
      await _chat!.addQueryChunk(
        Message.toolResponse(toolName: response.name, response: toolResult),
      );
      final ack = toolResult['acknowledgement'] as String?;
      final ok = toolResult['ok'] == true;
      if (ok &&
          ack != null &&
          ack.isNotEmpty &&
          _terminalAckTools.contains(response.name)) {
        return ack;
      }
      final follow = await _chat!.generateChatResponse();
      if (follow is TextResponse) return _stripThink(follow.token);
      return ack ?? '';
    }
    return '';
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
class GaitChatSession {
  GaitChatSession._({
    required InferenceChat chat,
    required Future<void> warmupFuture,
  })  : _chat = chat,
        _warmupFuture = warmupFuture;

  final InferenceChat _chat;
  final Future<void> _warmupFuture;
  bool _disposed = false;

  /// Ask one question. Waits for the background warmup to finish on the very
  /// first call, then prefills only the new user message + previous reply —
  /// the system prompt + gait context are already in the KV cache.
  Future<String> ask(String userText) async {
    if (_disposed) {
      throw StateError('GaitChatSession is closed');
    }
    if (userText.trim().isEmpty) return '';
    // Block on the warmup prefill before the first user turn; on every later
    // turn this future is already complete so it's a no-op.
    await _warmupFuture;
    await _chat.addQueryChunk(Message.text(text: userText, isUser: true));
    final response = await _chat.generateChatResponse();
    if (response is TextResponse) return GemmaService._stripThink(response.token);
    return '';
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
