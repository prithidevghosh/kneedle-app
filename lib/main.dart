import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/gait_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  await StorageService.init();
  await NotificationService.init();
  // Spin up the gait isolate eagerly so the first analyse() call is instant.
  unawaited(GaitService.instance.start());
  runApp(const ProviderScope(child: KneedleApp()));
}
