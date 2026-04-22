import 'package:face_liveness_demo/core/app_strings.dart';
import 'package:face_liveness_demo/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home screen shows start button', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FaceLivenessApp()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.startVerification), findsOneWidget);
  });
}
