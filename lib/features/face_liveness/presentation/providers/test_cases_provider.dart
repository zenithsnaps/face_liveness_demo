import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/test_cases_repository.dart';
import '../../infrastructure/test_cases/file_test_cases_repository.dart';
import '../../infrastructure/test_cases/supabase_test_cases_repository.dart';
import 'liveness_providers.dart';

final testCasesRepositoryProvider = Provider<TestCasesRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) return SupabaseTestCasesRepository(client);
  return FileTestCasesRepository();
});

class TestCasesListController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final repo = ref.read(testCasesRepositoryProvider);
    return repo.load();
  }

  Future<void> addCase(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final repo = ref.read(testCasesRepositoryProvider);
    await repo.add(trimmed);
    state = AsyncData(await repo.load());
    ref.read(selectedTestCaseProvider.notifier).select(trimmed);
  }

  Future<void> removeCase(String name) async {
    final repo = ref.read(testCasesRepositoryProvider);
    await repo.remove(name);
    state = AsyncData(await repo.load());
    if (ref.read(selectedTestCaseProvider) == name) {
      ref.read(selectedTestCaseProvider.notifier).select(null);
    }
  }
}

final testCasesListProvider =
    AsyncNotifierProvider<TestCasesListController, List<String>>(
  TestCasesListController.new,
);

class SelectedTestCaseController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? name) => state = name;
}

final selectedTestCaseProvider =
    NotifierProvider<SelectedTestCaseController, String?>(
  SelectedTestCaseController.new,
);
