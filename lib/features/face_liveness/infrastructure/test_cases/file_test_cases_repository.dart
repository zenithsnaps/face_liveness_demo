import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/test_cases_repository.dart';

/// Persists the tester-curated list of test-case labels as a JSON array
/// in the app's documents directory. Used as a fallback when Supabase isn't
/// configured. Errors are swallowed so the home screen remains usable in
/// test or restricted environments.
class FileTestCasesRepository implements TestCasesRepository {
  static const _fileName = 'test_cases.json';

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<List<String>> _readRaw() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const [];
      final raw = await f.readAsString();
      if (raw.isEmpty) return const [];
      return (jsonDecode(raw) as List<dynamic>).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeRaw(List<String> cases) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(cases));
    } catch (_) {
      // best-effort
    }
  }

  @override
  Future<List<String>> load() async {
    final cases = await _readRaw();
    if (cases.isNotEmpty) return cases;
    // First run: seed defaults so the dropdown matches the Supabase seed.
    await _writeRaw(kDefaultTestCases);
    return List.of(kDefaultTestCases);
  }

  @override
  Future<void> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final cases = await _readRaw();
    if (cases.contains(trimmed)) return;
    await _writeRaw([...cases, trimmed]);
  }

  @override
  Future<void> remove(String name) async {
    final cases = await _readRaw();
    if (!cases.contains(name)) return;
    await _writeRaw(cases.where((c) => c != name).toList());
  }
}
