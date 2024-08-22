import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'frame_sdk_platform_interface.dart';
import 'bluetooth.dart';
import 'files.dart';
import 'microphone.dart';
import 'camera.dart';
import 'display.dart';
import 'motion.dart';

class Frame {
  final Logger logger = Logger('Frame');
  String? _luaOnWake;
  Function? _callbackOnWake;
  BrilliantDevice? _connectedDevice;
  late final Files files;
  late final Microphone microphone;
  late final Camera camera;
  late final Display display;
  late final Motion motion;
  int timesToRetry = 1;
  int? _retryCount;
  bool useLibrary = true;
  // DateTime _lastTimeSync = DateTime.now();

  Frame() {
    files = Files(this);
    microphone = Microphone(this);
    camera = Camera(this);
    display = Display(this);
    motion = Motion(this);
  }

  /// Gets the connected Bluetooth device.
  ///
  /// Throws:
  ///   Exception: If not connected to a Frame device.
  BrilliantDevice get bluetooth {
    if (_connectedDevice == null) {
      throw Exception("Not connected to Frame device");
    }
    return _connectedDevice!;
  }

  /// Checks if the device is connected.
  bool get isConnected => _connectedDevice?.isConnected ?? false;

  /// Connects to the nearest Frame device.
  ///
  /// Args:
  ///   timeout (Duration?): The maximum time to wait for a connection. Defaults to 30 seconds.
  ///
  /// Returns:
  ///   Future<bool>: True if connected, false otherwise.
  Future<bool> connect(
      {Duration? timeout = const Duration(seconds: 30)}) async {
    bool wasConnected = isConnected;
    if (_connectedDevice == null) {
      try {
        _connectedDevice = await BrilliantBluetooth.getNearestFrame().timeout(
          timeout ?? const Duration(seconds: 30),
          onTimeout: () {
            throw TimeoutException("Failed to find a Frame device");
          },
        );
      } catch (e) {
        logger.warning("Error getting nearest device: $e");
        return false;
      }
    } else if (!_connectedDevice!.isConnected) {
      _connectedDevice =
          await BrilliantBluetooth.reconnect(_connectedDevice!.id);
    }
    bool isConnectedNow = _connectedDevice?.isConnected ?? false;

    if (!wasConnected && isConnectedNow) {
      bluetooth.stringResponse.listen((data) {
        if (data.startsWith("[")) {
          if (data.contains("break signal")) {
            logger.info("Frame break signal: $data");
          } else if (data.contains("cannot open file")) {
            logger.info("Frame error: $data");
          } else {
            logger.warning("Frame error: $data");
          }
        }
      });
      await bluetooth.sendBreakSignal();
      bluetooth.getDataOfType(FrameDataTypePrefixes.debugPrint).listen((data) {
        logger.info("Debug print: ${utf8.decode(data)}");
      });
      if (useLibrary) {
        await injectAllLibraryFunctions();
      }
      await setTimeOnFrame(checked: true);
      await runLua("is_awake=true", checked: true);
    }

    return isConnectedNow;
  }

  /// Connects to a specific Frame device.
  ///
  /// Args:
  ///   deviceId (String): The ID of the device to connect to.
  ///
  /// Returns:
  ///   Future<bool>: True if connected, false otherwise.
  Future<bool> connectToDevice(String deviceId) async {
    bool wasConnected = isConnected;
    if (_connectedDevice == null) {
      _connectedDevice = await BrilliantBluetooth.reconnect(deviceId);
    } else if (!_connectedDevice!.isConnected) {
      _connectedDevice = await BrilliantBluetooth.reconnect(deviceId);
    }
    bool isConnectedNow = _connectedDevice?.isConnected ?? false;
    if (!wasConnected && isConnectedNow) {
      await bluetooth.sendBreakSignal();
    }

    if (!wasConnected && isConnectedNow) {
      await bluetooth.sendBreakSignal();
      bluetooth.getDataOfType(FrameDataTypePrefixes.debugPrint).listen((data) {
        logger.info("Debug print: ${utf8.decode(data)}");
      });
      if (useLibrary) {
        await injectAllLibraryFunctions();
      }
      await setTimeOnFrame(checked: true);
      await runLua("is_awake=true", checked: true);
    }

    return isConnectedNow;
  }

