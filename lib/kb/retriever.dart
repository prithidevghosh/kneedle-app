import 'kb_index.dart';

/// Thin convenience wrapper around [KbIndex] for the chat / agent layers.
/// Lives in its own file so the prompt-building code doesn't need to know
/// about BM25 internals — it just calls `Retriever.evidenceBlock(query)` and
/// gets back a string ready to splice into the user turn.
class Retriever {
  Retriever._();

  /// Retrieve up to [k] chunks for [query] and return both the structured
  /// hits and the rendered EVIDENCE block that should be prepended to the
  /// user's message. Returns an empty result on miss; callers should NOT
  /// fabricate evidence in that case.
  static KbRetrievalResult retrieve(
    String query, {
    int k = 3,
  }) {
    if (!KbIndex.isLoaded) {
      return const KbRetrievalResult(hits: [], evidenceBlock: '');
    }
    final hits = KbIndex.instance.search(query, k: k);
    if (hits.isEmpty) {
      return const KbRetrievalResult(hits: [], evidenceBlock: '');
    }
    final lines = <String>[
      'EVIDENCE — cite by stable id in square brackets, e.g. [${hits.first.chunk.id}].',
      'You MAY cite ONLY these ids. Do NOT invent ids.',
      '',
    ];
    for (final h in hits) {
      final c = h.chunk;
      lines.add('[${c.id}] ${c.source} — ${c.title}: ${c.text}');
    }
    return KbRetrievalResult(
      hits: hits,
      evidenceBlock: lines.join('\n'),
    );
  }

  /// All known stable ids — exposed so the renderer can filter out any
  /// `[ID]` tokens the model invented.
  static Set<String> get knownIds =>
      KbIndex.isLoaded ? KbIndex.instance.knownIds : const {};

  /// Resolve a single id to its chunk, or null if unknown.
  static KbChunk? byId(String id) =>
      KbIndex.isLoaded ? KbIndex.instance.byId(id) : null;
}

class KbRetrievalResult {
  const KbRetrievalResult({required this.hits, required this.evidenceBlock});
  final List<KbHit> hits;

  /// Ready-to-splice prompt fragment. Empty string when no chunks scored
  /// above the BM25 threshold — callers MUST treat empty as "do not cite".
  final String evidenceBlock;

  bool get isEmpty => hits.isEmpty;
}
