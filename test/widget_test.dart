import 'package:face_liveness_demo/core/app_strings.dart';
import 'package:face_liveness_demo/features/face_liveness/infrastructure/test_cases/file_test_cases_repository.dart';
import 'package:face_liveness_demo/features/face_liveness/presentation/providers/test_cases_provider.dart';
import 'package:face_liveness_demo/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubTestCasesRepository extends FileTestCasesRepository {
  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> save(List<String> cases) async {}
}

void main() {
  testWidgets('Home screen shows start button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testCasesRepositoryProvider
              .overrideWithValue(_StubTestCasesRepository()),
        ],
        child: const FaceLivenessApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.startVerification), findsOneWidget);
  });
}
