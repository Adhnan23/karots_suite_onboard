import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans one barcode with the camera (Android); null when closed.
Future<String?> scanBarcode(BuildContext context) => Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _ScanPage()));

class _ScanPage extends StatefulWidget {
  const _ScanPage();
  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final ctl = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
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
        final v = cap.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
        if (v == null || done) return;
        done = true;
        Navigator.pop(context, v);
      },
    ),
  );
}
