import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/repositories/test_cases_repository.dart';

/// Reads / writes the test-case dropdown list from the Supabase `test_cases`
/// table (see migration `0004_test_cases.sql`). The migration seeds the 7
/// default cases with positions 1-7; `add()` appends with `max(position)+1`.
class SupabaseTestCasesRepository implements TestCasesRepository {
  final SupabaseClient _client;

  const SupabaseTestCasesRepository(this._client);

  @override
  Future<List<String>> load() async {
    final rows = await _client
        .from('test_cases')
        .select('name')
        .order('position', ascending: true) as List<dynamic>;
    return rows
        .map((r) => (r as Map<String, dynamic>)['name'] as String)
        .toList();
  }

  @override
  Future<void> add(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final maxRows = await _client
        .from('test_cases')
        .select('position')
        .order('position', ascending: false)
        .limit(1) as List<dynamic>;
    final nextPos = maxRows.isEmpty
        ? 1
        : ((maxRows.first as Map<String, dynamic>)['position'] as int) + 1;
    try {
      await _client
          .from('test_cases')
          .insert({'name': trimmed, 'position': nextPos});
    } on PostgrestException catch (e) {
      // 23505 = unique violation: name already exists, treat as no-op.
      if (e.code != '23505') rethrow;
    }
  }

  @override
  Future<void> remove(String name) async {
    await _client.from('test_cases').delete().eq('name', name);
  }
}
