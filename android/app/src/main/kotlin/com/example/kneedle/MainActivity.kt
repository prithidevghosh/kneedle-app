package com.example.kneedle

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

// Bluetooth selfie-stick / shutter remote bridge.
//
// Those buttons present as a BT HID keyboard and send Volume Up (occasionally
// Volume Down / Camera / Media Play). The system's AudioService swallows
// volume keys before Flutter's engine ever sees them, so we override
// dispatchKeyEvent at the Activity level — the earliest hook on the dispatch
// chain — and forward to Dart via EventChannel. While `active` is true we also
// consume the event so the user doesn't see the volume HUD pop up mid-capture.
class MainActivity : FlutterActivity() {
    private var sink: EventChannel.EventSink? = null
    private var active: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "kneedle/shutter").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, eventSink: EventChannel.EventSink?) {
                    sink = eventSink
                }
                override fun onCancel(args: Any?) {
                    sink = null
                }
            }
        )
        MethodChannel(messenger, "kneedle/shutter_control").setMethodCallHandler { call, result ->
            if (call.method == "setActive") {
                active = call.arguments as? Boolean ?: false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!active) return super.dispatchKeyEvent(event)
        val kc = event.keyCode
        val isShutterKey = kc == KeyEvent.KEYCODE_VOLUME_UP ||
            kc == KeyEvent.KEYCODE_VOLUME_DOWN ||
            kc == KeyEvent.KEYCODE_CAMERA ||
            kc == KeyEvent.KEYCODE_HEADSETHOOK ||
            kc == KeyEvent.KEYCODE_MEDIA_PLAY ||
            kc == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        if (!isShutterKey) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            val name = when (kc) {
                KeyEvent.KEYCODE_VOLUME_UP -> "volume_up"
                KeyEvent.KEYCODE_VOLUME_DOWN -> "volume_down"
                KeyEvent.KEYCODE_CAMERA -> "camera"
                else -> "media"
            }
            sink?.success(name)
        }
        // Swallow both DOWN and UP so the system doesn't also act on it
        // (volume HUD, media transport, etc.).
        return true
    }
}
