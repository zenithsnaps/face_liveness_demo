import 'package:face_liveness_demo/core/app_strings.dart';
import 'package:face_liveness_demo/features/face_liveness/domain/repositories/test_cases_repository.dart';
import 'package:face_liveness_demo/features/face_liveness/infrastructure/tester/file_last_tester_repository.dart';
import 'package:face_liveness_demo/features/face_liveness/presentation/providers/test_cases_provider.dart';
import 'package:face_liveness_demo/features/face_liveness/presentation/providers/tester_provider.dart';
import 'package:face_liveness_demo/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubTestCasesRepository implements TestCasesRepository {
  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> add(String name) async {}

  @override
  Future<void> remove(String name) async {}
}

class _StubLastTester extends FileLastTesterRepository {
  @override
  Future<String> load() async => '';

  @override
  Future<void> save(String name) async {}
}

void main() {
  testWidgets('Home screen shows start button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testCasesRepositoryProvider
              .overrideWithValue(_StubTestCasesRepository()),
          lastTesterRepositoryProvider.overrideWithValue(_StubLastTester()),
        ],
        child: const FaceLivenessApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.startVerification), findsOneWidget);
  });
}
