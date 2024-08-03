import 'dart:async';
import 'dart:math';
import 'package:frame_sdk/bluetooth.dart';
import 'package:frame_sdk/frame_sdk.dart';

/// Represents a direction in 3D space.
class Direction {
  /// The roll angle of the Frame in degrees.
  final double roll;

  /// The pitch angle of the Frame in degrees.
  final double pitch;

  /// NOT YET IMPLEMENTED: The heading angle of the Frame in degrees.  Always returns 0 for now.
  final double heading;

  /// Initializes the Direction with roll, pitch, and heading values.
  ///
  /// Args:
  ///   roll (double): The roll angle of the Frame in degrees.
  ///   pitch (double): The pitch angle of the Frame in degrees.
  ///   heading (double): The heading angle of the Frame in degrees.
  const Direction({
    this.roll = 0.0,
    this.pitch = 0.0,
    this.heading = 0.0,
  });

  @override
  String toString() =>
      'Direction(roll: $roll, pitch: $pitch, heading: $heading)';

  /// Adds two Direction objects.
  ///
  /// Args:
  ///   other (Direction): The other Direction object to add.
  ///
  /// Returns:
  ///   Direction: A new Direction object representing the sum of the two directions.
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

  /// Subtracts one Direction object from another.
  ///
  /// Args:
  ///   other (Direction): The other Direction object to subtract.
  ///
  /// Returns:
  ///   Direction: A new Direction object representing the difference between the two directions.
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

  /// Calculates the amplitude of the Direction vector.
  ///
  /// Returns:
  ///   double: The amplitude of the Direction vector.
  double amplitude() {
    return sqrt(roll * roll + pitch * pitch + heading * heading);
  }
}

/// Handles motion on the Frame IMU.
class Motion {
  final Frame frame;

  /// Initializes the Motion class with a Frame instance.
  ///
  /// Args:
  ///   frame (Frame): The Frame instance to associate with the Motion class.
  Motion(this.frame);

  /// Gets the orientation of the Frame.
  /// Note that the heading is not yet implemented on Frame and will always return 0.
  ///
  /// Returns:
  ///   Future<Direction>: The current direction of the Frame.
  Future<Direction> getDirection() async {
    final result = await frame.runLua(
      "local dir = frame.imu.direction();print(dir['roll']..','..dir['pitch']..','..dir['heading'])",
      awaitPrint: true,
    );
    final values = result!.split(',').map(double.parse).toList();
    return Direction(roll: values[0], pitch: values[1], heading: values[2]);
  }

  StreamSubscription<void>? _tappedSubscription;

  /// Returns a stream that emits events when the Frame is tapped.
  ///
  /// Returns:
  ///   Stream<void>: A stream of tap events.
  Stream<void> tappedStream() {
    return frame.bluetooth.getDataOfType(FrameDataTypePrefixes.tap);
  }

  /// Runs a callback when the Frame is tapped. Can include Lua code to be run on Frame upon tap and/or a Dart callback to be run locally upon tap.  Clears any existing callbacks and replaces them with the new ones passed in, so pass in null for both arguments if you want to remove any existing callbacks.
  ///
  /// Args:
  ///   luaScript (String?): The Lua script to run on tap.
  ///   callback (void Function()?): The callback to run on tap.
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

  /// Waits for the Frame to be tapped before continuing.
  Future<void> waitForTap() async {
    Completer<void> completer = Completer<void>();
    await runOnTap(callback: () => completer.complete());
    await completer.future;
    await runOnTap();
  }
}