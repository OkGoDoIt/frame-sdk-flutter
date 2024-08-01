import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:frame_sdk/camera.dart';
import 'package:frame_sdk/display.dart';
import 'package:frame_sdk/frame_sdk.dart';
import 'package:frame_sdk/bluetooth.dart';
import 'package:frame_sdk/motion.dart';

import 'package:logging/logging.dart';
import 'package:collection/collection.dart';

void main() {
  // Request bluetooth permission
  BrilliantBluetooth.requestPermission();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _frameSdkPlugin = Frame();
  final List<String> _logMessages = [];
  late final Frame frame;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    initPlatformState();
    frame = Frame();

    runExample();
  }

  Future<void> runExample() async {
    var logger = Logger('Frame');
    logger.onRecord.listen((record) {
      print("Log (${record.level.name}): ${record.message}");
    });

    await frame.ensureConnected();

    assertTrue('Connected to device', frame.bluetooth.isConnected);

    assertEqual("Evaluate 1", "1", await frame.evaluate("1"));
    assertEqual("Evaluate 2", "2", await frame.evaluate("2"));
    assertEqual("Evaluate 3", "3", await frame.evaluate("3"));

    // Test Bluetooth
    assertEqual(
        "Send lua with response",
        "hi",
        await frame.bluetooth.sendString("print('hi')", awaitResponse: true) ??
            "");
    assertEqual("Send lua without response", null,
        await frame.bluetooth.sendString("tester = 1"));

/*
    assertRaises(
        "Fail to receive response",
        () async => await frame.bluetooth.sendString("tester = 2",
            awaitResponse: true, timeout: const Duration(seconds: 3)));
*/
    assertEqual(
        "Send complex lua with response",
        "c",
        await frame.bluetooth.sendString(
            "frame.bluetooth.receive_callback((function(d)frame.bluetooth.send(d)end));print('c')",
            awaitResponse: true));

    assertEqual(
        "send and receive data",
        "test",
        utf8.decode((await frame.bluetooth.sendData(
            Uint8List.fromList(utf8.encode("test")),
            awaitResponse: true))!));

    assertEqual(
        "send and receive data again",
        "still testing",
        utf8.decode((await frame.bluetooth.sendData(
            Uint8List.fromList(utf8.encode("still testing")),
            awaitResponse: true))!));

    assertEqual(
        "send data without response",
        null,
        await frame.bluetooth
            .sendData(Uint8List.fromList(utf8.encode("test"))));

    await frame.bluetooth.sendString("frame.bluetooth.receive_callback(nil)");

    String longToSend =
        "a = 0;${List.generate(32, (i) => "a = a + 1;").join(" ")}print(a)";
    var longResult = await frame.sendLongLua(longToSend, awaitPrint: true);

    // Test Frame
    assertEqual("Long send lua", "32", longResult);

    assertEqual("Long receive lua", "hi",
        await frame.runLua("prntLng('hi')", awaitPrint: true));

    var msg = "hello world! " * 32;
    await frame.runLua(
        "msg = \"hello world! \";" +
            List.generate(5, (i) => "msg = msg .. msg;").join(""),
        checked: true);
    assertEqual("Long receive lua message", msg, await frame.evaluate("msg"));

    var batteryLevel = await frame.getBatteryLevel();
    assertTrue(
        "Battery level is valid", batteryLevel > 0 && batteryLevel <= 100);

    // Test long send and receive
    int aCount = 2;
    String message = List.generate(aCount, (i) => "and $i, ").join();
    String script = "message = '';" +
        List.generate(aCount, (i) => "message = message .. 'and $i, '; ")
            .join() +
        "print(message)";
    assertEqual("Long send and receive lua (a=2)", message,
        await frame.runLua(script, awaitPrint: true));

    // Test longer send and receive
    aCount = 50;
    message = List.generate(aCount, (i) => "and $i, ").join();
    script = "message = '';" +
        List.generate(aCount, (i) => "message = message .. 'and $i, '; ")
            .join() +
        "print(message)";
    assertEqual("Longer send and receive lua (a=50)", message,
        await frame.runLua(script, awaitPrint: true));

    // Test battery level comparison
    var batteryLevelFromEvaluate =
        double.parse(await frame.evaluate("frame.battery_level()")).toInt();
    assertAlmostEqual(
        "Battery level from getBatteryLevel and evaluate are close",
        batteryLevel,
        batteryLevelFromEvaluate,
        15);

    // Test time synchronization
    var frameTime = double.parse(await frame.evaluate("frame.time.utc()"));
    var currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    assertAlmostEqual(
        "Frame time is close to current time", frameTime, currentTime, 5);

    // Test Files

    var content = "Testing:\n" +
        ("test1... " * 200) +
        "\nTesting 2:\n" +
        ("test2\n" * 100);
    await frame.files
        .writeFile("test.txt", utf8.encode(content), checked: true);
    var actualContent = await frame.files.readFile("test.txt");
    assertEqual("Long file content matches", content.trim(),
        utf8.decode(actualContent).trim());

    actualContent = await frame.files.readFile("test.txt");
    assertEqual("Long file content matches on second read", content.trim(),
        utf8.decode(actualContent).trim());

    await frame.files.deleteFile("test.txt");

    var rawContent = Uint8List.fromList(List.generate(254, (i) => i + 1));
    await frame.files.writeFile("test.dat", rawContent, checked: true);
    actualContent = await frame.files.readFile("test.dat");
    assertEqual("Raw file content matches", rawContent, actualContent);

    actualContent = await frame.files.readFile("test.dat");
    assertEqual(
        "Raw file content matches on second read", rawContent, actualContent);

    await frame.files.writeFile("test.dat", rawContent, checked: true);
    actualContent = await frame.files.readFile("test.dat");
    assertEqual(
        "Raw file content matches after rewrite", rawContent, actualContent);

    actualContent = await frame.files.readFile("test.dat");
    assertEqual("Raw file content matches on second read after rewrite",
        rawContent, actualContent);

    await frame.files.deleteFile("test.dat");

    // Test Camera

    var photo = await frame.camera.takePhoto();
    assertTrue("took photo content greater than 2kb", photo.length > 2000);

    // Test Camera with autofocus options

    var startTime = DateTime.now();
    var photoWithoutAutofocus = await frame.camera.takePhoto();
    var endTime = DateTime.now();
    var timeWithoutAutofocus = endTime.difference(startTime);
    assertTrue("photo without autofocus content greater than 2kb",
        photoWithoutAutofocus.length > 2000);

    startTime = DateTime.now();
    var photoWithAutofocus1Sec = await frame.camera
        .takePhoto(autofocusSeconds: 1, autofocusType: AutoFocusType.spot);
    endTime = DateTime.now();
    var timeWithAutofocus1Sec = endTime.difference(startTime);
    assertTrue("photo with 1 sec autofocus content greater than 2kb",
        photoWithAutofocus1Sec.length > 2000);
    assertTrue("photo with 1 sec autofocus takes longer than without autofocus",
        timeWithAutofocus1Sec > timeWithoutAutofocus);

    startTime = DateTime.now();
    var photoWithAutofocus3Sec = await frame.camera.takePhoto(
        autofocusSeconds: 3, autofocusType: AutoFocusType.centerWeighted);
    endTime = DateTime.now();
    var timeWithAutofocus3Sec = endTime.difference(startTime);
    assertTrue("photo with 3 sec autofocus content greater than 2kb",
        photoWithAutofocus3Sec.length > 2000);
    assertTrue("photo with 3 sec autofocus takes longer than 1 sec autofocus",
        timeWithAutofocus3Sec > timeWithAutofocus1Sec);

    // Test Camera with quality options

    var lowQualityPhoto =
        await frame.camera.takePhoto(quality: PhotoQuality.low);
    assertTrue("low quality photo content greater than 2kb",
        lowQualityPhoto.length > 2000);

    var mediumQualityPhoto =
        await frame.camera.takePhoto(quality: PhotoQuality.medium);
    assertTrue("medium quality photo content greater than 2kb",
        mediumQualityPhoto.length > 2000);
    assertTrue("medium quality photo larger than low quality",
        mediumQualityPhoto.length > lowQualityPhoto.length);

    var highQualityPhoto =
        await frame.camera.takePhoto(quality: PhotoQuality.high);
    assertTrue("high quality photo content greater than 2kb",
        highQualityPhoto.length > 2000);
    assertTrue("high quality photo larger than medium quality",
        highQualityPhoto.length > mediumQualityPhoto.length);

    // Test Display
    await frame.display
        .showText("Lorem ipsum dolor sit amet, consectetur adipiscing elit.");

    await frame.display.clear();

    await frame.display.showText(
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
        color: PaletteColors.green);

    int oldWidth = frame.display.getTextWidth("Lorem ipsum!");
    frame.display.charSpacing = 10;
    await frame.display
        .showText("Lorem ipsum dolor sit amet, consectetur adipiscing elit.");
    int newWidth = frame.display.getTextWidth("Lorem ipsum!");
    assertGreaterThan("Text width", newWidth, oldWidth + 5 * 10);

    frame.display.charSpacing = 4;
    // Test Display - Draw rectangles

    await frame.display.drawRect(1, 1, 640, 400, color: PaletteColors.red);
    await frame.display.drawRect(300, 300, 10, 10, color: PaletteColors.green);
    await frame.display.drawRectFilled(
        50, 50, 300, 300, 8, PaletteColors.skyBlue, PaletteColors.darkBrown);
    await frame.display.show();
    await frame.display.clear();

    // Test Display - Word wrap
    String testText = "Hi bob! " * 100;
    String wrapped400 = frame.display.wrapText(testText, 400);
    String wrapped800 = frame.display.wrapText(testText, 800);
    assertEqual("Wrapped text exclamation count remains the same",
        wrapped400.split("!").length - 1, wrapped800.split("!").length - 1);
    assertAlmostEqual("Wrapped text newline count increases",
        wrapped400.split("\n").length, wrapped800.split("\n").length * 2, 3);
    assertAlmostEqual(
        "Wrapped text height",
        frame.display.getTextHeight(wrapped400),
        frame.display.getTextHeight(wrapped800) * 2,
        100);

    frame.display.charSpacing = 10;
    String wideWrapped400 = frame.display.wrapText(testText, 400);
    assertGreaterThan(
        "Wrapped text height increases when we increase char spacing",
        frame.display.getTextHeight(wideWrapped400),
        frame.display.getTextHeight(wrapped400) + 20);
    frame.display.charSpacing = 4;

    // Test Display - Line height
    int initialLineHeight = frame.display.lineHeight;
    assertEqual("Initial line height", initialLineHeight,
        frame.display.getTextHeight("hello world!  123Qgjp@"));
    int heightOfTwoLines = frame.display.getTextHeight("hello\nworldj");
    frame.display.lineHeight += 20;
    assertEqual("Increased line height", heightOfTwoLines + 40,
        frame.display.getTextHeight("hello p\nworld j"));
    frame.display.lineHeight = initialLineHeight; // Reset line height

    // Test Display - Scroll text

    testText =
        "Lorem \"ipsum\" [dolor] 'sit' amet,    consectetur adipiscing elit.\n"
        "Nulla nec nunc euismod, consectetur nunc eu, aliquam nunc.\n"
        "Nulla lorem nec nunc euismod, ipsum consectetur nunc eu, aliquam nunc.";

    Stopwatch stopwatch = Stopwatch()..start();
    await frame.display.scrollText(testText);
    stopwatch.stop();
    int elapsedTime1 = stopwatch.elapsedMilliseconds;

    assertTrue("Scroll text time within range",
        elapsedTime1 >= 5000 && elapsedTime1 < 20000);

    stopwatch.reset();
    stopwatch.start();
    await frame.display.scrollText(testText * 3);
    stopwatch.stop();
    int elapsedTime2 = stopwatch.elapsedMilliseconds;

    assertAlmostEqual(
        "Scroll text time proportional", elapsedTime1 * 3, elapsedTime2, 8000);

    // Test Microphone
    frame.microphone.sampleRate = 8000;
    frame.microphone.bitDepth = 16;
    var audioData = await frame.microphone
        .recordAudio(maxLength: const Duration(seconds: 5));
    assertTrue("Record audio", audioData.isNotEmpty);
    // Test Microphone - End on silence
    await frame.display.showText("Testing microphone, please be silent!");
    var silentAudio = await frame.microphone.recordAudio(
        maxLength: const Duration(seconds: 20),
        silenceCutoffLength: const Duration(seconds: 2));
    await frame.display.clear();
    assertTrue("End on silence recording shorter than max",
        silentAudio.length < 5 * 8000);

    // Test Microphone - Save audio file
    await frame.display.showText("Testing microphone, please be silent!");
    var length = await frame.microphone.saveAudioFile("test.wav",
        maxLength: const Duration(seconds: 20),
        silenceCutoffLength: const Duration(seconds: 2));
    await frame.display.clear();
    assertTrue("Saved audio file length", length < 5);
    var file = File("test.wav");
    assertTrue("Audio file exists", await file.exists());
    assertTrue(
        "Audio file size greater than 500b", (await file.length()) > 500);
    await file.delete();

    // Test Microphone - Record and play audio
    for (var sampleRate in [8000, 16000]) {
      for (var bitDepth in [8, 16]) {
        if (sampleRate == 16000 && bitDepth == 16) continue;
        frame.microphone.sampleRate = sampleRate;
        frame.microphone.bitDepth = bitDepth;
        var data = await frame.microphone
            .recordAudio(maxLength: const Duration(seconds: 5));

        var stopwatch = Stopwatch()..start();
        await frame.microphone.playAudio(data);
        stopwatch.stop();
        assertAlmostEqual("Play audio duration", 5,
            stopwatch.elapsedMilliseconds / 1000, 0.5);
        assertAlmostEqual(
            "Play audio matches data length",
            data.length / frame.microphone.sampleRate,
            stopwatch.elapsedMilliseconds / 1000,
            0.2);

        stopwatch.reset();
        stopwatch.start();
        await frame.microphone.playAudio(data);
        stopwatch.stop();
        assertAlmostEqual(
            "Async play audio matches data length",
            data.length / frame.microphone.sampleRate,
            stopwatch.elapsedMilliseconds / 1000,
            0.2);

        stopwatch.reset();
        stopwatch.start();
        frame.microphone.playAudio(data);
        stopwatch.stop();
        assertAlmostEqual("Background play audio start time", 0,
            stopwatch.elapsedMilliseconds / 1000, 0.1);
      }
    }

    // Test Motion
    var direction = await frame.motion.getDirection();
    assertTrue("Get direction pitch within range",
        direction.pitch >= -180 && direction.pitch <= 180);
    assertTrue("Get direction roll within range",
        direction.roll >= -180 && direction.roll <= 180);
    assertTrue("Get direction heading within range",
        direction.heading >= 0 && direction.heading <= 360);

    // Test motion consistency
    await frame.display.showText("Testing motion, don't move the Frame!");
    Direction direction1 = await frame.motion.getDirection();
    await Future.delayed(const Duration(seconds: 1));
    Direction direction2 = await frame.motion.getDirection();
    await frame.display.clear();

    Direction diff = direction2 - direction1;
    assertAlmostEqual("Motion difference amplitude", 0, diff.amplitude(), 10);
    assertAlmostEqual(
        "Pitch consistency", direction1.pitch, direction2.pitch, 5);
    assertAlmostEqual("Roll consistency", direction1.roll, direction2.roll, 5);
    assertAlmostEqual(
        "Heading consistency", direction1.heading, direction2.heading, 5);

    // Test tap handler registration
    await frame.display.showText("Testing tap, tap the Frame!");

    // Test with Lua script
    await frame.motion.runOnTap(luaScript: "print('Tapped!')");

    // Test with Dart callback
    await frame.motion
        .runOnTap(callback: () => frame.display.showText("Tapped!"));

    // Test with both Lua script and Dart callback
    await frame.motion.runOnTap(
        luaScript: "print('tap1')",
        callback: () => frame.display.showText("Tapped again!"));

    // Test clearing tap handlers
    await frame.motion.runOnTap(luaScript: null, callback: null);

    // Test sleep
    await frame.runLua("test_var = 55", checked: true);

    frameTime = double.parse(await frame.evaluate("frame.time.utc()"));
    currentTime = DateTime.now().millisecondsSinceEpoch / 1000.0;
    assertAlmostEqual("Frame time is close to current time before sleep",
        frameTime, currentTime, 2);

    await frame.sleep();

    assertEqual("Variable persists after sleep", "55",
        await frame.evaluate("test_var"));

    // Check that the camera is not awake after sleep
    assertTrue("Camera is not awake after sleep", !frame.camera.isAwake);

    // Take a photo and verify that the camera wakes up
    var result = await frame.camera
        .takePhoto(autofocusSeconds: 1, quality: PhotoQuality.low);
    assertGreaterThan("photo has data", result.lengthInBytes, 100);

    assertTrue("Camera is awake after taking photo", frame.camera.isAwake);


    _addLogMessage("All tests completed.");
  }

  Future<void> initPlatformState() async {
    String platformVersion;
    try {
      platformVersion = await _frameSdkPlugin.getPlatformVersion() ??
          'Unknown platform version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
      _addLogMessage(platformVersion);
    }

    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
      _addLogMessage('Platform version: $platformVersion');
    });
  }

  void assertTrue(String message, bool condition) async {
    if (condition) {
      _addLogMessage('✅ Test passed: $message');
    } else {
      _addLogMessage('❌ Test failed: $message');
    }
  }

  void assertEqual(String message, dynamic expected, dynamic actual) async {
    if (expected is List && actual is List) {
      assertEqualLists(message, expected, actual);
    } else if (expected == actual) {
      _addLogMessage('✅ Test passed: $message');
    } else {
      _addLogMessage('❌ Test failed $message: expected $expected, got $actual');
    }
  }

  void assertEqualLists(String message, List expected, List actual) {
    final listEquality = ListEquality();
    if (listEquality.equals(expected, actual)) {
      _addLogMessage('✅ Test passed: $message');
    } else {
      if (expected.length != actual.length) {
        if (expected.length > actual.length) {
          final differentItems = expected.where((element) => !actual.contains(element));
          _addLogMessage('❌ Test failed $message: expected list length ${expected.length}, got ${actual.length}.  Expected items not received: $differentItems');
        } else {
          final differentItems = actual.where((element) => !expected.contains(element));
          _addLogMessage('❌ Test failed $message: expected list length ${expected.length}, got ${actual.length}.  Actual items not expected: $differentItems');
        }
      } else {
        _addLogMessage('❌ Test failed $message: expected $expected, got $actual');
      }
    }
  }

  void assertGreaterThan(
      String message, num expectedGreater, num expectedLower) {
    if (expectedGreater > expectedLower) {
      _addLogMessage('✅ Test passed: $message');
    } else {
      _addLogMessage(
          '❌ Test failed $message: expected $expectedGreater > $expectedLower');
    }
  }

  void assertAlmostEqual(String message, num expected, num actual, num delta) {
    if ((expected - actual).abs() <= delta) {
      _addLogMessage('✅ Test passed: $message');
    } else {
      _addLogMessage(
          '❌ Test failed $message: expected $expected, got $actual (delta: $delta)');
    }
  }

  void assertRaises(String message, Future Function() function) async {
    try {
      await function();
      _addLogMessage('❌ Test failed: $message');
    } catch (e) {
      _addLogMessage('✅ Test passed $message: $e');
    }
  }

  void _addLogMessage(String message) {
    print(message);
    setState(() {
      _logMessages.add(message);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    frame.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Column(
          children: [
            Center(
              child: Text('Running on: $_platformVersion\n'),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children:
                      _logMessages.map((message) => Text(message)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
