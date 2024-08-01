import 'dart:async';
import 'dart:math';
import 'package:frame_sdk/bluetooth.dart';
import 'package:frame_sdk/frame_sdk.dart';

class Direction {
  final double roll;
  final double pitch;
  final double heading;

  const Direction({
    this.roll = 0.0,
    this.pitch = 0.0,
    this.heading = 0.0,
  });

  @override
  String toString() =>
      'Direction(roll: $roll, pitch: $pitch, heading: $heading)';

  Direction operator +(Direction other) {
    double newRoll = roll + other.roll;
    double newPitch = pitch + other.pitch;
    double newHeading = (heading + other.heading) % 360;

    newRoll = (newRoll + 180) % 360 - 180;
    newPitch = (newPitch + 180) % 360 - 180;

    return Direction(
      roll: newRoll,
      pitch: newPitch,
      heading: newHeading,
    );
  }

  Direction operator -(Direction other) {
    double newRoll = roll - other.roll;
    double newPitch = pitch - other.pitch;
    double newHeading = (heading - other.heading + 360) % 360;

    newRoll = (newRoll + 180) % 360 - 180;
    newPitch = (newPitch + 180) % 360 - 180;

    return Direction(
      roll: newRoll,
      pitch: newPitch,
      heading: newHeading,
    );
  }

  double amplitude() {
    return sqrt(roll * roll + pitch * pitch + heading * heading);
  }
}

class Motion {
  final Frame frame;

  Motion(this.frame);

  Future<Direction> getDirection() async {
    final result = await frame.runLua(
      "local dir = frame.imu.direction();print(dir['roll']..','..dir['pitch']..','..dir['heading'])",
      awaitPrint: true,
    );
    final values = result!.split(',').map(double.parse).toList();
    return Direction(roll: values[0], pitch: values[1], heading: values[2]);
  }

  StreamSubscription<void>? _tappedSubscription;

  Stream<void> tappedStream() {
    return frame.bluetooth.getDataOfType(FrameDataTypePrefixes.tap);
  }

  Future<void> runOnTap({String? luaScript, void Function()? callback}) async {
    if (_tappedSubscription != null) {
      _tappedSubscription!.cancel();
      _tappedSubscription = null;
    }

    if (callback != null) {
      _tappedSubscription = tappedStream().listen((_) => callback());
    }

    String luaCode = '';
    if (luaScript != null && callback != null) {
      luaCode =
          "function on_tap();frame.bluetooth.send('\\x${FrameDataTypePrefixes.tap.valueAsHex}');$luaScript;end;frame.imu.tap_callback(on_tap)";
    } else if (luaScript == null && callback != null) {
      luaCode =
          "function on_tap();frame.bluetooth.send('\\x${FrameDataTypePrefixes.tap.valueAsHex}');end;frame.imu.tap_callback(on_tap)";
    } else if (luaScript != null && callback == null) {
      luaCode =
          "function on_tap();$luaScript;end;frame.imu.tap_callback(on_tap)";
    } else {
      luaCode = "frame.imu.tap_callback(nil)";
    }

    await frame.runLua(luaCode, checked: callback == null);
  }

  Future<void> waitForTap() async {
    Completer<void> completer = Completer<void>();
    await runOnTap(callback: () => completer.complete());
    await completer.future;
    await runOnTap();
  }
}
