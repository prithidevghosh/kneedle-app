import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Bridge to the native key-event interceptor in `MainActivity.kt`.
///
/// Bluetooth selfie-stick remotes show up as a HID keyboard and fire Volume Up
/// (sometimes Volume Down / Camera / Media Play). Android delivers those keys
/// to AudioService before the Flutter engine, so the interception has to happen
/// at the Activity layer — this class is just the Dart-side stream consumer.
class ShutterButtonService {
  static const _events = EventChannel('kneedle/shutter');
  static const _control = MethodChannel('kneedle/shutter_control');

  static Stream<String> get events {
    if (!Platform.isAndroid) return const Stream<String>.empty();
    return _events.receiveBroadcastStream().map((e) => e.toString());
  }

  /// While active, the native side swallows the relevant key events instead of
  /// letting the system handle them (no volume HUD, no media transport jump).
  static Future<void> setActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _control.invokeMethod('setActive', active);
    } catch (_) {/* channel unavailable — selfie-stick trigger silently off */}
  }
}
