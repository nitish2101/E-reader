# Flutter specific ProGuard rules

# Keep Flutter classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# PDF library
-keep class com.pdfrender.** { *; }

# EPUB library  
-keep class nl.siegmann.epublib.** { *; }

# Hive
-keep class hive.** { *; }
-keepclassmembers class * extends hive.HiveObject {
    *;
}

# Preserve custom model classes
-keep class com.ereader.** { *; }

# Suppress warnings for missing deferred components classes (likely unused)
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
-dontwarn com.google.android.play.core.**
