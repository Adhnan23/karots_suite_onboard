# google_mlkit_text_recognition declares the non-Latin script recognizers as
# `compileOnly` dependencies, but TextRecognizer.initialize() references them
# directly. R8 therefore reports them as missing classes in release builds.
# This app only uses TextRecognitionScript.latin (see lib/input/ocr.dart), so
# suppress the warnings instead of bundling the extra ML Kit models.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
