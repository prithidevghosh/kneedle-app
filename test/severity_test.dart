import 'package:flutter_test/flutter_test.dart';
import 'package:kneedle/clinical/severity.dart';
import 'package:kneedle/data/exercise_library.dart';
import 'package:kneedle/gait/pipeline.dart';

GaitMetrics _m({
  String klGrade = 'kl_0',
  double? sym,
  double lean = 0,
  double diff = 0,
  double cad = 100,
}) =>
    GaitMetrics(
      klProxyGrade: klGrade,
      symmetryScore: sym,
      trunkLeanAngle: lean,
      kneeAngleDiff: diff,
      cadence: cad,
    );

void main() {
  group('assessSeverity — KL precedence', () {
    test('kl_0 → normal', () => expect(assessSeverity(_m()), 'normal'));
    test('kl_2 → moderate',
        () => expect(assessSeverity(_m(klGrade: 'kl_2')), 'moderate'));
    test('kl_4 → severe',
        () => expect(assessSeverity(_m(klGrade: 'kl_4')), 'severe'));
  });

  group('assessSeverity — legacy heuristics when KL absent', () {
    test('low symmetry → severe', () {
      // Use unrecognised KL grade so the fallback path runs.
      expect(assessSeverity(_m(klGrade: 'unknown', sym: 50)), 'severe');
    });
    test('lean > 4° → moderate', () {
      expect(assessSeverity(_m(klGrade: 'unknown', lean: 6)), 'moderate');
    });
    test('clean → mild',
        () => expect(assessSeverity(_m(klGrade: 'unknown')), 'mild'));
  });

  group('computeSymmetryBand', () {
    test('null → unknown', () => expect(computeSymmetryBand(null), 'unknown'));
    test('85 → good', () => expect(computeSymmetryBand(85), 'good'));
    test('70 → fair', () => expect(computeSymmetryBand(70), 'fair'));
    test('50 → poor', () => expect(computeSymmetryBand(50), 'poor'));
  });

  group('filterLibraryBySeverity', () {
    test('severe excludes weight-bearing', () {
      final lib = filterLibraryBySeverity('severe');
      final ids = {for (final e in lib) e.id};
      for (final excluded in severeExcludeIds) {
        expect(ids, isNot(contains(excluded)));
      }
    });
    test('mild keeps full library', () {
      expect(
        filterLibraryBySeverity('mild').length,
        exerciseLibrary.length,
      );
    });
  });
}
