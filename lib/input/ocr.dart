import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

/// Reading text from a photo: the camera and ML Kit on Android; on Linux a picture
/// file and the tesseract command (when installed).
class Ocr {
  static bool? _tesseract;

  static Future<bool> available() async {
    if (Platform.isAndroid) return true;
    if (!Platform.isLinux) return false;
    return _tesseract ??= (await Process.run('which', ['tesseract'])).exitCode == 0;
  }

  /// The lines read, top to bottom; null when cancelled.
  static Future<List<String>?> readLines() async {
    if (Platform.isAndroid) {
      final photo = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1800, imageQuality: 90);
      if (photo == null) return null;
      final r = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final res = await r.processImage(InputImage.fromFilePath(photo.path));
        return [
          for (final b in res.blocks)
            for (final l in b.lines)
              if (l.text.trim().isNotEmpty) l.text.trim(),
        ];
      } finally {
        await r.close();
      }
    }
    final f = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Pictures', extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp']),
      ],
    );
    if (f == null) return null;
    final out = await Process.run('tesseract', [f.path, 'stdout']);
    return [
      for (final l in '${out.stdout}'.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
  }
}
