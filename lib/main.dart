import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'kb/kb_index.dart';
import 'services/gait_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  await StorageService.init();
  await NotificationService.init();
  // Load the OA guideline KB for the RAG-grounded chat. Bundled asset,
  // ~25 chunks, BM25 build is <5 ms — fine to await synchronously.
  // We swallow errors so a bad/missing asset doesn't block app startup;
  // KbIndex.isLoaded will return false and the chat falls back to
  // un-cited answers.
  try {
    await KbIndex.load();
  } catch (e) {
    // ignore: avoid_print
    print('[main] KbIndex load failed (non-fatal): $e');
  }
  // Spin up the gait isolate eagerly so the first analyse() call is instant.
  unawaited(GaitService.instance.start());
  runApp(const ProviderScope(child: KneedleApp()));
}
