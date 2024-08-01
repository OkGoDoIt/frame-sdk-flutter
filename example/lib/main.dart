import 'dart:convert';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:frame_sdk/frame_sdk.dart';
import 'package:frame_sdk/bluetooth.dart';

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

  @override
  void initState() {
    super.initState();
    initPlatformState();
    frame = Frame();

    runExample();
  }

  Future<void> runExample() async {
    await frame.ensureConnected();
    assertTrue('Connected to device', frame.bluetooth.isConnected);
    assertEqual(
        "Send lua with response",
        "hi",
        await frame.bluetooth.sendString("print('hi')", awaitResponse: true) ??
            "");
    assertEqual("Send lua without response", null,
        await frame.bluetooth.sendString("tester = 1"));

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
        "send data without response",
        null,
        await frame.bluetooth
            .sendData(Uint8List.fromList(utf8.encode("test"))));

    await frame.bluetooth.sendString("frame.bluetooth.receive_callback(nil)");
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
    if (expected == actual) {
      _addLogMessage('✅ Test passed: $message');
    } else {
      _addLogMessage('❌ Test failed $message: expected $expected, got $actual');
    }
  }

  void assertRaises(String message, Function function) async {
    try {
      function();
      _addLogMessage('❌ Test failed: $message');
    } catch (e) {
      _addLogMessage('✅ Test passed $message: $e');
    }
  }

  void _addLogMessage(String message) {
    setState(() {
      _logMessages.add(message);
    });
  }

  @override
  void dispose() async {
    await frame.disconnect();
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
              child: ListView.builder(
                itemCount: _logMessages.length,
                itemBuilder: (context, index) {
                  return Text(_logMessages[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
