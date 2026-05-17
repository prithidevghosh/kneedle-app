# Vosk uses JNA (Java Native Access) to talk to its bundled .so libraries.
# R8/ProGuard aggressively strips reflectively-loaded JNI bindings, which
# silently crashes the recognizer at runtime with `UnsatisfiedLinkError`.
# These keep rules preserve every JNA entry point so the natives stay wired.
# Only needed when kUseVoskStt = true; harmless otherwise.
-keep class com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }

# JNA references java.awt.* for its desktop-Java path. Those classes don't
# exist on Android — JNA's reflective lookups simply fall through at
# runtime. Without `-dontwarn`, R8 treats the missing references as a hard
# error and aborts the release build.
-dontwarn java.awt.**
-dontwarn javax.swing.**

# flutter_local_notifications stores scheduled-notification metadata as JSON
# and rehydrates it via Gson on app start. In release builds, R8 strips the
# generic TypeToken information that Gson relies on, which surfaces as
# `java.lang.RuntimeException: missing type parameter.` thrown from
# `FlutterLocalNotificationsPlugin.loadScheduledNotifications` the first time
# the plugin is touched after a reminder is scheduled. Keeping the plugin's
# model classes and Gson's TypeToken machinery makes the deserializer
# round-trip correctly. Debug builds don't run R8, which is why this only
# shows up in the APK.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes *Annotation*

# flutter_gemma's vision path calls into MediaPipe's image helpers when
# we attach JPEG frames to the gait analysis prompt. The MPImage classes
# live in `tasks-vision` which is pulled in transitively only when image
# support is enabled — R8 sees the references but can't see the classes
# and aborts. Keep them so the multimodal analyse path doesn't crash at
# runtime, and silence the warnings for any others R8 can't resolve.
-keep class com.google.mediapipe.framework.image.** { *; }
-keep class com.google.mediapipe.tasks.genai.** { *; }
-dontwarn com.google.mediapipe.framework.image.**
-dontwarn com.google.mediapipe.tasks.genai.**
