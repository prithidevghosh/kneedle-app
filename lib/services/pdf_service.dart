import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/exercise_session.dart';
import '../models/gait_session.dart';
import '../models/pain_entry.dart';

/// Generates a clinical-style PDF assessment report from local Hive data.
///
/// Layout is modelled on real-world physiotherapy / movement-analysis
/// reports: identifying header, patient block, clinical impression,
/// objective measures table (with reference ranges + status), narrative
/// observations, pain trajectory log, exercise adherence, recommendations,
/// and a per-page footer with disclaimer and page numbering.
class PdfService {
  PdfService._();

  // ── Brand palette tuned for print legibility ───────────────────────────
  static const _ink = PdfColor.fromInt(0xFF1F2933);
  static const _inkMuted = PdfColor.fromInt(0xFF52606D);
  static const _hairline = PdfColor.fromInt(0xFFD7DBE0);
  static const _bandFill = PdfColor.fromInt(0xFFF3F5F7);
  static const _bandStripe = PdfColor.fromInt(0xFFFAFBFC);
  static const _accent = PdfColor.fromInt(0xFF1F4D5C); // teal-slate
  static const _accentSoft = PdfColor.fromInt(0xFFE5EEF1);
  static const _good = PdfColor.fromInt(0xFF1F7A4D);
  static const _watch = PdfColor.fromInt(0xFF8E5B0A);
  static const _concern = PdfColor.fromInt(0xFFB23B2A);

  static Future<File> generate({
    required List<PainEntry> painEntries,
    required List<GaitSession> gaitSessions,
    required List<ExerciseSession> exerciseSessions,
    String patientName = 'Kneedle user',
  }) async {
    final doc = pw.Document(
      title: 'Kneedle Movement Assessment Report',
      author: 'Kneedle',
      creator: 'Kneedle (on-device)',
      subject: 'Gait & knee function summary',
    );

    final now = DateTime.now();
    final df = DateFormat('dd MMM yyyy');
    final dfTime = DateFormat('dd MMM yyyy · HH:mm');
    final reportId = _reportId(now);

    final sortedGait = [...gaitSessions]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final sortedPain = [...painEntries]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final sortedEx = [...exerciseSessions]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final latest = sortedGait.isEmpty ? null : sortedGait.first;
    final periodFrom = _periodStart(sortedGait, sortedPain, sortedEx);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 48),
        header: (ctx) => _pageHeader(ctx, reportId),
        footer: (ctx) => _pageFooter(ctx, now),
        build: (ctx) => [
          _titleBlock(patientName, now, dfTime),
          pw.SizedBox(height: 14),
          _patientCard(patientName, reportId, periodFrom, now, df),
          pw.SizedBox(height: 16),
          _sectionHeading('1.  Clinical impression'),
          _impressionBlock(latest, sortedGait.length, sortedPain),
          pw.SizedBox(height: 14),
          _sectionHeading('2.  Objective gait measurements'),
          _measurementsTable(latest, dfTime),
          pw.SizedBox(height: 6),
          _legend(),
          pw.SizedBox(height: 14),
          _sectionHeading('3.  Observations & clinical flags'),
          _observationsBlock(latest),
          pw.SizedBox(height: 14),
          _sectionHeading('4.  Pain trajectory'),
          _painBlock(sortedPain, df),
          pw.SizedBox(height: 14),
          _sectionHeading('5.  Exercise adherence'),
          _exerciseBlock(sortedEx, df),
          pw.SizedBox(height: 14),
          _sectionHeading('6.  Recommendations & plan'),
          _recommendationsBlock(latest),
          pw.SizedBox(height: 16),
          _signatureBlock(),
          pw.SizedBox(height: 10),
          _disclaimerBlock(),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmm').format(now);
    final f = File('${dir.path}/kneedle_report_$stamp.pdf');
    await f.writeAsBytes(await doc.save(), flush: true);
    return f;
  }

  // ── Header / footer ────────────────────────────────────────────────────

