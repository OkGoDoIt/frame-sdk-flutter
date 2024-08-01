import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'frame_sdk_platform_interface.dart';
import 'bluetooth.dart';
import 'library_functions.dart';
import 'files.dart';
import 'microphone.dart';
import 'camera.dart';
import 'display.dart';

class Frame {
  final Logger logger = Logger('Frame');
  String? _luaOnWake;
  Function? _callbackOnWake;
  BrilliantDevice? _connectedDevice;
  late final Files files;
  late final Microphone microphone;
  late final Camera camera;
  late final Display display;

  Frame() {
    files = Files(this);
    microphone = Microphone(this);
    camera = Camera(this);
    display = Display(this);
  }

  BrilliantDevice get bluetooth {
    if (_connectedDevice == null) {
      throw Exception("Not connected to Frame device");
    }
    return _connectedDevice!;
  }

  bool get isConnected => _connectedDevice?.isConnected ?? false;

  Future<bool> connect(
      {Duration? timeout = const Duration(seconds: 30)}) async {
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

    return _connectedDevice?.isConnected ?? false;
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      if (_connectedDevice!.isConnected) {
        await _connectedDevice!.disconnect();
      }
      _connectedDevice = null;
    }
  }

  Future<void> ensureConnected() async {
    if (!isConnected) {
      if (!await connect()) {
        throw Exception("Failed to connect to Frame device");
      }
    }
  }

  Future<String?> runLua(String luaString,
      {bool awaitPrint = false,
      bool checked = false,
      Duration? timeout}) async {
    await ensureConnected();
    luaString =
        luaString.replaceAllMapped(RegExp(r'\bprint\('), (match) => 'prntLng(');

    if (luaString.length <= (bluetooth.maxStringLength ?? 0)) {
      if (checked && !awaitPrint) {
        luaString += ";print(\"+\")";
        if (luaString.length <= (bluetooth.maxStringLength ?? 0)) {
          final result = await bluetooth.sendString(luaString,
              awaitResponse: true, timeout: timeout);
          if (result != "+") {
            throw Exception("Lua did not run successfully: $result");
          }
          return null;
        }
      } else {
        return await bluetooth.sendString(luaString,
            awaitResponse: awaitPrint, timeout: timeout);
      }
    }

    return await sendLongLua(luaString,
        awaitPrint: awaitPrint, checked: checked, timeout: timeout);
  }

  Future<String?> sendLongLua(String string,
      {bool awaitPrint = false,
      bool checked = false,
      Duration? timeout}) async {
    await ensureConnected();

    final randomName = String.fromCharCodes(
        List.generate(4, (_) => Random().nextInt(26) + 97));

    // TODO: enable this once files are implemented
    //await files.writeFile("/$randomName.lua", utf8.encode(string),
    //    checked: true);
    String? response;
    if (awaitPrint) {
      response = await bluetooth.sendString("require(\"$randomName\")",
          awaitResponse: true, timeout: timeout);
    } else if (checked) {
      response = await bluetooth.sendString(
          "require(\"$randomName\");print('done')",
          awaitResponse: true,
          timeout: timeout);
      if (response != "done") {
        throw Exception("require() did not return 'done': $response");
      }
      response = null;
    } else {
      response = await bluetooth.sendString("require(\"$randomName\")");
    }
    // TODO: enable this once files are implemented
    //await files.deleteFile("/$randomName.lua");
    return response;
  }

  Future<int> getBatteryLevel() async {
    await ensureConnected();
    final response = await bluetooth.sendString("print(frame.battery_level())",
        awaitResponse: true);
    return int.parse(response ?? "-1");
  }

  Future<void> delay(Duration duration) async {
    await ensureConnected();
    await bluetooth.sendString(
        "frame.sleep(${(duration.inMilliseconds / 1000.0).toStringAsFixed(3)})");
  }

  Future<void> sleep([bool deep = false]) async {
    await ensureConnected();
    if (deep) {
      await bluetooth.sendString("frame.sleep()");
    } else {
      // TODO: impliment this after camera and motion are implimented
    }
  }

  Future<void> stayAwake(bool value) async {
    await ensureConnected();
    await runLua("frame.stay_awake(${value.toString().toLowerCase()})",
        checked: true);
  }

  Future<void> injectLibraryFunction(
      String name, String function, String version) async {
    await ensureConnected();

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
      await files.writeFile("/lib-$version/$name.lua", utf8.encode(function),
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

  Future<void> injectAllLibraryFunctions() async {
    final libraryVersion =
        libraryFunctions.hashCode.toRadixString(35).substring(0, 6);

    await ensureConnected();
    final response = await bluetooth.sendString(
        "frame.file.mkdir(\"lib-$libraryVersion\");print(\"c\")",
        awaitResponse: true);
    if (response == "c") {
      logger.info("Created lib directory");
    } else {
      logger.info("Did not create lib directory: $response");
    }
    await injectLibraryFunction("prntLng", libraryFunctions, libraryVersion);
  }

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

  Future<void> runOnWake({String? luaScript, void Function()? callback}) async {
    if (_wakeSubscription != null) {
      _wakeSubscription!.cancel();
      _wakeSubscription = null;
    }
    _callbackOnWake = callback;
    _luaOnWake = luaScript;
    _wakeSubscription = bluetooth.getDataOfType(FrameDataTypePrefixes.wake).listen((data) {
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
      await files.writeFile(
          "main.lua", utf8.encode("is_awake=true;$luaScript"),
          checked: true);
    } else {
      await files.writeFile("main.lua", utf8.encode("is_awake=true"),
          checked: true);
    }
  }

  int getCharCodeFromStringAtPos(String string, int pos) {
    return string.codeUnitAt(pos);
  }

  Future<String?> getPlatformVersion() {
    return FrameSdkPlatform.instance.getPlatformVersion();
  }
}
