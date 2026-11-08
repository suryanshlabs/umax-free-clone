# Keep rules for the on-device AI stack.
#
# ML Kit Face Mesh Detection and MediaPipe ship native libraries plus Java/Kotlin
# glue that is reached reflectively in places. R8 shrinking (when enabled) must
# never strip, rename or obfuscate those packages: doing so can turn a working
# detector into a silently empty one at runtime, which in this app looks like a
# false "no face" reading.
#
# Note: as of 1.2.2 the release build does NOT enable minification
# (isMinifyEnabled stays false in build.gradle.kts), so these rules are
# insurance for the day it is switched on, not a fix for a live bug.

-keep class com.google.mlkit.** { *; }
-keep class com.google.mediapipe.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.mlkit.**.** { *; }
-dontwarn com.google.mlkit.**

# The camera plugin's platform code is also reached through method channels and
# reflection; keep its classes intact as well.
-keep class io.flutter.plugins.camera.** { *; }
