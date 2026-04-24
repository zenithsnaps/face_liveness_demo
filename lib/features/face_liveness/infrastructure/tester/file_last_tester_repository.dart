import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persists the last entered tester name as a single-line text file in the
/// app's documents directory. Convenience-only — failures are swallowed and
/// the home screen falls back to an empty field.
class FileLastTesterRepository {
  static const _fileName = 'last_tester.txt';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<String> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return '';
      return (await f.readAsString()).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> save(String name) async {
    try {
      final f = await _file();
      await f.writeAsString(name.trim());
    } catch (_) {
      // best-effort
    }
  }
}
