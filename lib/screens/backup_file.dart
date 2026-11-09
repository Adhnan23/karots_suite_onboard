import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A backup's file name, stamped with now.
String backupName([String what = 'backup']) => 'karots-onboard-$what-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json';

/// Saves a backup where the person chooses: the share sheet on Android (Drive,
/// Files…), a save dialog elsewhere. False when they backed out.
Future<bool> saveBackupFile(BuildContext context, String text, String name) async {
  final bytes = Uint8List.fromList(utf8.encode(text));
  if (Platform.isAndroid) {
    final r = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: name, mimeType: 'application/json')],
        fileNameOverrides: [name],
      ),
    );
    return r.status == ShareResultStatus.success;
  }
  final at = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      const XTypeGroup(label: 'Backup', extensions: ['json']),
    ],
  );
  if (at == null) return false;
  await File(at.path).writeAsBytes(bytes);
  return true;
}

/// A copy kept inside the app as well (a second chance; gone if the app's
/// storage is cleared).
Future<void> keepInsideCopy(String text, String name) async {
  try {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/backups');
    await dir.create(recursive: true);
    await File('${dir.path}/$name').writeAsString(text);
  } catch (_) {} // no app folder (tests): the chosen copy is the one that matters
}
