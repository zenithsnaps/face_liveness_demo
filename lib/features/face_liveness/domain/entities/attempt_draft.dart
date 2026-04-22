import 'package:meta/meta.dart';

@immutable
class AttemptDraft {
  final String id;
  final DateTime startedAt;

  const AttemptDraft({required this.id, required this.startedAt});
}
