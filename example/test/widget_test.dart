import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'dart:typed_data';

import 'package:frame_sdk/frame_sdk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Bluetooth Tests', () {
    Frame frame = Frame();

    setUp(() {});

    test('connect and disconnect', () async {
      expect(frame.isConnected, false);

      await frame.connect();
      expect(frame.isConnected, true);

      await frame.disconnect();
      expect(frame.isConnected, false);

      await frame.ensureConnected();
      expect(frame.isConnected, true);

      await frame.disconnect();
      expect(frame.isConnected, false);
    });

    test('send Lua', () async {
      await frame.ensureConnected();
      expect(
          await frame.bluetooth.sendString("print('hi')", awaitResponse: true),
          "hi");
      expect(await frame.bluetooth.sendString("print('hi')"), null);
    });

    test('send data', () async {
      await frame.ensureConnected();
      expect(
          await frame.bluetooth
              .sendData(Uint8List.fromList([1, 2, 3]), awaitResponse: true),
          Uint8List.fromList([1, 2, 3]));
      expect(
          await frame.bluetooth.sendData(Uint8List.fromList([1, 2, 3])), null);
    });

    test('MTU', () async {
      await frame.ensureConnected();
      expect(frame.bluetooth.maxStringLength, greaterThan(0));
      expect(frame.bluetooth.maxDataLength, greaterThan(0));
      expect(frame.bluetooth.maxStringLength,
          (frame.bluetooth.maxDataLength ?? 0) + 1);
    });
  });
}
