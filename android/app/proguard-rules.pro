# ML Kit finds its components by reflection, and the Flutter plugins ship no
# keep rules of their own. Without these, R8 strips them from the release build
# and every frame handed to the face detector fails with a NullPointerException,
# so the measurement never collects a sample.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_face_detection.** { *; }
-dontwarn com.google.mlkit.**
