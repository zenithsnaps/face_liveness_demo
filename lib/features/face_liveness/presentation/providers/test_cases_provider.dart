import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/test_cases/file_test_cases_repository.dart';

final testCasesRepositoryProvider = Provider<FileTestCasesRepository>(
  (ref) => FileTestCasesRepository(),
);

class TestCasesListController extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final repo = ref.read(testCasesRepositoryProvider);
    return repo.load();
  }

  Future<void> addCase(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final current = state.valueOrNull ?? const <String>[];
    if (current.contains(trimmed)) {
      ref.read(selectedTestCaseProvider.notifier).select(trimmed);
      return;
    }
    final next = [...current, trimmed];
    state = AsyncData(next);
    await ref.read(testCasesRepositoryProvider).save(next);
    ref.read(selectedTestCaseProvider.notifier).select(trimmed);
  }

  Future<void> removeCase(String name) async {
    final current = state.valueOrNull ?? const <String>[];
    final next = current.where((c) => c != name).toList();
    state = AsyncData(next);
    await ref.read(testCasesRepositoryProvider).save(next);
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
