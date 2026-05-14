import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Thin, persistent disclaimer banner shown above every clinical surface
/// (gait results, chat, journal). Tap → bottom sheet with the long-form
/// localized safety text. Reads as a soft chip, not an alarm — designed for
/// elderly users who panic at red icons.
class SafetyBanner extends StatelessWidget {
  const SafetyBanner({
    super.key,
    this.message =
        'Screening tool · Not a diagnosis · Tap for red flags',
    this.detail,
  });

  /// One-line surface label. Defaults to the universal English disclaimer.
  final String message;

  /// Long-form text shown in the bottom sheet. If null, falls back to a
  /// generic OA disclaimer.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _showDetail(context),
      borderRadius: BorderRadius.circular(KneedleTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: KneedleTheme.space4,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: KneedleTheme.amberTint,
          borderRadius: BorderRadius.circular(KneedleTheme.radiusSm),
          border: Border.all(
            color: KneedleTheme.amber.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.shield_outlined,
              size: 18,
              color: Color(0xFF8E5B0A),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B4607),
                  letterSpacing: 0.1,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFF8E5B0A),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => _SafetyDetailSheet(detail: detail),
    );
  }
}

class _SafetyDetailSheet extends StatelessWidget {
  const _SafetyDetailSheet({this.detail});
  final String? detail;

  static const _defaultDetail =
      'Kneedle is a self-care companion for knee osteoarthritis. It is '
      'NOT a diagnostic device and does NOT replace a doctor.\n\n'
      'See a doctor TODAY if any of these happen:\n'
      ' • You cannot put weight on the knee.\n'
      ' • The knee suddenly swells, especially with fever.\n'
      ' • The knee locks, gives way, or you feel numbness.\n'
      ' • Pain at 8/10 or higher that does not settle within a few hours.\n\n'
      "Book a doctor or physiotherapist THIS WEEK if pain wakes you at "
      'night, keeps rising across days, or your gait check shows severe '
      'asymmetry.\n\n'
      'Everything Kneedle records is stored only on this phone — share the '
      "doctor report from the Report tab when you see your clinician.";

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        KneedleTheme.space5,
        KneedleTheme.space4,
        KneedleTheme.space5,
        KneedleTheme.space5 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: KneedleTheme.amberTint,
                  borderRadius:
                      BorderRadius.circular(KneedleTheme.radiusSm),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF8E5B0A),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'About this tool',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: KneedleTheme.space4),
          Text(
            detail ?? _defaultDetail,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: KneedleTheme.ink,
            ),
          ),
          const SizedBox(height: KneedleTheme.space5),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}
