import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/tester/file_last_tester_repository.dart';

final lastTesterRepositoryProvider = Provider<FileLastTesterRepository>((ref) {
  return FileLastTesterRepository();
});

class TesterNameController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final repo = ref.read(lastTesterRepositoryProvider);
    return repo.load();
  }

  Future<void> set(String name) async {
    final trimmed = name.trim();
    state = AsyncData(trimmed);
    await ref.read(lastTesterRepositoryProvider).save(trimmed);
  }
}

final testerNameProvider =
    AsyncNotifierProvider<TesterNameController, String>(TesterNameController.new);
