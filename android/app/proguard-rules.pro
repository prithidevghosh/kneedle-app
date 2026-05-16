# Vosk uses JNA (Java Native Access) to talk to its bundled .so libraries.
# R8/ProGuard aggressively strips reflectively-loaded JNI bindings, which
# silently crashes the recognizer at runtime with `UnsatisfiedLinkError`.
# These keep rules preserve every JNA entry point so the natives stay wired.
# Only needed when kUseVoskStt = true; harmless otherwise.
-keep class com.sun.jna.* { *; }
-keepclassmembers class * extends com.sun.jna.* { public *; }
