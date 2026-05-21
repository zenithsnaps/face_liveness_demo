# Flutter method-channel bridge classes are called via reflection from Dart.
# R8 cannot see these usages and would strip them — keep the entire package.
-keep class com.example.face_liveness_demo.** { *; }

# ML Kit & MediaPipe — keep public API and native JNI entry points.
-keep class com.google.mlkit.** { *; }
-keep class com.google.mediapipe.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }

# Preserve native method bindings.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Suppress warnings for compile-time-only annotation classes used by
# AutoValue (transitive dependency of MediaPipe tasks-vision).
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
-dontwarn javax.lang.model.SourceVersion
-dontwarn javax.lang.model.element.Element
-dontwarn javax.lang.model.element.ElementKind
-dontwarn javax.lang.model.element.Modifier
-dontwarn javax.lang.model.type.TypeMirror
-dontwarn javax.lang.model.type.TypeVisitor
-dontwarn javax.lang.model.util.SimpleTypeVisitor8