  static pw.Widget _pageHeader(pw.Context ctx, String reportId) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _hairline, width: 0.6)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          _logoMark(),
          pw.SizedBox(width: 8),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'KNEEDLE',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                  letterSpacing: 2,
                ),
              ),
              pw.Text(
                'Movement & gait assessment',
                style: const pw.TextStyle(fontSize: 8, color: _inkMuted),
              ),
            ],
          ),
          pw.Spacer(),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Report ID  $reportId',
                style: const pw.TextStyle(fontSize: 8, color: _inkMuted),
              ),
              pw.Text(
                'Confidential - patient health information',
                style: pw.TextStyle(
                  fontSize: 7.5,
                  color: _inkMuted,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pageFooter(pw.Context ctx, DateTime generatedAt) {
    final stamp = DateFormat('dd MMM yyyy · HH:mm').format(generatedAt);
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      margin: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _hairline, width: 0.6)),
      ),
      child: pw.Row(
        children: [
          pw.Text(
            'Generated on-device by Kneedle  ·  $stamp',
            style: const pw.TextStyle(fontSize: 8, color: _inkMuted),
          ),
          pw.Spacer(),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: _inkMuted),
          ),
        ],
      ),
    );
  }

  static pw.Widget _logoMark() {
    return pw.Container(
      width: 22,
      height: 22,
      decoration: pw.BoxDecoration(
        color: _accent,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      alignment: pw.Alignment.center,
      child: pw.Text(
        'K',
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  // ── Title & patient meta ───────────────────────────────────────────────

  static pw.Widget _titleBlock(
    String patientName,
    DateTime now,
    DateFormat dfTime,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'MOVEMENT ASSESSMENT REPORT',
          style: pw.TextStyle(
            fontSize: 9,
            color: _accent,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 3,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Knee Function & Gait Analysis Summary',
          style: pw.TextStyle(
            fontSize: 20,
            color: _ink,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Prepared for the patient\'s treating clinician',
          style: pw.TextStyle(
            fontSize: 10.5,
            color: _inkMuted,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    );
  }

  static pw.Widget _patientCard(
    String name,
    String reportId,
    DateTime? periodFrom,
    DateTime now,
    DateFormat df,
  ) {
    final periodStr = periodFrom == null
        ? df.format(now)
        : '${df.format(periodFrom)}  ->  ${df.format(now)}';
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _bandFill,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: _hairline, width: 0.6),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: _kvCol([
              ['Patient', name],
              ['Date of report', df.format(now)],
            ]),
          ),
          pw.Container(width: 0.6, height: 36, color: _hairline),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: _kvCol([
              ['Report ID', reportId],
              ['Assessment period', periodStr],
            ]),
          ),
          pw.Container(width: 0.6, height: 36, color: _hairline),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: _kvCol([
              ['Source', 'Self-administered, on-device'],
              ['Method', 'MediaPipe pose + Gemma 3n'],
            ]),
          ),
        ],
      ),
    );
  }

  static pw.Widget _kvCol(List<List<String>> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) pw.SizedBox(height: 6),
          pw.Text(
            rows[i][0].toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7.5,
              color: _inkMuted,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            rows[i][1],
            style: pw.TextStyle(
              fontSize: 10.5,
              color: _ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _sectionHeading(String text) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _accent, width: 1.2),
        ),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11.5,
          color: _accent,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // ── Section: clinical impression ───────────────────────────────────────

  static pw.Widget _impressionBlock(
    GaitSession? latest,
    int totalSessions,
    List<PainEntry> pain,
  ) {
    if (latest == null) {
      return _noteBox(
        'No gait sessions have been recorded yet. The patient is encouraged '
        'to complete a walking capture so a baseline can be established.',
      );
    }

    final severity = _titleCase(latest.severity);
    final klGrade = latest.klGrade;
    final symmetry = latest.symmetryScore;
    final cadence = latest.cadence;
    final analysis = latest.decodedAnalysis();
    final empathy = analysis?['empathy_line'] as String?;
    final observation = analysis?['observation'] as String?;

    final recentPain = pain.where((e) {
      return DateTime.now().difference(e.timestamp).inDays <= 14;
    }).toList();
    final avgPain = recentPain.isEmpty
        ? null
        : recentPain.map((e) => e.painScore).reduce((a, b) => a + b) /
            recentPain.length;

    // 1-2 sentence summary, written like a clinician would dictate.
    final summary = StringBuffer()
      ..write('Self-administered gait capture on '
          '${DateFormat('dd MMM yyyy').format(latest.timestamp)} ')
      ..write('indicates a ${severity.toLowerCase()} presentation ')
      ..write('(KL proxy grade $klGrade');
    if (symmetry != null) {
      summary.write(
          ', symmetry index ${symmetry.toStringAsFixed(0)}/100');
    }
    if (cadence != null) {
      summary.write(', cadence ${cadence.toStringAsFixed(0)} steps/min');
    }
    summary.write('). ');
    summary.write('Capture confidence '
        '${(latest.confidence * 100).toStringAsFixed(0)}%. ');
    if (avgPain != null) {
      summary.write(
          'Mean self-reported pain over the last 14 days is '
          '${avgPain.toStringAsFixed(1)}/10 across ${recentPain.length} entries. ');
    }
    summary.write('Total sessions reviewed in this report: $totalSessions.');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _impressionChip('Severity', severity, _severityColor(latest.severity)),
            pw.SizedBox(width: 8),
            _impressionChip('KL proxy', klGrade, _accent),
            pw.SizedBox(width: 8),
            if (symmetry != null)
              _impressionChip(
                'Symmetry',
                '${symmetry.toStringAsFixed(0)}/100',
                _statusToColor(_statusForSymmetry(symmetry)),
              ),
            pw.SizedBox(width: 8),
            if (cadence != null)
              _impressionChip(
                'Cadence',
                '${cadence.toStringAsFixed(0)} spm',
                _statusToColor(_statusForCadence(cadence)),
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          summary.toString(),
          style: const pw.TextStyle(
            fontSize: 10.5,
            color: _ink,
            lineSpacing: 2.2,
          ),
        ),
        if (observation != null && observation.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              color: _accentSoft,
              border: pw.Border(
                left: pw.BorderSide(color: _accent, width: 2.5),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'NARRATIVE OBSERVATION',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: _accent,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  observation,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: _ink,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (empathy != null && empathy.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            '"$empathy"',
            style: pw.TextStyle(
              fontSize: 9.5,
              color: _inkMuted,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  static pw.Widget _impressionChip(
    String label,
    String value,
    PdfColor accent,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: accent, width: 0.8),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 7,
              color: accent,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              color: _ink,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ── Section: objective measurements table ─────────────────────────────

  static pw.Widget _measurementsTable(GaitSession? s, DateFormat dfTime) {
    if (s == null) {
      return _noteBox('No measurements available.');
    }

    final rows = <_MeasureRow>[
      _MeasureRow(
        'Knee flexion - right',
        _fmtDeg(s.kneeAngleRight),
        'Peak walking flexion >= 15°',
        _statusForKneeBend(s.kneeAngleRight),
      ),
      _MeasureRow(
        'Knee flexion - left',
        _fmtDeg(s.kneeAngleLeft),
        'Peak walking flexion >= 15°',
        _statusForKneeBend(s.kneeAngleLeft),
      ),
      _MeasureRow(
        'Symmetry index',
        s.symmetryScore == null
            ? '-'
            : '${s.symmetryScore!.toStringAsFixed(0)}/100',
        '>= 80 normal',
        _statusForSymmetry(s.symmetryScore),
      ),
      _MeasureRow(
        'Cadence',
        s.cadence == null
            ? '-'
            : '${s.cadence!.toStringAsFixed(0)} steps/min',
        '100-125 spm comfortable',
        _statusForCadence(s.cadence),
      ),
      _MeasureRow(
        'Double-support ratio',
        '${s.doubleSupportRatio.toStringAsFixed(1)} %',
        '20-25 % typical',
        _statusForDoubleSupport(s.doubleSupportRatio),
      ),
      _MeasureRow(
        'Static varus/valgus - right',
        '${s.rightStaticAlignmentDeviation.toStringAsFixed(1)} %LL',
        '< 4 % leg length',
        _statusForAlignment(s.rightStaticAlignmentDeviation),
      ),
      _MeasureRow(
        'Static varus/valgus - left',
        '${s.leftStaticAlignmentDeviation.toStringAsFixed(1)} %LL',
        '< 4 % leg length',
        _statusForAlignment(s.leftStaticAlignmentDeviation),
      ),
      _MeasureRow(
        'KL proxy score',
        '${s.klScore.toStringAsFixed(1)}  (grade ${s.klGrade})',
        '0-1 normal · 2 mild · 3 mod · 4 severe',
        _statusForKlGrade(s.klGrade),
      ),
      _MeasureRow(
        'Capture confidence',
        '${(s.confidence * 100).toStringAsFixed(0)} %',
        '>= 70 % for reliable read',
        s.confidence >= 0.7
            ? _Status.good
            : (s.confidence >= 0.5 ? _Status.watch : _Status.concern),
      ),
    ];

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(2.3),
        1: pw.FlexColumnWidth(1.5),
        2: pw.FlexColumnWidth(2.2),
        3: pw.FlexColumnWidth(1.1),
      },
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _hairline, width: 0.4),
        top: pw.BorderSide(color: _hairline, width: 0.6),
        bottom: pw.BorderSide(color: _hairline, width: 0.6),
      ),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _accent),
          children: [
            _th('Measurement'),
            _th('Result'),
            _th('Reference range'),
            _th('Status', alignRight: true),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isEven ? _bandStripe : PdfColors.white,
            ),
            children: [
              _td(rows[i].label, bold: true),
              _td(rows[i].value),
              _td(rows[i].reference, muted: true),
              _statusCell(rows[i].status),
            ],
          ),
      ],
    );
  }

  static pw.Widget _th(String text, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text.toUpperCase(),
        textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  static pw.Widget _td(String text, {bool bold = false, bool muted = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9.5,
          color: muted ? _inkMuted : _ink,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _statusCell(_Status s) {
    final (label, color) = switch (s) {
      _Status.good => ('WITHIN RANGE', _good),
      _Status.watch => ('BORDERLINE', _watch),
      _Status.concern => ('OUTSIDE RANGE', _concern),
      _Status.na => ('-', _inkMuted),
    };
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: color, width: 0.7),
            borderRadius: pw.BorderRadius.circular(2),
          ),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7.5,
              color: color,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  static pw.Widget _legend() {
    return pw.Row(
      children: [
        pw.Text(
          'Reference ranges are general adult walking norms and are advisory only. ',
          style: pw.TextStyle(
            fontSize: 7.5,
            color: _inkMuted,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
      ],
    );
  }

  // ── Section: observations & flags ─────────────────────────────────────

  static pw.Widget _observationsBlock(GaitSession? s) {
    if (s == null || s.clinicalFlags.isEmpty) {
      return _noteBox(
        'No clinical flags raised in this session.',
        tone: _accentSoft,
      );
    }
    final lines = s.clinicalFlags.map(_flagLabel).toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: 3,
                  height: 3,
                  margin: const pw.EdgeInsets.only(top: 5, right: 6),
                  decoration: const pw.BoxDecoration(
                    color: _ink,
                    shape: pw.BoxShape.circle,
                  ),
                ),
                pw.Expanded(
                  child: pw.Text(
                    l,
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: _ink,
                      lineSpacing: 2,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Section: pain trajectory ───────────────────────────────────────────

  static pw.Widget _painBlock(List<PainEntry> all, DateFormat df) {
    if (all.isEmpty) {
      return _noteBox('No pain entries logged.');
    }
    final now = DateTime.now();
    final recent =
        all.where((e) => now.difference(e.timestamp).inDays <= 14).toList();
    final mean14 = recent.isEmpty
        ? null
        : recent.map((e) => e.painScore).reduce((a, b) => a + b) /
            recent.length;
    final overallMean =
        all.map((e) => e.painScore).reduce((a, b) => a + b) / all.length;
    final peak = all.map((e) => e.painScore).reduce(math.max);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            _statTile('Entries (all)', '${all.length}'),
            pw.SizedBox(width: 8),
            _statTile('Mean (14 d)',
                mean14 == null ? '-' : '${mean14.toStringAsFixed(1)} / 10'),
            pw.SizedBox(width: 8),
            _statTile(
                'Mean (overall)', '${overallMean.toStringAsFixed(1)} / 10'),
            pw.SizedBox(width: 8),
            _statTile('Peak rating', '$peak / 10'),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text(
          'Most recent entries (up to 10 shown):',
          style: pw.TextStyle(
            fontSize: 9,
            color: _inkMuted,
            fontStyle: pw.FontStyle.italic,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.5),
            1: pw.FlexColumnWidth(0.8),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(3),
          },
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _hairline, width: 0.4),
            top: pw.BorderSide(color: _hairline, width: 0.6),
            bottom: pw.BorderSide(color: _hairline, width: 0.6),
          ),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _accent),
              children: [
                _th('Date'),
                _th('Score'),
                _th('Location'),
                _th('Context / trigger'),
              ],
            ),
            for (var i = 0; i < all.take(10).length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isEven ? _bandStripe : PdfColors.white,
                ),
                children: [
                  _td(df.format(all[i].timestamp)),
                  _td('${all[i].painScore}/10', bold: true),
                  _td(all[i].location.isEmpty ? '-' : all[i].location),
                  _td(all[i].context.isEmpty ? '-' : all[i].context,
                      muted: true),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _statTile(String label, String value) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _bandFill,
          borderRadius: pw.BorderRadius.circular(3),
          border: pw.Border.all(color: _hairline, width: 0.5),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 7,
                color: _inkMuted,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 12.5,
                color: _ink,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section: exercise adherence ───────────────────────────────────────

  static pw.Widget _exerciseBlock(List<ExerciseSession> all, DateFormat df) {
    if (all.isEmpty) {
      return _noteBox(
        'No exercise sessions completed in the assessment window.',
      );
    }
    final totalReps = all.fold<int>(0, (s, e) => s + e.repsCompleted);
    final totalMin = (all.fold<int>(0, (s, e) => s + e.durationSec) / 60).round();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            _statTile('Sessions', '${all.length}'),
            pw.SizedBox(width: 8),
            _statTile('Total reps', '$totalReps'),
            pw.SizedBox(width: 8),
            _statTile('Active time', '$totalMin min'),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.7),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1.2),
          },
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: _hairline, width: 0.4),
            top: pw.BorderSide(color: _hairline, width: 0.6),
            bottom: pw.BorderSide(color: _hairline, width: 0.6),
          ),
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _accent),
              children: [
                _th('Date'),
                _th('Exercise'),
                _th('Reps'),
                _th('Duration'),
              ],
            ),
            for (var i = 0; i < all.take(8).length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  color: i.isEven ? _bandStripe : PdfColors.white,
                ),
                children: [
                  _td(df.format(all[i].timestamp)),
                  _td(all[i].exerciseName, bold: true),
                  _td('${all[i].repsCompleted}'),
                  _td('${(all[i].durationSec / 60).toStringAsFixed(1)} min',
                      muted: true),
                ],
              ),
          ],
        ),
      ],
    );
  }

  // ── Section: recommendations ──────────────────────────────────────────

  static pw.Widget _recommendationsBlock(GaitSession? latest) {
    final analysis = latest?.decodedAnalysis();
    final fixTitle = analysis?['fix_title'] as String? ?? '';
    final fixDesc = analysis?['fix_desc'] as String? ?? '';
    final frequency = analysis?['frequency'] as String? ?? '';
    final painRule = analysis?['pain_rule'] as String? ?? '';
    final referralRecommended =
        (analysis?['referral_recommended'] as bool?) ?? false;
    final referralText = analysis?['referral_text'] as String? ?? '';
    final exercises = analysis?['exercises'];

    final exList = <Map<String, Object?>>[];
    if (exercises is List) {
      for (final e in exercises) {
        if (e is Map) exList.add(e.cast<String, Object?>());
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (fixTitle.isNotEmpty)
          _recRow(
            'Primary focus',
            fixTitle + (fixDesc.isEmpty ? '' : '. $fixDesc'),
          ),
        if (frequency.isNotEmpty) _recRow('Frequency', frequency),
        if (painRule.isNotEmpty) _recRow('Pain rule', painRule),
        if (exList.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Prescribed exercises',
            style: pw.TextStyle(
              fontSize: 9,
              color: _inkMuted,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 4),
          for (final ex in exList.take(6))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 14,
                    margin: const pw.EdgeInsets.only(top: 1),
                    child: pw.Text(
                      '·',
                      style: pw.TextStyle(
                        fontSize: 11,
                        color: _accent,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.RichText(
                      text: pw.TextSpan(
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: _ink,
                          lineSpacing: 2,
                        ),
                        children: [
                          pw.TextSpan(
                            text: _exName(ex),
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          if (_exReps(ex).isNotEmpty)
                            pw.TextSpan(
                              text: '  -  ${_exReps(ex)}',
                              style: const pw.TextStyle(color: _inkMuted),
                            ),
                          if (_exReason(ex).isNotEmpty)
                            pw.TextSpan(text: '. ${_exReason(ex)}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (referralRecommended && referralText.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFFBF3E5),
              border: pw.Border(
                left: pw.BorderSide(color: _watch, width: 2.5),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'CLINICIAN REVIEW SUGGESTED',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    color: _watch,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  referralText,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: _ink,
                    lineSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (fixTitle.isEmpty &&
            frequency.isEmpty &&
            painRule.isEmpty &&
            exList.isEmpty &&
            !referralRecommended)
          _noteBox(
            'No structured recommendations were captured with the most recent '
            'session. Consider repeating the gait assessment to refresh the plan.',
          ),
      ],
    );
  }

  static pw.Widget _recRow(String label, String body) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(
                fontSize: 8,
                color: _inkMuted,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              body,
              style: const pw.TextStyle(
                fontSize: 10,
                color: _ink,
                lineSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Signature & disclaimer ────────────────────────────────────────────

  static pw.Widget _signatureBlock() {
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(height: 0.6, color: _ink),
              pw.SizedBox(height: 4),
              pw.Text(
                'Reviewing clinician - signature',
                style: const pw.TextStyle(fontSize: 8.5, color: _inkMuted),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(height: 0.6, color: _ink),
              pw.SizedBox(height: 4),
              pw.Text(
                'Date',
                style: const pw.TextStyle(fontSize: 8.5, color: _inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _disclaimerBlock() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: _bandStripe,
        borderRadius: pw.BorderRadius.circular(3),
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Text(
        'Disclaimer - Kneedle is a wellbeing and self-monitoring tool. It is '
        'not a medical device and does not provide a diagnosis. Measurements '
        'are derived from a single-camera, self-administered capture and are '
        'subject to environmental and technique variability. This summary is '
        'intended to support, not replace, the judgement of a qualified '
        'healthcare professional. All data is processed locally on the '
        'patient\'s device; nothing is uploaded unless the patient chooses to '
        'share this document.',
        style: pw.TextStyle(
          fontSize: 7.5,
          color: _inkMuted,
          lineSpacing: 2,
          fontStyle: pw.FontStyle.italic,
        ),
      ),
    );
  }

  static pw.Widget _noteBox(String text, {PdfColor tone = _bandFill}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: tone,
        borderRadius: pw.BorderRadius.circular(3),
        border: pw.Border.all(color: _hairline, width: 0.5),
      ),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  static String _fmtDeg(double? v) =>
      v == null ? '-' : '${v.toStringAsFixed(1)}°';

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  static String _reportId(DateTime now) {
    final base = now.millisecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'KN-${base.substring(base.length - 6)}';
  }

  static DateTime? _periodStart(
    List<GaitSession> g,
    List<PainEntry> p,
    List<ExerciseSession> e,
  ) {
    final ts = <DateTime>[
      ...g.map((x) => x.timestamp),
      ...p.map((x) => x.timestamp),
      ...e.map((x) => x.timestamp),
    ];
    if (ts.isEmpty) return null;
    ts.sort();
    return ts.first;
  }

  static PdfColor _statusToColor(_Status s) {
    switch (s) {
      case _Status.good:
        return _good;
      case _Status.watch:
        return _watch;
      case _Status.concern:
        return _concern;
      case _Status.na:
        return _inkMuted;
    }
  }

  static PdfColor _severityColor(String sev) {
    switch (sev.toLowerCase()) {
      case 'severe':
        return _concern;
      case 'moderate':
        return _watch;
      default:
        return _good;
    }
  }

  static _Status _statusForSymmetry(double? v) {
    if (v == null) return _Status.na;
    if (v >= 80) return _Status.good;
    if (v >= 65) return _Status.watch;
    return _Status.concern;
  }

  static _Status _statusForCadence(double? v) {
    if (v == null) return _Status.na;
    if (v >= 100 && v <= 125) return _Status.good;
    if (v >= 80) return _Status.watch;
    return _Status.concern;
  }

  static _Status _statusForKneeBend(double? v) {
    if (v == null) return _Status.na;
    if (v >= 10) return _Status.good;
    if (v >= 5) return _Status.watch;
    return _Status.concern;
  }

  static _Status _statusForDoubleSupport(double v) {
    if (v >= 18 && v <= 27) return _Status.good;
    if (v < 30) return _Status.watch;
    return _Status.concern;
  }

  static _Status _statusForAlignment(double v) {
    final a = v.abs();
    if (a < 4) return _Status.good;
    if (a < 7) return _Status.watch;
    return _Status.concern;
  }

  static _Status _statusForKlGrade(String g) {
    switch (g.toUpperCase()) {
      case '0':
      case '1':
      case 'KL0':
      case 'KL1':
        return _Status.good;
      case '2':
      case 'KL2':
        return _Status.watch;
      case '3':
      case '4':
      case 'KL3':
      case 'KL4':
        return _Status.concern;
      default:
        return _Status.na;
    }
  }

  static String _exName(Map<String, Object?> ex) {
    final def = ex['def'];
    if (def is Map) {
      final n = def['name_en'] ?? def['name'] ?? '';
      if (n is String && n.isNotEmpty) return n;
    }
    final direct = ex['name_en'] ?? ex['name'] ?? '';
    return direct is String ? direct : '';
  }

  static String _exReps(Map<String, Object?> ex) {
    final def = ex['def'];
    if (def is Map) {
      final r = def['reps_en'] ?? def['reps'] ?? '';
      if (r is String) return r;
    }
    final direct = ex['reps_en'] ?? ex['reps'] ?? '';
    return direct is String ? direct : '';
  }

  static String _exReason(Map<String, Object?> ex) {
    final r = ex['reason'] ?? '';
    return r is String ? r : '';
  }

  static String _flagLabel(String f) {
    return _flagLabels[f] ?? _humanise(f);
  }

  static String _humanise(String snake) {
    final parts = snake.split('_').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return snake;
    return parts.map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
  }

  static Future<void> shareReport(File f) async {
    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'application/pdf')],
      subject: 'Kneedle - Movement Assessment Report',
    );
  }
}

enum _Status { good, watch, concern, na }

class _MeasureRow {
  _MeasureRow(this.label, this.value, this.reference, this.status);
  final String label;
  final String value;
  final String reference;
  final _Status status;
}

const _flagLabels = <String, String>{
  'bilateral_oa_pattern':
      'Bilateral OA-like wear pattern detected across both knees.',
  'fppa_deviation':
      'Frontal-plane projection angle deviation - medial knee tracking during stance.',
  'mild_static_varus_valgus_deformity':
      'Mild static varus/valgus deformity in standing posture.',
  'moderate_static_varus_valgus_deformity':
      'Moderate static varus/valgus deformity in standing posture.',
  'severe_static_varus_valgus_deformity':
      'Severe static varus/valgus deformity - clinical review advised.',
  'mild_varus_valgus_thrust':
      'Mild dynamic varus/valgus thrust during loading response.',
  'significant_varus_valgus_thrust':
      'Pronounced dynamic varus/valgus thrust during loading response.',
  'trendelenburg_positive':
      'Positive Trendelenburg sign - contralateral pelvic drop in single-leg stance.',
  'significant_trunk_lean':
      'Compensatory lateral trunk lean during stance.',
  'high_double_support':
      'Elevated double-support time consistent with antalgic guarding.',
  'elevated_double_support':
      'Mildly elevated double-support time - cautious stepping pattern.',
  'high_stride_asymmetry':
      'High stride-time asymmetry between limbs.',
  'low_cadence':
      'Cadence below typical comfortable adult range.',
  'reduced_hip_extension':
      'Reduced terminal hip extension at toe-off.',
  'reduced_ankle_dorsiflexion':
      'Reduced ankle dorsiflexion during mid-stance.',
  'right_loading_response_absent':
      'Right knee loading-response flexion absent.',
  'right_loading_response_reduced':
      'Right knee loading-response flexion reduced.',
  'left_loading_response_absent':
      'Left knee loading-response flexion absent.',
  'left_loading_response_reduced':
      'Left knee loading-response flexion reduced.',
  'right_swing_flexion_severe':
      'Right knee swing-phase flexion severely reduced.',
  'right_swing_flexion_reduced':
      'Right knee swing-phase flexion reduced.',
  'left_swing_flexion_severe':
      'Left knee swing-phase flexion severely reduced.',
  'left_swing_flexion_reduced':
      'Left knee swing-phase flexion reduced.',
  'right_flexion_contracture':
      'Suspected right knee flexion contracture - incomplete terminal extension.',
  'left_flexion_contracture':
      'Suspected left knee flexion contracture - incomplete terminal extension.',
};

// Suppresses unused-import lint when jsonDecode is not directly used here.
// ignore: unused_element
void _keepImports() => jsonDecode('{}');
