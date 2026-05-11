import 'constants.dart';
import 'geometry.dart';

/// Find heel-strike events as peaks in the ankle-Y series (image coords, Y↓).
///
/// Port of `detect_heel_strikes` (gait_analyzer.py), including the
/// scipy.signal.find_peaks parameters: minimum inter-peak distance and a
/// prominence threshold of 0.015 (1.5 % of frame height) — calibrated for
/// elderly / OA shuffling gait where ankle lift is 2–4 % of frame.
List<int> detectHeelStrikes(
  List<double> ankleY,
  List<double> visibility, {
  double sampleFps = GaitConst.targetSampleFps,
}) {
  if (ankleY.length < 3) return const [];
  final smoothed = smooth(ankleY);
  final minDistance = (sampleFps * 0.35).round().clamp(3, 1 << 30);
  const prominence = 0.015;
  final peaks = _findPeaks(smoothed, minDistance: minDistance, prominence: prominence);
  return [
    for (final p in peaks)
      if (p < visibility.length && visibility[p] > GaitConst.minLandmarkVis) p,
  ];
}

/// Minimal port of scipy.signal.find_peaks for the 1-D real-valued case used
/// here. Implements the two arguments we actually depend on:
///
/// * `distance` — minimum number of samples between successive peaks. Lower
///   peaks are dropped first when conflicts arise (matches scipy).
/// * `prominence` — peak's vertical drop to the next higher base on either side.
///
/// Edges are NOT considered peaks (matches scipy default behaviour for plateaus
/// of length 1; we additionally treat plateaus by selecting the centre index).
List<int> _findPeaks(
  List<double> x, {
  required int minDistance,
  required double prominence,
}) {
  final n = x.length;
  if (n < 3) return const [];

  // 1. Locate all local maxima (handle flat plateaus by using the midpoint).
  final raw = <int>[];
  var i = 1;
  while (i < n - 1) {
    if (x[i - 1] < x[i]) {
      // Walk over a plateau.
      var iAhead = i + 1;
      while (iAhead < n - 1 && x[iAhead] == x[i]) {
        iAhead++;
      }
      if (x[iAhead] < x[i]) {
        final mid = (i + iAhead - 1) ~/ 2;
        raw.add(mid);
        i = iAhead;
        continue;
      }
      i = iAhead;
    } else {
      i++;
    }
  }
  if (raw.isEmpty) return const [];

  // 2. Compute prominence for each candidate peak.
  bool keepProminence(int p) {
    final h = x[p];
    // Walk left to first sample whose value >= h, tracking the lowest min.
    var lMin = h;
    for (var k = p - 1; k >= 0; k--) {
      if (x[k] > h) break;
      if (x[k] < lMin) lMin = x[k];
    }
    var rMin = h;
    for (var k = p + 1; k < n; k++) {
      if (x[k] > h) break;
      if (x[k] < rMin) rMin = x[k];
    }
    final base = lMin > rMin ? lMin : rMin;
    return (h - base) >= prominence;
  }

  final byProm = <int>[for (final p in raw) if (keepProminence(p)) p];
  if (byProm.isEmpty) return const [];

  // 3. Enforce minimum distance — drop the smaller of any too-close pair.
  // Sort by height descending; greedily keep, marking neighbours invalid.
  final sortedByHeight = List<int>.from(byProm)
    ..sort((a, b) => x[b].compareTo(x[a]));
  final kept = <bool>[for (final _ in byProm) true];
  final indexOf = <int, int>{
    for (var k = 0; k < byProm.length; k++) byProm[k]: k,
  };
  for (final p in sortedByHeight) {
    final idx = indexOf[p]!;
    if (!kept[idx]) continue;
    for (var k = 0; k < byProm.length; k++) {
      if (k == idx || !kept[k]) continue;
      if ((byProm[k] - p).abs() < minDistance) kept[k] = false;
    }
  }
  final out = <int>[
    for (var k = 0; k < byProm.length; k++) if (kept[k]) byProm[k],
  ]..sort();
  return out;
}

/// Map sampled-frame index → gait phase label for one side.
/// Returns an empty map when fewer than 2 heel strikes were detected.
Map<int, String> labelPhases(int nFrames, List<int> hsIndices) {
  final out = <int, String>{};
  if (hsIndices.length < 2) return out;
  for (var i = 0; i < hsIndices.length - 1; i++) {
    final hs = hsIndices[i];
    final nextHs = hsIndices[i + 1];
    final cycleLen = nextHs - hs;
    if (cycleLen <= 0) continue;
    for (var f = hs; f < nextHs; f++) {
      out[f] = phaseForPct((f - hs) / cycleLen * 100);
    }
  }
  return out;
}
