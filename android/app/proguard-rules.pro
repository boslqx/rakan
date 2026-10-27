# MediaPipe ships AutoValue's annotation processor, which references
# compile-time-only javax.lang.model classes. They are never used at runtime.
-dontwarn javax.lang.model.**
-dontwarn autovalue.shaded.**
-dontwarn com.google.auto.value.**
# Graph-profiling protos referenced by MediaPipe but not shipped in tasks-vision.
-dontwarn com.google.mediapipe.proto.**

# MediaPipe's native code looks up its Java classes by name over JNI, and its
# task options are protobuf-lite messages read via reflection. Keep both intact
# so the pose landmarker doesn't crash in release builds.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