  /// Sets the time on the Frame device.
  ///
  /// Args:
  ///   checked (bool): Whether to wait for confirmation of successful execution. Defaults to false.
  Future<void> setTimeOnFrame({bool checked = false}) async {
    String utcUnixEpochTime =
        (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).toString();
    String timeZoneOffset =
        DateTime.now().timeZoneOffset.inMinutes > 0 ? '+' : '-';
    timeZoneOffset +=
        '${DateTime.now().timeZoneOffset.inHours.abs().toString().padLeft(2, '0')}:${(DateTime.now().timeZoneOffset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
    logger.info(
        "Setting time to $utcUnixEpochTime and time zone to $timeZoneOffset");
    await runLua(
        "frame.time.utc($utcUnixEpochTime);frame.time.zone('$timeZoneOffset')",
        checked: checked,
        withoutHelpers: true);
    //_lastTimeSync = DateTime.now();
  }

  /// Disconnects from the Frame device.
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      if (_connectedDevice!.isConnected) {
        await _connectedDevice!.disconnect();
      }
      _connectedDevice = null;
    }
  }

  /// Ensures the Frame device is connected, establishing a connection if not.
  Future<void> ensureConnected() async {
    if (!isConnected) {
      if (!await connect()) {
        _retryCount ??= 0;
        if ((_retryCount ?? 99) < timesToRetry) {
          _retryCount = (_retryCount ?? 99) + 1;
          await ensureConnected();
          _retryCount = null;
        } else {
          throw BrilliantBluetoothException(
              "Failed to connect to Frame device with the timeout of ${bluetooth.defaultTimeout}");
        }
      }
    }
  }

  static const _chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// Generates a random string of the given length.
  ///
  /// Args:
  ///   length (int): The length of the random string.
  ///
  /// Returns:
  ///   String: The generated random string.
  String _generateRandomString(int length) {
    return String.fromCharCodes(List.generate(
        length, (_) => _chars.codeUnitAt(Random().nextInt(_chars.length))));
  }

  /// Runs a Lua string on the device.
  ///
  /// Args:
  ///   luaString (String): The Lua code to execute.
  ///   awaitPrint (bool): Whether to wait for a print statement from the Lua code. Defaults to false.
  ///   checked (bool): Whether to wait for confirmation of successful execution. Defaults to false.
  ///   timeout (Duration?): The maximum time to wait for execution.
  ///   withoutHelpers (bool): Whether to run the Lua code without library helpers. Mainly used internally by the SDK to bootstrap additional functions. Defaults to false.
  ///
  /// Returns:
  ///   Future<String?>: The result of the Lua execution if `awaitPrint` is true.
  Future<String?> runLua(String luaString,
      {bool awaitPrint = false,
      bool checked = false,
      Duration? timeout,
      bool withoutHelpers = false}) async {
    await ensureConnected();
    if (useLibrary && !withoutHelpers) {
      luaString = luaString.replaceAllMapped(
          RegExp(r'\bprint\('), (match) => 'prntLng(');
    }
    if (luaString.length <= (bluetooth.maxStringLength ?? 0)) {
      if (checked && !awaitPrint) {
        final checkString = _generateRandomString(3);
        final checkedLuaString = "$luaString;print(\"+$checkString\")";
        if (checkedLuaString.length <= (bluetooth.maxStringLength ?? 0)) {
          final waitingForResponse =
              bluetooth.waitForString(match: "+$checkString", timeout: timeout);
          await bluetooth.sendString(checkedLuaString, awaitResponse: false);
          await waitingForResponse;

          return null;
        }
      } else {
        return await bluetooth.sendString(luaString,
            awaitResponse: awaitPrint, timeout: timeout);
      }
    }

    if (useLibrary && !withoutHelpers) {
      return await sendLongLua(luaString,
          awaitPrint: awaitPrint, checked: checked, timeout: timeout);
    } else {
      // the string is too long to send without helpers
      logger.severe("The string is too long to send without library helpers");
      throw const BrilliantBluetoothException(
          "The string is too long to send without library helpers");
    }
  }

  /// Sends a Lua string to the device that is longer than the MTU limit.
  ///
  /// Args:
  ///   string (String): The Lua code to execute.
  ///   awaitPrint (bool): Whether to wait for a print statement from the Lua code. Defaults to false.
  ///   checked (bool): Whether to wait for confirmation of successful execution. Defaults to false.
  ///   timeout (Duration?): The maximum time to wait for execution.
  ///
  /// Returns:
  ///   Future<String?>: The result of the Lua execution if `awaitPrint` is true.
  Future<String?> sendLongLua(String string,
      {bool awaitPrint = false,
      bool checked = false,
      Duration? timeout}) async {
    await ensureConnected();

    final randomName = String.fromCharCodes(
        List.generate(6, (_) => Random().nextInt(26) + 97));

    await files.writeFile("/$randomName.lua", utf8.encode(string),
        checked: true);
    String? response;
    if (awaitPrint) {
      response = await bluetooth.sendString("require(\"$randomName\")",
          awaitResponse: true, timeout: timeout);
    } else if (checked) {
      final checkString = _generateRandomString(3);
      final waitingForResponse =
          bluetooth.waitForString(match: ">$checkString", timeout: timeout);
      response = await bluetooth.sendString(
          "require(\"$randomName\");print('>$checkString')",
          awaitResponse: false);
      await waitingForResponse;
      response = null;
    } else {
      response = await bluetooth.sendString("require(\"$randomName\")");
    }

    await files.deleteFile("/$randomName.lua");
    return response;
  }

  /// Evaluates a Lua expression on the device and returns the result.
  ///
  /// Args:
  ///   luaExpression (String): The Lua expression to evaluate.
  ///
  /// Returns:
  ///   Future<String>: The result of the evaluation.
  Future<String> evaluate(String luaExpression) async {
    await ensureConnected();
    if (useLibrary) {
      return await runLua("prntLng(tostring($luaExpression))",
              awaitPrint: true) ??
          '';
    } else {
      return await runLua("print($luaExpression)", awaitPrint: true) ?? '';
    }
  }

  /// Returns the battery level as a percentage between 1 and 100.
  ///
  /// Returns:
  ///   Future<int>: The battery level percentage.
  Future<int> getBatteryLevel() async {
    await ensureConnected();
    final response = await bluetooth.sendString("print(frame.battery_level())",
        awaitResponse: true);
    try {
      return double.parse(response ?? "-1").toInt();
    } catch (e) {
      return -1;
    }
  }

  /// Delays execution on Frame for a given duration. Technically this sends a sleep command,
  /// but it doesn't actually change the power mode. This function does not block, returning immediately.
  ///
  /// Args:
  ///   duration (Duration): The duration to sleep.
  ///
  /// Throws:
  ///   ArgumentError: If the duration is negative or zero.
  Future<void> delay(Duration duration) async {
    await ensureConnected();
    await bluetooth.sendString(
        "frame.sleep(${(duration.inMilliseconds / 1000.0).toStringAsFixed(3)})");
  }

  /// Puts the Frame into sleep mode. There are two modes: normal and deep.
  ///
  /// Normal sleep mode can still receive bluetooth data, and is essentially the same as
  /// clearing the display and putting the camera in low power mode. The Frame will retain
  /// the time and date, and any functions and variables will stay in memory.
  ///
  /// Deep sleep mode saves additional power, but has more limitations. The Frame will not
  /// retain the time and date, and any functions and variables will not stay in memory.
  /// Bluetooth data will not be received. The only way to wake the Frame from deep sleep
  /// is to tap it.
  ///
  /// The difference in power usage is fairly low, so it's often best to use normal sleep
  /// mode unless you need the extra power savings.
  ///
  /// Args:
  ///   deep (bool): If true, puts the Frame into deep sleep mode. Defaults to false.
  Future<void> sleep([bool deep = false]) async {
    await ensureConnected();
    if (deep) {
      await bluetooth.sendString("frame.sleep()");
    } else {
      if (_luaOnWake != null || _callbackOnWake != null) {
        String runOnWake = _luaOnWake ?? "";
        if (_callbackOnWake != null) {
          runOnWake =
              "frame.bluetooth.send('\\x${FrameDataTypePrefixes.wake.valueAsHex}');$runOnWake";
        }
        runOnWake = "if not is_awake then;is_awake=true;$runOnWake;end";
        logger.info("Running on wake: $runOnWake");
        motion.runOnTap(luaScript: runOnWake);
      }
      await runLua(
          "frame.display.text(' ',1,1);frame.display.show();frame.camera.sleep()",
          checked: true);
      camera.isAwake = false;
    }
  }

  /// Prevents Frame from going to sleep while it's docked onto the charging cradle.
  /// This can help during development where continuous power is needed, however may
  /// degrade the display or cause burn-in if used for extended periods of time.
  ///
  /// Args:
  ///   value (bool): True to stay awake, False to allow sleep.
  Future<void> stayAwake(bool value) async {
    await ensureConnected();
    await runLua("frame.stay_awake(${value.toString().toLowerCase()})",
        checked: true);
  }

  /// Injects a function into the global environment of the device. Used to push helper library functions to the device.
  ///
  /// Args:
  ///   name (String): The name of the function.
  ///   function (String): The function code.
  ///   version (String): The version of the function.
  Future<void> injectLibraryFunction(
      String name, String function, String version) async {
    final exists =
        await bluetooth.sendString("print($name ~= nil)", awaitResponse: true);
    logger.info("Function $name exists: $exists");

    if (exists != "true") {
      final fileExists = await files.fileExists("/lib-$version/$name.lua");
      logger.info("File /lib-$version/$name.lua exists: $fileExists");

      if (fileExists) {
        final response = await bluetooth.sendString(
            "require(\"lib-$version/$name\");print(\"l\")",
            awaitResponse: true);
        if (response == "l") {
          return;
        }
      }

      logger.info("Writing file /lib-$version/$name.lua");
      await files.writeFile("/lib-$version/$name.lua",
          utf8.encode(function.replaceAll("\t", "").replaceAll("\n\n", "\n")),
          checked: true);

      logger.info("Requiring lib-$version/$name");
      final response = await bluetooth.sendString(
          "require(\"lib-$version/$name\");print(\"l\")",
          awaitResponse: true);
      if (response != "l") {
        throw Exception("Error injecting library function: $response");
      }
    }
  }

  late String _frameLib;

  /// Injects all library functions into the global environment of the device.
  Future<void> injectAllLibraryFunctions() async {
    if (!useLibrary) {
      return;
    }
    _frameLib = await rootBundle.loadString('packages/frame_sdk/assets/frameLib.lua');
    _frameLib = _frameLib.replaceAll("\t", "").replaceAll("\n\n", "\n");

    for (var prefix in FrameDataTypePrefixes.values) {
      // ignore: prefer_interpolation_to_compose_strings
      String placeholder = r'${FrameDataTypePrefixes.' + prefix.name + '.valueAsHex}';
      _frameLib = _frameLib.replaceAll(placeholder, prefix.valueAsHex);
    }

    
    final libraryVersion =
        _frameLib.hashCode.toRadixString(35).substring(0, 5);
    final response = await bluetooth.sendString(
        "frame.file.mkdir(\"lib-$libraryVersion\");print(\"c\")",
        awaitResponse: true);
    if (response == "c") {
      logger.info("Created lib directory");
    } else {
      logger.info("Did not create lib directory: $response");
    }
    await injectLibraryFunction("prntLng", _frameLib, libraryVersion);
  }

  /// Escapes a string for use in Lua.
  ///
  /// Args:
  ///   string (String): The string to escape.
  ///
  /// Returns:
  ///   String: The escaped string.
  String escapeLuaString(String string) {
    return string
        .replaceAll("\\", "\\\\")
        .replaceAll("\n", "\\n")
        .replaceAll("\r", "\\r")
        .replaceAll("\t", "\\t")
        .replaceAll("\"", "\\\"")
        .replaceAll("[", "[")
        .replaceAll("]", "]");
  }

  StreamSubscription<Uint8List>? _wakeSubscription;

  /// Runs a Lua function when the device wakes up from sleep. Can include Lua code to be run on Frame upon wake and/or a Dart callback to be run locally upon wake.
  ///
  /// Args:
  ///   luaScript (String?): The Lua script to run on wake.
  ///   callback (Function?): The callback to run on wake.
  Future<void> runOnWake({String? luaScript, void Function()? callback}) async {
    if (_wakeSubscription != null) {
      _wakeSubscription!.cancel();
      _wakeSubscription = null;
    }
    _callbackOnWake = callback;
    _luaOnWake = luaScript;
    _wakeSubscription =
        bluetooth.getDataOfType(FrameDataTypePrefixes.wake).listen((data) {
      if (_callbackOnWake != null) {
        _callbackOnWake!();
      }
    });

    if (luaScript != null && callback != null) {
      await files.writeFile("main.lua",
          "is_awake=true;frame.bluetooth.send('\\x${FrameDataTypePrefixes.wake.valueAsHex}')",
          checked: true);
    } else if (luaScript == null && callback != null) {
      await files.writeFile("main.lua",
          "is_awake=true;frame.bluetooth.send('\\x${FrameDataTypePrefixes.wake.valueAsHex}')",
          checked: true);
    } else if (luaScript != null && callback == null) {
      await files.writeFile("main.lua", utf8.encode("is_awake=true;$luaScript"),
          checked: true);
    } else {
      await files.writeFile("main.lua", utf8.encode("is_awake=true"),
          checked: true);
    }
  }

  /// Gets the character code from a string at the specified position.
  ///
  /// Args:
  ///   string (String): The string to get the character code from.
  ///   pos (int): The position of the character.
  ///
  /// Returns:
  ///   int: The character code.
  int getCharCodeFromStringAtPos(String string, int pos) {
    return string.codeUnitAt(pos);
  }

  /// Gets the platform version.
  ///
  /// Returns:
  ///   Future<String?>: The platform version.
  Future<String?> getPlatformVersion() {
    return FrameSdkPlatform.instance.getPlatformVersion();
  }
}
