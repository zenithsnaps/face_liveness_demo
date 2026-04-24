/// Tester-curated list of test case labels (e.g. "หน้าปกติ", "ปิดปาก").
///
/// Implementations: [SupabaseTestCasesRepository] when Supabase is configured,
/// [FileTestCasesRepository] as offline fallback.
abstract class TestCasesRepository {
  /// Ordered list of test case names. Implementations seed defaults on first
  /// access so the dropdown is never empty.
  Future<List<String>> load();

  /// Insert a new case. No-op if [name] is empty/whitespace or already exists.
  Future<void> add(String name);

  /// Delete a case by name. No-op if not present.
  Future<void> remove(String name);
}

/// Default test case names seeded into both Supabase (via migration 0004) and
/// the file-backed fallback. Keep these in sync with `0004_test_cases.sql`.
const kDefaultTestCases = <String>[
  'หน้าปกติ',
  'ปิดปาก',
  'ปิดปากปิดจมูก',
  'ปิดครึ่งหน้า',
  'ปิดมากกว่า 50%',
  'หลับตา 2 ข้าง',
  'ภาพมืด',
];
