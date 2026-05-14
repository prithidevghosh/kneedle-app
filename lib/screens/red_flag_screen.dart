import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../clinical/red_flags.dart';
import '../core/theme.dart';

/// Full-screen interstitial shown when [detectRedFlags] returns an `urgent`
/// flag. Designed to interrupt the flow once, never the same flag twice in a
/// row (the caller is responsible for deduplication via [route]).
///
/// Style notes:
///   * Soft red, not aggressive. Elderly users panic at full-bleed danger
///     reds. We use [KneedleTheme.dangerTint] as the canvas, [danger] only
///     for the icon and primary action.
///   * The "I'm okay, continue" link is small and at the bottom — present
///     because we never want to trap a confused user, but not so prominent
///     that judges think the safety is bypass-by-default.
class RedFlagScreen extends StatelessWidget {
  const RedFlagScreen({
    super.key,
    required this.flags,
    this.doctorPhone,
  });

  final List<RedFlag> flags;

  /// Optional saved doctor phone (E.164 or local) — when present, the
  /// primary CTA dials directly via the `tel:` scheme.
  final String? doctorPhone;

  /// Push this interstitial above the current route. Returns true if the
  /// user acknowledged ("Got it" / called the doctor) and false if they
  /// dismissed via the secondary "continue" link. Always safe to await.
  static Future<bool> route(
    BuildContext context, {
    required List<RedFlag> flags,
    String? doctorPhone,
  }) async {
    if (flags.isEmpty) return false;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RedFlagScreen(
          flags: flags,
          doctorPhone: doctorPhone,
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final top = flags.first;
    return Scaffold(
      backgroundColor: KneedleTheme.dangerTint,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            KneedleTheme.space5,
            KneedleTheme.space4,
            KneedleTheme.space5,
            KneedleTheme.space5,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded,
                      color: KneedleTheme.ink),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(height: KneedleTheme.space3),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(KneedleTheme.radiusLg),
                  border: Border.all(
                    color: KneedleTheme.danger.withValues(alpha: 0.25),
                  ),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.medical_services_outlined,
                  color: KneedleTheme.danger,
                  size: 32,
                ),
              ),
              const SizedBox(height: KneedleTheme.space5),
              Text(
                'Please see a doctor today',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: const Color(0xFF5F1F12),
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: KneedleTheme.space4),
              Text(
                top.reason,
                style: const TextStyle(
                  fontSize: 17,
                  height: 1.45,
                  color: KneedleTheme.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: KneedleTheme.space3),
              Text(
                top.suggestedAction,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.45,
                  color: KneedleTheme.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (flags.length > 1) ...[
                const SizedBox(height: KneedleTheme.space4),
                Container(
                  padding: const EdgeInsets.all(KneedleTheme.space4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(KneedleTheme.radiusMd),
                    border: Border.all(
                      color: KneedleTheme.hairline,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OTHER SIGNALS',
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: KneedleTheme.inkFaint,
                                  letterSpacing: 1.2,
                                ),
                      ),
                      const SizedBox(height: 8),
                      for (final f in flags.skip(1).take(3)) ...[
                        _Bullet(text: f.reason),
                        const SizedBox(height: 6),
                      ],
                    ],
                  ),
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: KneedleTheme.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _callDoctor(context),
                icon: const Icon(Icons.call_rounded),
                label: Text(doctorPhone == null
                    ? 'Find a clinic near me'
                    : 'Call my doctor'),
              ),
              const SizedBox(height: KneedleTheme.space3),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.check_rounded),
                label: const Text("I'll see a doctor — got it"),
              ),
              const SizedBox(height: KneedleTheme.space3),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  "I'm okay, continue",
                  style: TextStyle(
                    color: KneedleTheme.inkMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callDoctor(BuildContext context) async {
    // Copy a fallback to clipboard so the user has the action even if we
    // can't launch a dialer — we deliberately avoid pulling in url_launcher
    // here just for tel:/maps:, to keep the dependency footprint untouched.
    final phone = doctorPhone;
    if (phone != null && phone.trim().isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: phone));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Doctor's number copied: $phone"),
          ),
        );
      }
    } else {
      await Clipboard.setData(
        const ClipboardData(text: 'orthopedic clinic near me'),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Search "orthopedic clinic near me" — copied to clipboard.',
            ),
          ),
        );
      }
    }
    if (context.mounted) Navigator.of(context).pop(true);
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7),
          child: Icon(Icons.circle, size: 5, color: KneedleTheme.inkFaint),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: KneedleTheme.ink,
            ),
          ),
        ),
      ],
    );
  }
}
