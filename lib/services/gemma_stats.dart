/// Telemetry for one Gemma generation call. Captured alongside every
/// `analyseGait`, `chat`, and `GaitChatSession.ask` invocation so the UI can
/// surface tokens-per-second readouts and the console logs carry a uniform
/// "how fast did this go" footprint.
///
/// Token counts are derived from the streaming chunk count
/// (`generateChatResponseAsync` yields roughly one `TextResponse` per token),
/// which is exact enough for a TPS readout without paying an extra
/// `sizeInTokens` round-trip per call.
class LlmStats {
  LlmStats({
    this.inputChars = 0,
    this.imageCount = 0,
    this.outputChars = 0,
    this.outputTokens = 0,
    this.prefillMs = 0,
    this.firstTokenMs = 0,
    this.generationMs = 0,
  });

  /// Sum of system + user prompt characters fed into prefill.
  int inputChars;

  /// Number of images attached to the prompt (each ≈ 600 prefill tokens on
  /// Gemma 4 E2B vision, so this is the most expensive multiplier).
  int imageCount;

  /// Length of the final assistant text in characters.
  int outputChars;

  /// Streamed token chunks counted from `generateChatResponseAsync`. Roughly
  /// 1 chunk = 1 BPE token on flutter_gemma.
  int outputTokens;

  /// Wall time from `addQueryChunk` finish to the start of streaming —
  /// dominated by native prefill of the user turn (+ vision encoder if any
  /// images were attached).
  int prefillMs;

  /// Wall time from `addQueryChunk` finish to the first emitted token —
  /// useful for distinguishing "model is slow to think" vs "decode is slow".
  int firstTokenMs;

  /// Wall time spent actually streaming tokens, after the first token.
  int generationMs;

  int get totalMs => prefillMs + generationMs;

  /// Decode throughput, after first token. We deliberately exclude prefill
  /// from this number so the readout reflects on-device generation speed,
  /// matching how `ollama` and most local-inference UIs report it.
  double get tokensPerSecond =>
      generationMs > 0 ? outputTokens * 1000.0 / generationMs : 0;

  /// One-line summary suitable for both a SnackBar and a developer log.
  String summary() =>
      '$outputTokens tok in ${generationMs}ms '
      '(${tokensPerSecond.toStringAsFixed(1)} tok/s · '
      'prefill ${prefillMs}ms · ttft ${firstTokenMs}ms)';

  Map<String, Object?> toMap() => {
        'input_chars': inputChars,
        'image_count': imageCount,
        'output_chars': outputChars,
        'output_tokens': outputTokens,
        'prefill_ms': prefillMs,
        'first_token_ms': firstTokenMs,
        'generation_ms': generationMs,
        'tps': tokensPerSecond,
      };
}

/// Progress event emitted by `analyseGait` so the capture screen can switch
/// from a blank spinner to an animated stage-by-stage walkthrough.
class GemmaAnalysisEvent {
  GemmaAnalysisEvent({
    required this.stage,
    this.message = '',
    this.partial = '',
    this.stats,
  });

  /// One of: `prepare`, `prefill`, `streaming`, `parse`, `done`, `fallback`.
  final String stage;

  /// Human-friendly label for the current stage ("Reading frames", "Asking
  /// Gemma to interpret the numbers", "Building your plan").
  final String message;

  /// Partial assistant output as streamed so far. Empty during non-streaming
  /// stages. Used by the analysing screen to render a live "thinking" panel.
  final String partial;

  /// Latest token-stats snapshot. Non-null once streaming has begun.
  final LlmStats? stats;
}
