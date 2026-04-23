import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists the tester-curated list of test-case labels as a JSON array
/// in the app's documents directory. Errors are swallowed (returns empty
/// on read failure) so the home screen remains usable in test or restricted
/// environments.
class FileTestCasesRepository {
  static const _fileName = 'test_cases.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<String>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final raw = await f.readAsString();
      if (raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list.cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<String> cases) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(cases));
    } catch (_) {
      // best-effort
    }
  }
}
