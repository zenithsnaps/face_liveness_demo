import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/usecases/post_capture_thresholds.dart';
import '../../domain/entities/attempt_record.dart';
import '../../infrastructure/test_cases/file_test_case_labels_repository.dart';
import 'liveness_providers.dart';

// ─── Date range ──────────────────────────────────────────────────────────────

enum AnalyticsDateRange { last7Days, last30Days, all }

extension AnalyticsDateRangeX on AnalyticsDateRange {
  String get label => switch (this) {
        AnalyticsDateRange.last7Days => '7 วัน',
        AnalyticsDateRange.last30Days => '30 วัน',
        AnalyticsDateRange.all => 'ทั้งหมด',
      };

  DateTime? get since => switch (this) {
        AnalyticsDateRange.last7Days =>
          DateTime.now().subtract(const Duration(days: 7)),
        AnalyticsDateRange.last30Days =>
          DateTime.now().subtract(const Duration(days: 30)),
        AnalyticsDateRange.all => null,
      };
}

// ─── Filters ─────────────────────────────────────────────────────────────────

class AnalyticsFilters {
  final Set<String> testCases; // empty = show all
  final AnalyticsDateRange range;

  const AnalyticsFilters({
    this.testCases = const {},
    this.range = AnalyticsDateRange.last30Days,
  });

  AnalyticsFilters copyWith({
    Set<String>? testCases,
    AnalyticsDateRange? range,
  }) =>
      AnalyticsFilters(
        testCases: testCases ?? this.testCases,
        range: range ?? this.range,
      );
}

class AnalyticsFiltersController extends Notifier<AnalyticsFilters> {
  @override
  AnalyticsFilters build() => const AnalyticsFilters();

  void setRange(AnalyticsDateRange r) =>
      state = state.copyWith(range: r);

  void toggleTestCase(String name) {
    final next = Set<String>.from(state.testCases);
    if (next.contains(name)) {
      next.remove(name);
    } else {
      next.add(name);
    }
    state = state.copyWith(testCases: next);
  }

  void clearTestCases() => state = state.copyWith(testCases: {});
}

final analyticsFiltersProvider =
    NotifierProvider<AnalyticsFiltersController, AnalyticsFilters>(
  AnalyticsFiltersController.new,
);

// ─── Attempts ────────────────────────────────────────────────────────────────

class AnalyticsAttemptsController
    extends AsyncNotifier<List<AttemptRecord>> {
  @override
  Future<List<AttemptRecord>> build() async {
    final filters = ref.watch(analyticsFiltersProvider);
    final repo = ref.read(livenessResultRepositoryProvider);
    if (repo == null) return const [];
    final all = await repo.fetchAttempts(since: filters.range.since);
    if (filters.testCases.isEmpty) return all;
    return all.where((a) => filters.testCases.contains(a.testCase)).toList();
  }
}

final analyticsAttemptsProvider =
    AsyncNotifierProvider<AnalyticsAttemptsController, List<AttemptRecord>>(
  AnalyticsAttemptsController.new,
);

// ─── Threshold ───────────────────────────────────────────────────────────────

class AnalyticsThresholdController extends Notifier<double> {
  @override
  double build() => PostCaptureThresholds.defaults.faceScore;

  void set(double v) => state = v.clamp(0.0, 1.0);
}

final analyticsThresholdProvider =
    NotifierProvider<AnalyticsThresholdController, double>(
  AnalyticsThresholdController.new,
);

// ─── Test-case labels (live / spoof / unlabeled) ─────────────────────────────

enum TestCaseLabel { live, spoof, unlabeled }

extension TestCaseLabelX on TestCaseLabel {
  String get display => switch (this) {
        TestCaseLabel.live => 'Live',
        TestCaseLabel.spoof => 'Spoof',
        TestCaseLabel.unlabeled => '—',
      };

  TestCaseLabel get next => switch (this) {
        TestCaseLabel.unlabeled => TestCaseLabel.live,
        TestCaseLabel.live => TestCaseLabel.spoof,
        TestCaseLabel.spoof => TestCaseLabel.unlabeled,
      };
}

final testCaseLabelsRepositoryProvider =
    Provider<FileTestCaseLabelsRepository>(
  (ref) => FileTestCaseLabelsRepository(),
);

class TestCaseLabelsController
    extends AsyncNotifier<Map<String, TestCaseLabel>> {
  @override
  Future<Map<String, TestCaseLabel>> build() async {
    final raw = await ref
        .read(testCaseLabelsRepositoryProvider)
        .load();
    return raw.map(
      (k, v) => MapEntry(k, _parseLabel(v)),
    );
  }

  Future<void> cycle(String name) async {
    final current = state.valueOrNull ?? {};
    final existing = current[name] ?? TestCaseLabel.unlabeled;
    final next = {...current, name: existing.next};
    state = AsyncData(next);
    await ref.read(testCaseLabelsRepositoryProvider).save(
          next.map((k, v) => MapEntry(k, v.name)),
        );
  }

  TestCaseLabel labelFor(String name) =>
      state.valueOrNull?[name] ?? TestCaseLabel.unlabeled;
}

final testCaseLabelsProvider =
    AsyncNotifierProvider<TestCaseLabelsController, Map<String, TestCaseLabel>>(
  TestCaseLabelsController.new,
);

TestCaseLabel _parseLabel(String s) => switch (s) {
      'live' => TestCaseLabel.live,
      'spoof' => TestCaseLabel.spoof,
      _ => TestCaseLabel.unlabeled,
    };
