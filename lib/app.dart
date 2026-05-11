import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'providers/providers.dart';
import 'screens/root_shell.dart';

class KneedleApp extends ConsumerWidget {
  const KneedleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Kneedle',
      debugShowCheckedModeBanner: false,
      theme: KneedleTheme.light(),
      home: const _Bootstrap(),
    );
  }
}

class _Bootstrap extends ConsumerWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(gemmaInitProvider);
    final progress = ref.watch(modelDownloadProgressProvider);

    return init.when(
      data: (_) => const RootShell(),
      loading: () => _SplashScaffold(
        child: _LoadingView(progress: progress),
      ),
      error: (e, _) => _SplashScaffold(
        child: _ErrorView(
          error: '$e',
          onRetry: () => ref.invalidate(gemmaInitProvider),
        ),
      ),
    );
  }
}

class _SplashScaffold extends StatelessWidget {
  const _SplashScaffold({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KneedleTheme.cream,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KneedleTheme.space7),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final pct = progress > 0 ? progress.clamp(0.0, 1.0) : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KneedleTheme.sage, KneedleTheme.sageDeep],
              ),
              borderRadius: BorderRadius.circular(KneedleTheme.radiusXl),
              boxShadow: [
                BoxShadow(
                  color: KneedleTheme.sage.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                  spreadRadius: -4,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.spa_rounded, size: 44, color: Colors.white),
          ),
        ),
        const SizedBox(height: KneedleTheme.space6),
        Text(
          'Kneedle',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: KneedleTheme.space2),
        Text(
          'Preparing your on-device assistant',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: KneedleTheme.space6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: KneedleTheme.space3),
        Text(
          pct == null
              ? 'Initialising…'
              : '${(pct * 100).toStringAsFixed(0)}% downloaded',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.cloud_off_rounded,
            size: 48, color: KneedleTheme.danger),
        const SizedBox(height: KneedleTheme.space4),
        Text(
          "Couldn't load Gemma",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: KneedleTheme.space2),
        Text(
          error,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: KneedleTheme.space6),
        FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}
