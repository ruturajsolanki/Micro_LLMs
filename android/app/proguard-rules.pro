# ProGuard rules for MicroLLM
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# Keep Flutter engine
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep our platform channel handlers
-keep class com.microllm.app.** { *; }

# Keep JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep speech recognition classes
-keep class android.speech.** { *; }

# Keep TTS classes
-keep class android.speech.tts.** { *; }

# Keep model-related classes (if using reflection)
# -keep class com.microllm.app.models.** { *; }

# Remove logging in release builds
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}

# Keep line numbers for better crash reports
-keepattributes SourceFile,LineNumberTable

# Rename source file attribute to hide package structure
-renamesourcefileattribute SourceFile
