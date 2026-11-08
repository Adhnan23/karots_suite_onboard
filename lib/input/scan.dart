import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans one barcode with the camera (Android); null when closed.
Future<String?> scanBarcode(BuildContext context) => Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScanPage()));

/// A moving camera can read half a barcode as another code. A read only counts
/// once the same value comes [needed] frames in a row, and EAN / UPC reads must
/// have a right check digit (shop-made Code 128 numbers are left alone).
class ScanConfirm {
  ScanConfirm({this.needed = 3});
  final int needed;
  String? _last;
  int _count = 0;

  /// The confirmed value, or null while still waiting.
  String? add(BarcodeFormat format, String? value) {
    if (value == null || value.isEmpty || !_checkDigitOk(format, value)) {
      _last = null;
      _count = 0;
      return null;
    }
    _count = value == _last ? _count + 1 : 1;
    _last = value;
    return _count >= needed ? value : null;
  }

  static bool _checkDigitOk(BarcodeFormat f, String v) {
    if (f != BarcodeFormat.ean13 && f != BarcodeFormat.ean8 && f != BarcodeFormat.upcA) return true;
    if (!RegExp(r'^\d{8}$|^\d{12,13}$').hasMatch(v)) return false;
    var sum = 0;
    for (var i = 0; i < v.length - 1; i++) {
      final d = v.codeUnitAt(v.length - 2 - i) - 48;
      sum += i.isEven ? d * 3 : d;
    }
    return (10 - sum % 10) % 10 == v.codeUnitAt(v.length - 1) - 48;
  }
}

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  // Every frame (not noDuplicates), so the same code can be seen several times in a row.
  final ctl = MobileScannerController(detectionSpeed: DetectionSpeed.normal, detectionTimeoutMs: 120);
  final confirm = ScanConfirm();
  bool done = false;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Scan a barcode'),
      actions: [
        IconButton(icon: const Icon(Icons.flash_on_rounded), onPressed: ctl.toggleTorch),
        IconButton(icon: const Icon(Icons.cameraswitch_rounded), onPressed: ctl.switchCamera),
      ],
    ),
    body: MobileScanner(
      controller: ctl,
      onDetect: (cap) {
        if (done) return;
        final b = cap.barcodes.firstOrNull;
        final v = b == null ? confirm.add(BarcodeFormat.unknown, null) : confirm.add(b.format, b.rawValue);
        if (v == null) return;
        done = true;
        Navigator.pop(context, v);
      },
    ),
  );
}
