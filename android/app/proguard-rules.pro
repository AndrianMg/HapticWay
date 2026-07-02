# tflite_flutter references the optional GPU delegate, which is not bundled —
# R8's own generated suppression (build/app/outputs/mapping/release/missing_rules.txt).
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options
-dontwarn org.tensorflow.lite.gpu.**

# TFLite calls back into these classes via JNI, which R8 cannot see —
# stripping/renaming them breaks interpreter creation at runtime.
-keep class org.tensorflow.lite.** { *; }
