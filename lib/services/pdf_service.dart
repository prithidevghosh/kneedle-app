import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/exercise_session.dart';
import '../models/gait_session.dart';
import '../models/pain_entry.dart';

/// Generates a single-page doctor-ready PDF summary from local Hive data.
/// No upload, no rendering server — `pdf` is pure Dart.
class PdfService {
  PdfService._();

  static Future<File> generate({
    required List<PainEntry> painEntries,
    required List<GaitSession> gaitSessions,
    required List<ExerciseSession> exerciseSessions,
    String patientName = 'Kneedle user',
  }) async {
    final doc = pw.Document();
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final latestGait = gaitSessions.isEmpty ? null : gaitSessions.first;
    final painCount = painEntries.length;
    final avgPain = painEntries.isEmpty
        ? 0.0
        : painEntries.map((e) => e.painScore).reduce((a, b) => a + b) /
            painEntries.length;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Kneedle — clinician summary',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                )),
            pw.Text('Generated $today  •  $patientName',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)),
            pw.Divider(),
            pw.SizedBox(height: 6),
            _section('Gait — most recent session', [
              if (latestGait == null)
                'No gait sessions recorded yet.'
              else ...[
                'Date: ${df.format(latestGait.timestamp)}',
                'KL proxy grade: ${latestGait.klGrade} '
                    '(score ${latestGait.klScore.toStringAsFixed(1)})',
                'Severity tier (patient-facing): ${latestGait.severity}',
                'Symmetry score: '
                    '${latestGait.symmetryScore?.toStringAsFixed(1) ?? "n/a"} / 100',
                'Cadence: '
                    '${latestGait.cadence?.toStringAsFixed(0) ?? "n/a"} steps/min',
                'Static varus/valgus deviation '
                    '(R/L, % leg length): '
                    '${latestGait.rightStaticAlignmentDeviation.toStringAsFixed(1)} / '
                    '${latestGait.leftStaticAlignmentDeviation.toStringAsFixed(1)}',
                'Double-support ratio: '
                    '${latestGait.doubleSupportRatio.toStringAsFixed(1)} %',
                'Bilateral pattern: '
                    '${latestGait.bilateralPattern ? "yes" : "no"}',
                if (latestGait.clinicalFlags.isNotEmpty)
                  'Flags: ${latestGait.clinicalFlags.join(", ")}',
                'Capture confidence: '
                    '${(latestGait.confidence * 100).toStringAsFixed(0)}%',
              ],
            ]),
            pw.SizedBox(height: 8),
            _section('Pain journal — last 14 days', [
              'Entries logged: $painCount',
              'Mean pain rating: ${avgPain.toStringAsFixed(1)} / 10',
              if (painEntries.isNotEmpty)
                ..._tableRows(painEntries.take(10).toList(), df),
            ]),
            pw.SizedBox(height: 8),
            _section('Exercise adherence', [
              'Sessions completed: ${exerciseSessions.length}',
              if (exerciseSessions.isNotEmpty)
                'Last session: '
                    '${exerciseSessions.first.exerciseName}, '
                    '${exerciseSessions.first.repsCompleted} reps, '
                    '${df.format(exerciseSessions.first.timestamp)}',
            ]),
            pw.Spacer(),
            pw.Divider(),
            pw.Text(
              'Generated on-device by Kneedle. No data was sent to any server.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ],
        ),
      ),
    );

    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/kneedle_report_$today.pdf');
    await f.writeAsBytes(await doc.save(), flush: true);
    return f;
  }

  static List<String> _tableRows(List<PainEntry> entries, DateFormat df) => [
        for (final e in entries)
          '${df.format(e.timestamp)}  •  ${e.painScore}/10  •  '
              '${e.location}${e.context.isEmpty ? "" : " — ${e.context}"}',
      ];

  static pw.Widget _section(String title, List<Object> lines) {
    final widgets = <pw.Widget>[
      pw.Text(title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          )),
      pw.SizedBox(height: 4),
    ];
    for (final l in lines) {
      if (l is pw.Widget) {
        widgets.add(l);
      } else {
        widgets.add(pw.Text(l.toString(),
            style: const pw.TextStyle(fontSize: 10.5)));
      }
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: widgets,
    );
  }

  static Future<void> shareReport(File f) async {
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/pdf')],
      subject: 'Kneedle clinician summary',
    );
  }
}
