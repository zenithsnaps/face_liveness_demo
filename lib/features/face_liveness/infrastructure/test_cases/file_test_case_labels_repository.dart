import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persisted as a JSON map: { "caseLabel": "live" | "spoof" | "unlabeled" }
class FileTestCaseLabelsRepository {
  static const _fileName = 'test_case_labels.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, String>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return {};
      final raw = await f.readAsString();
      if (raw.isEmpty) return {};
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      return {};
    }
  }

  Future<void> save(Map<String, String> labels) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(labels));
    } catch (_) {}
  }
}
