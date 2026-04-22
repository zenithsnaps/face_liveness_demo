import 'package:meta/meta.dart';

@immutable
class EulerAngles {
  final double yaw;   // left/right rotation, degrees
  final double pitch; // up/down rotation, degrees
  final double roll;  // tilt rotation, degrees

  const EulerAngles({
    required this.yaw,
    required this.pitch,
    required this.roll,
  });

  const EulerAngles.zero()
      : yaw = 0,
        pitch = 0,
        roll = 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EulerAngles &&
          other.yaw == yaw &&
          other.pitch == pitch &&
          other.roll == roll);

  @override
  int get hashCode => Object.hash(yaw, pitch, roll);

  @override
  String toString() => 'EulerAngles(yaw=$yaw, pitch=$pitch, roll=$roll)';
}
