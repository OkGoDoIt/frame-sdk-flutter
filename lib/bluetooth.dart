import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _log = Logger("Bluetooth");

const _frameDataPrefix = 0x01;

/// Enum representing different types of frame data prefixes.
enum FrameDataTypePrefixes {
  longData(0x01),
  longDataEnd(0x02),
  wake(0x03),
  tap(0x04),
  micData(0x05),
  debugPrint(0x06),
  photoData(0x07),
  photoDataEnd(0x08),
  checkLength(0x09),
  longText(0x0A),
  longTextEnd(0x0B);

  const FrameDataTypePrefixes(this.value);
  final int value;
  String get valueAsHex => value.toRadixString(16).padLeft(2, '0');
}

/// Exception class for Brilliant Bluetooth errors.
class BrilliantBluetoothException implements Exception {
  final String msg;
  const BrilliantBluetoothException(this.msg);
  @override
  String toString() => 'BrilliantBluetoothException: $msg';
}

/// Enum representing the connection state of a Brilliant device.
enum BrilliantConnectionState {
  connected,
  dfuConnected,
  disconnected,
}

/// Class representing a scanned Brilliant device.
class BrilliantScannedDevice {
  BluetoothDevice device;
  int? rssi;

  BrilliantScannedDevice({
    required this.device,
    required this.rssi,
  });
}

/// Class representing a Brilliant device.
class BrilliantDevice {
  BluetoothDevice device;
  BrilliantConnectionState state;
  int? maxStringLength;
  int? maxDataLength;
  Duration defaultTimeout;
  bool logDebugging;

  int maxReceiveBuffer = 10 * 1024 * 1024;

  BluetoothCharacteristic? _txChannel;
  BluetoothCharacteristic? _rxChannel;
  BluetoothCharacteristic? _dfuControl;
  BluetoothCharacteristic? _dfuPacket;

  BrilliantDevice({
    required this.state,
    required this.device,
    this.maxStringLength,
    this.maxDataLength,
    this.defaultTimeout = const Duration(seconds: 30),
    this.logDebugging = false,
  });

  /// Checks if the device is connected.
  bool get isConnected => state == BrilliantConnectionState.connected;

  /// Returns the device ID.
  String get id => device.remoteId.toString();

  /// Stream of connection state changes for the device.
  Stream<BrilliantDevice> get connectionState {
    return FlutterBluePlus.events.onConnectionStateChanged
        .where((event) =>
            event.connectionState == BluetoothConnectionState.connected ||
            (event.connectionState == BluetoothConnectionState.disconnected &&
                event.device.disconnectReason!.code != 23789258))
        .asyncMap((event) async {
      if (event.connectionState == BluetoothConnectionState.connected) {
        _log.info("Connection state stream: Connected");
        try {
          return await BrilliantBluetooth._enableServices(event.device);
        } catch (error) {
          _log.warning("Connection state stream: Invalid due to $error");
          return Future.error(BrilliantBluetoothException(error.toString()));
        }
      }
      _log.info(
          "Connection state stream: Disconnected due to ${event.device.disconnectReason!.description}");
      if (Platform.isAndroid) {
        event.device.connect(timeout: const Duration(days: 365));
      }
      return BrilliantDevice(
        state: BrilliantConnectionState.disconnected,
        device: event.device,
      );
    });
  }

  /// Handles string response parts from the device.
  Stream<String> handleStringResponsePart(
      Stream<OnCharacteristicReceivedEvent> source) async* {
    Uint8List? ongoingPrintResponse;
    int? ongoingPrintResponseChunkCount;
    await for (final event in source) {
      if (event.value[0] == FrameDataTypePrefixes.longText.value) {
        // ongoing long text
        if (ongoingPrintResponse == null ||
            ongoingPrintResponseChunkCount == null) {
          ongoingPrintResponse = Uint8List(0);
          ongoingPrintResponseChunkCount = 0;
          _log.fine("Starting receiving new long printed string");
        }
        ongoingPrintResponse =
            Uint8List.fromList(ongoingPrintResponse + event.value.sublist(1));

        ongoingPrintResponseChunkCount++;
        final receivedString = utf8.decode(event.value.sublist(1));
        _log.finer(
            "Received long text chunk #$ongoingPrintResponseChunkCount: $receivedString");

        if (ongoingPrintResponse.length > maxReceiveBuffer) {
          _log.severe(
              "Buffered received long printed string is more than $maxReceiveBuffer bytes: ${ongoingPrintResponse.lengthInBytes} bytes received");
          throw BrilliantBluetoothException(
              "Buffered received long printed string is more than $maxReceiveBuffer bytes: ${ongoingPrintResponse.lengthInBytes} bytes received");
        }
      } else if (event.value[0] == FrameDataTypePrefixes.longTextEnd.value) {
        final totalExpectedChunkCount =
            int.parse(utf8.decode(event.value.sublist(1)));
        _log.finer(
            "Received final string chunk count: $totalExpectedChunkCount");
        if (ongoingPrintResponseChunkCount != totalExpectedChunkCount) {
          _log.warning(
              "Chunk count mismatch in long received string (expected $totalExpectedChunkCount, got $ongoingPrintResponseChunkCount)");
          throw BrilliantBluetoothException(
              "Chunk count mismatch in long received string (expected $totalExpectedChunkCount, got $ongoingPrintResponseChunkCount)");
        }
        final completePrintResponse = utf8.decode(ongoingPrintResponse!);
        ongoingPrintResponse = null;
        ongoingPrintResponseChunkCount = null;
        _log.info("Finished receiving long string: $completePrintResponse");
        yield completePrintResponse;
      } else {
        final receivedString = utf8.decode(event.value);
        if (receivedString.startsWith("+") || receivedString.startsWith(">")) {
          _log.fine("Received check string: $receivedString");
        } else {
          _log.info("Received string: $receivedString");
        }
        yield receivedString;
      }
    }
  }

  /// Handles data response parts from the device.
  Stream<Uint8List> handleDataResponsePart(
      Stream<OnCharacteristicReceivedEvent> source) async* {
    Uint8List? ongoingDataResponse;
    Uint8List? ongoingPhotoResponse;
    int? ongoingDataResponseChunkCount;
    int? ongoingPhotoResponseChunkCount;

    await for (final event in source) {
      if (event.value[0] == _frameDataPrefix &&
          event.value[1] == FrameDataTypePrefixes.longData.value) {
        // ongoing long data
        if (ongoingDataResponse == null ||
            ongoingDataResponseChunkCount == null) {
          ongoingDataResponse = Uint8List(0);
          ongoingDataResponseChunkCount = 0;
          _log.fine("Starting receiving new long data");
        }
        ongoingDataResponse =
            Uint8List.fromList(ongoingDataResponse + event.value.sublist(2));
        ongoingDataResponseChunkCount++;
        _log.finer(
            "Received long data chunk #$ongoingDataResponseChunkCount: ${event.value.sublist(2).length} bytes");
        if (ongoingDataResponse.length > maxReceiveBuffer) {
          _log.severe(
              "Buffered received long data is more than $maxReceiveBuffer bytes: ${ongoingDataResponse.length} bytes received");
          throw BrilliantBluetoothException(
              "Buffered received long data is more than $maxReceiveBuffer bytes: ${ongoingDataResponse.length} bytes received");
        }
      } else if (event.value[0] == _frameDataPrefix &&
          event.value[1] == FrameDataTypePrefixes.longDataEnd.value) {
        final totalExpectedChunkCount = event.value.length == 2
            ? 0
            : int.parse(utf8.decode(event.value.sublist(2)));
        _log.finer(
            "Received final long data chunk count: $totalExpectedChunkCount");
        if (ongoingDataResponseChunkCount != totalExpectedChunkCount) {
          _log.warning(
              "Chunk count mismatch in long received data (expected $totalExpectedChunkCount, got $ongoingDataResponseChunkCount)");
          throw BrilliantBluetoothException(
              "Chunk count mismatch in long received data (expected $totalExpectedChunkCount, got $ongoingDataResponseChunkCount)");
        }
        final completeDataResponse = ongoingDataResponse!;
        ongoingDataResponse = null;
        ongoingDataResponseChunkCount = null;
        _log.fine(
            "Finished receiving long data: ${completeDataResponse.length} bytes");
        yield completeDataResponse;
      } else if (event.value[0] == _frameDataPrefix &&
          event.value[1] == FrameDataTypePrefixes.photoData.value) {
        // ongoing photo
        if (ongoingPhotoResponse == null ||
            ongoingPhotoResponseChunkCount == null) {
          ongoingPhotoResponse = Uint8List(0);
          ongoingPhotoResponseChunkCount = 0;
          _log.fine("Starting receiving new photo");
        }
        ongoingPhotoResponse =
            Uint8List.fromList(ongoingPhotoResponse + event.value.sublist(2));
        ongoingPhotoResponseChunkCount++;
        _log.finer(
            "Received photo chunk #$ongoingPhotoResponseChunkCount: ${event.value.sublist(2).length} bytes");
        if (ongoingPhotoResponse.length > maxReceiveBuffer) {
          _log.severe(
              "Buffered received photo is more than $maxReceiveBuffer bytes: ${ongoingPhotoResponse.length} bytes received");
          throw BrilliantBluetoothException(
              "Buffered received photo is more than $maxReceiveBuffer bytes: ${ongoingPhotoResponse.length} bytes received");
        }
      } else if (event.value[0] == _frameDataPrefix &&
          event.value[1] == FrameDataTypePrefixes.photoDataEnd.value) {
        final totalExpectedChunkCount = event.value.length == 2
            ? 0
            : int.parse(utf8.decode(event.value.sublist(2)));
        _log.finer(
            "Received final photo chunk count: $totalExpectedChunkCount");
        if (ongoingPhotoResponseChunkCount != totalExpectedChunkCount) {
          _log.warning(
              "Chunk count mismatch in long received photo (expected $totalExpectedChunkCount, got $ongoingPhotoResponseChunkCount)");
          throw BrilliantBluetoothException(
              "Chunk count mismatch in long received photo (expected $totalExpectedChunkCount, got $ongoingPhotoResponseChunkCount)");
        }
        final completePhotoResponse = Uint8List.fromList(
            [FrameDataTypePrefixes.photoData.value, ...ongoingPhotoResponse!]);
        ongoingPhotoResponse = null;
        ongoingPhotoResponseChunkCount = null;
        _log.fine(
            "Finished receiving photo: ${completePhotoResponse.length} bytes");
        yield completePhotoResponse;
      } else if (event.value[0] == _frameDataPrefix) {
        _log.finer(
            "Received other single data: ${event.value.length - 1} bytes");

        yield Uint8List.fromList(event.value.sublist(1));
      }
    }
  }

  /// Stream of string responses from the device.
  Stream<String> get stringResponse {
    return handleStringResponsePart(FlutterBluePlus
        .events.onCharacteristicReceived
        .where((event) => event.value[0] != _frameDataPrefix));
  }

  /// Stream of data responses from the device.
  Stream<Uint8List> get dataResponse {
    return handleDataResponsePart(FlutterBluePlus
        .events.onCharacteristicReceived
        .where((event) => event.value[0] == _frameDataPrefix));
  }

  /// Gets data of a specific type from the device.
  Stream<Uint8List> getDataOfType(FrameDataTypePrefixes dataType) =>
      getDataWithPrefix(dataType.value);

  /// Gets data of a specific type from the device.
  Stream<Uint8List> getDataWithPrefix(int prefix) {
    return dataResponse
        .where((event) => event[0] == prefix)
        .map((event) => Uint8List.fromList(event.sublist(1)));
  }

  /// Disconnects the device.
  Future<void> disconnect() async {
    _log.info("Disconnecting");
    try {
      await device.disconnect();
    } catch (_) {}
  }

  /// Sends a break signal to the device.
  Future<void> sendBreakSignal() async {
    _log.info("Sending break signal");
    await sendString("\x03", awaitResponse: false);
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Sends a reset signal to the device.
  Future<void> sendResetSignal() async {
    _log.info("Sending reset signal");
    await sendString("\x04", awaitResponse: false);
    await Future.delayed(const Duration(milliseconds: 200));
  }

  /// Sends a string to the device.
  Future<String?> sendString(
    String string, {
    bool awaitResponse = false,
    Duration? timeout,
  }) async {
    try {
      final controlChar = string.length == 1 && string.codeUnitAt(0) < 10
          ? string.codeUnitAt(0)
          : null;
      if (controlChar != null && !awaitResponse) {
        _log.info("Sending control character: $controlChar");
        await _txChannel!
            .write(Uint8List.fromList([controlChar]), withoutResponse: true);
        _log.finer("Sent control character: $controlChar");
        return null;
      } else {
        _log.info("Sending string: $string");
      }

      if (state != BrilliantConnectionState.connected) {
        throw ("Device is not connected");
      }

      if (string.length > maxStringLength!) {
        throw ("Payload exceeds allowed length of $maxStringLength");
      }

      await _txChannel!.write(utf8.encode(string));

      _log.finer("Sent string: $string");

      if (!awaitResponse) {
        return null;
      }

      final response =
          await stringResponse.timeout(timeout ?? defaultTimeout).first;

      return response;
    } catch (error) {
      _log.warning("Couldn't send string. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Waits for a specific string from the device.
  Future<String> waitForString({String? match, Duration? timeout}) async {
    StreamSubscription<String>? subscription;
    Completer<String> completer = Completer();
    try {
      if (match != null) {
        subscription = stringResponse
            .where((event) => event.trim() == match.trim())
            .timeout(timeout ?? defaultTimeout)
            .listen((event) {
          subscription?.cancel();
          _log.fine("Received the $match string we were waiting for");
          completer.complete(event);
        }, onError: (error) {
          _log.warning("Error waiting for string $match: $error");
          completer.completeError(error);
        });
      } else {
        subscription =
            stringResponse.timeout(timeout ?? defaultTimeout).listen((event) {
          _log.fine("Received a string we were waiting for: $event");
          completer.complete(event);
        }, onError: (error) {
          _log.warning("Error waiting for string: $error");
          completer.completeError(error);
        });
      }
    } on TimeoutException {
      _log.warning("Timeout while waiting for string.");
      if (subscription != null) {
        subscription.cancel();
      }
      if (!completer.isCompleted) {
        completer.completeError(const BrilliantBluetoothException(
            "Timeout while waiting for string"));
      }
    }
    return completer.future;
  }

  /// Sends data to the device.
  Future<Uint8List?> sendData(Uint8List data,
      {bool awaitResponse = false, Duration? timeout}) async {
    try {
      _log.info("Sending ${data.length} bytes of plain data");
      _log.fine(data);

      if (state != BrilliantConnectionState.connected) {
        throw ("Device is not connected");
      }

      if (data.length > maxDataLength!) {
        throw ("Payload exceeds allowed length of $maxDataLength");
      }

      var finalData = data.toList()..insert(0, _frameDataPrefix);

      await _txChannel!.write(finalData, withoutResponse: true);

      if (!awaitResponse) {
        return null;
      }

      return await waitForData(timeout: timeout);
    } catch (error) {
      _log.warning("Couldn't send data. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Waits for data of a specific type from the device.
  Future<Uint8List> waitForDataOfType(FrameDataTypePrefixes dataType,
      {Duration? timeout}) async {
    StreamSubscription<Uint8List>? subscription;
    Completer<Uint8List> completer = Completer();
    _log.fine("Waiting for data of type ${dataType.name}");
    try {
      subscription = dataResponse
          .where((event) => event[0] == dataType.value)
          .timeout(timeout ?? defaultTimeout)
          .listen((event) {
        _log.fine(
            "Received data of type ${dataType.name}: ${event.length} bytes");
        subscription?.cancel();
        completer.complete(event.sublist(1));
      });
    } on TimeoutException {
      _log.warning("Timeout while waiting for data of type ${dataType.name}");
      if (subscription != null) {
        subscription.cancel();
      }
      if (!completer.isCompleted) {
        completer.completeError(BrilliantBluetoothException(
            "Timeout while waiting for data of type ${dataType.name}"));
      }
      return Future.error(BrilliantBluetoothException(
          "Timeout while waiting for data of type ${dataType.name}"));
    }
    return completer.future;
  }

  /// Waits for any data from the device.
  Future<Uint8List> waitForData({Duration? timeout}) async {
    StreamSubscription<Uint8List>? subscription;
    Completer<Uint8List> completer = Completer();
    _log.fine("Waiting for any data");
    try {
      subscription =
          dataResponse.timeout(timeout ?? defaultTimeout).listen((event) {
        _log.fine("Received misc data: ${event.length} bytes");
        subscription?.cancel();
        completer.complete(event);
      });
    } on TimeoutException {
      _log.warning("Timeout while waiting for data.");
      if (subscription != null) {
        subscription.cancel();
      }
      if (!completer.isCompleted) {
        completer.completeError(const BrilliantBluetoothException(
            "Timeout while waiting for data"));
      }
      return Future.error(
          const BrilliantBluetoothException("Timeout while waiting for data"));
    }
    return completer.future;
  }

  /// Uploads a script to the device.
  Future<void> uploadScript(String fileName, String filePath) async {
    try {
      _log.info("Uploading script: $fileName");

      String file = await rootBundle.loadString(filePath);

      file = file.replaceAll('\\', '\\\\');
      file = file.replaceAll("\n", "\\n");
      file = file.replaceAll("'", "\\'");
      file = file.replaceAll('"', '\\"');

      var resp =
          await sendString("f=frame.file.open('$fileName', 'w');print('\x02')");

      if (resp != "\x02") {
        throw ("Error opening file: $resp");
      }

      int index = 0;
      int chunkSize = maxStringLength! - 22;

      while (index < file.length) {
        // Don't go over the end of the string
        if (index + chunkSize > file.length) {
          chunkSize = file.length - index;
        }

        // Don't split on an escape character
        if (file[index + chunkSize - 1] == '\\') {
          chunkSize -= 1;
        }

        String chunk = file.substring(index, index + chunkSize);

        resp = await sendString("f:write('$chunk');print('\x02')");

        if (resp != "\x02") {
          throw ("Error writing file: $resp");
        }

        index += chunkSize;
      }

      resp = await sendString("f:close();print('\x02')");

      if (resp != "\x02") {
        throw ("Error closing file: $resp");
      }
    } catch (error) {
      _log.warning("Couldn't upload script. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Updates the firmware of the device.
  Stream<double> updateFirmware(String filePath) async* {
    try {
      yield 0;

      _log.info("Starting firmware update");

      if (state != BrilliantConnectionState.dfuConnected) {
        throw ("DFU device is not connected");
      }

      if (_dfuControl == null || _dfuPacket == null) {
        throw ("Device is not in DFU mode");
      }

      final updateZipFile = await rootBundle.load(filePath);
      final zip = ZipDecoder().decodeBytes(updateZipFile.buffer.asUint8List());

      final initFile = zip.firstWhere((file) => file.name.endsWith(".dat"));
      final imageFile = zip.firstWhere((file) => file.name.endsWith(".bin"));

      await for (var _ in _transferDfuFile(initFile.content, true)) {}
      await Future.delayed(const Duration(milliseconds: 500));
      await for (var value in _transferDfuFile(imageFile.content, false)) {
        yield value;
      }

      _log.info("Firmware update completed");
    } catch (error) {
      _log.warning("Couldn't complete firmware update. $error");
      yield* Stream.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Transfers a DFU file to the device.
  Stream<double> _transferDfuFile(Uint8List file, bool isInitFile) async* {
    Uint8List response;

    try {
      if (isInitFile) {
        _log.fine("Uploading DFU init file. Size: ${file.length}");
        response = await _dfuSendControlData(Uint8List.fromList([0x06, 0x01]));
      } else {
        _log.fine("Uploading DFU image file. Size: ${file.length}");
        response = await _dfuSendControlData(Uint8List.fromList([0x06, 0x02]));
      }
    } catch (_) {
      throw ("Couldn't create DFU file on device");
    }

    final maxSize = ByteData.view(response.buffer).getUint32(3, Endian.little);
    var offset = ByteData.view(response.buffer).getUint32(7, Endian.little);
    final crc = ByteData.view(response.buffer).getUint32(11, Endian.little);

    _log.fine("Received allowed size: $maxSize, offset: $offset, CRC: $crc");

    while (offset < file.length) {
      final chunkSize = min(maxSize, file.length - offset);
      final chunkCrc = getCrc32(file.sublist(0, offset + chunkSize));

      // Create command with size
      final chunkSizeAsBytes = [
        chunkSize & 0xFF,
        chunkSize >> 8 & 0xFF,
        chunkSize >> 16 & 0xff,
        chunkSize >> 24 & 0xff
      ];

      try {
        if (isInitFile) {
          await _dfuSendControlData(
              Uint8List.fromList([0x01, 0x01, ...chunkSizeAsBytes]));
        } else {
          await _dfuSendControlData(
              Uint8List.fromList([0x01, 0x02, ...chunkSizeAsBytes]));
        }
      } catch (_) {
        throw ("Couldn't issue DFU create command");
      }

      // Split chunk into packets of MTU size
      final packetSize = device.mtuNow - 3;
      final packets = (chunkSize / packetSize).ceil();

      for (var p = 0; p < packets; p++) {
        final fileStart = offset + p * packetSize;
        var fileEnd = fileStart + packetSize;

        // The last packet could be smaller
        if (fileEnd - offset > maxSize) {
          fileEnd -= fileEnd - offset - maxSize;
        }

        // The last part of the file could also be smaller
        if (fileEnd > file.length) {
          fileEnd = file.length;
        }

        final fileSlice = file.sublist(fileStart, fileEnd);

        final percentDone = (100 / file.length) * offset;
        yield percentDone;

        _log.fine(
            "Sending ${fileSlice.length} bytes of packet data. ${percentDone.toInt()}% Complete");

        await _dfuSendPacketData(fileSlice)
            .onError((_, __) => throw ("Couldn't send DFU data"));
      }

      // Calculate CRC
      try {
        response = await _dfuSendControlData(Uint8List.fromList([0x03]));
      } catch (_) {
        throw ("Couldn't get CRC from device");
      }
      offset = ByteData.view(response.buffer).getUint32(3, Endian.little);
      final returnedCrc =
          ByteData.view(response.buffer).getUint32(7, Endian.little);

      if (returnedCrc != chunkCrc) {
        throw ("CRC mismatch after sending this chunk");
      }

      // Execute command (The last command may disconnect which is normal)
      try {
        response = await _dfuSendControlData(Uint8List.fromList([0x04]));
      } catch (_) {}
    }

    _log.fine("DFU file sent");
  }

  /// Sends control data for DFU.
  Future<Uint8List> _dfuSendControlData(Uint8List data) async {
    try {
      _log.fine("Sending ${data.length} bytes of DFU control data: $data");

      _dfuControl!.write(data, timeout: 1);

      final response = await _dfuControl!.onValueReceived
          .timeout(const Duration(seconds: 1))
          .first;

      return Uint8List.fromList(response);
    } catch (error) {
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Sends packet data for DFU.
  Future<void> _dfuSendPacketData(Uint8List data) async {
    await _dfuPacket!.write(data, withoutResponse: true);
  }
}

class BrilliantBluetooth {
  static final Guid _serviceUUID = Guid("7a230001-5475-a6a4-654c-8431f6ad49c4");
  static final Guid _txCharacteristicUUID =
      Guid("7a230002-5475-a6a4-654c-8431f6ad49c4");
  static final Guid _rxCharacteristicUUID =
      Guid("7a230003-5475-a6a4-654c-8431f6ad49c4");
  static const _allowedDeviceNames = ["Frame", "Frame Update", "DFUTarg"];

  /// Gets the nearest Frame device.
  static Future<BrilliantDevice> getNearestFrame() async {
    await FlutterBluePlus.stopScan();
    //await FlutterBluePlus.startScan();
    await FlutterBluePlus.startScan(withServices: [_serviceUUID]);

    final Completer<List<ScanResult>> completer = Completer();
    final subscription = FlutterBluePlus.scanResults.listen((results) {
      if (results.isNotEmpty) {
        final filteredList = results
            .where((d) =>
                d.advertisementData.serviceUuids.contains(_serviceUUID) &&
                _allowedDeviceNames.any((name) => d.advertisementData.advName.startsWith(name)))
            .toList();
        if (filteredList.isNotEmpty) {
          completer.complete(filteredList);
        }
      }
    });

    final devices = await completer.future;
    await subscription.cancel();
    FlutterBluePlus.stopScan();

    devices.sort((a, b) => b.rssi.compareTo(a.rssi));

    if (devices.isEmpty) {
      throw const BrilliantBluetoothException("No Frame devices found");
    }

    final device = BrilliantScannedDevice(
      device: devices.first.device,
      rssi: devices.first.rssi,
    );

    return connect(device);
  }

  /// Requests Bluetooth permission.
  static Future<void> requestPermission() async {
    try {
      await FlutterBluePlus.startScan();
      await FlutterBluePlus.stopScan();
    } catch (error) {
      _log.warning("Couldn't obtain Bluetooth permission. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Scans for devices.
  static Stream<BrilliantScannedDevice> scan() async* {
    try {
      _log.info("Starting to scan for devices");

      await FlutterBluePlus.startScan(
        withServices: [
          _serviceUUID,
          Guid('fe59'),
        ],
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 2),
      );
    } catch (error) {
      _log.warning("Scanning failed. $error");
      throw BrilliantBluetoothException(error.toString());
    }

    yield* FlutterBluePlus.scanResults
        .where((results) => results.isNotEmpty)
        // TODO filter by name: "Frame", "Frame Update", "Monocle" & "DFUTarg"
        .map((results) {
      ScanResult nearestDevice = results[0];
      for (int i = 0; i < results.length; i++) {
        if (results[i].rssi > nearestDevice.rssi) {
          nearestDevice = results[i];
        }
      }

      _log.fine(
          "Found ${nearestDevice.device.advName} rssi: ${nearestDevice.rssi}");

      return BrilliantScannedDevice(
        device: nearestDevice.device,
        rssi: nearestDevice.rssi,
      );
    });
  }

  /// Stops scanning for devices.
  static Future<void> stopScan() async {
    try {
      _log.info("Stopping scan for devices");
      await FlutterBluePlus.stopScan();
    } catch (error) {
      _log.warning("Couldn't stop scanning. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Connects to a scanned device.
  static Future<BrilliantDevice> connect(BrilliantScannedDevice scanned) async {
    try {
      _log.info("Connecting");

      await FlutterBluePlus.stopScan();

      await scanned.device.connect(
        autoConnect: Platform.isIOS ? true : false,
        mtu: null,
      );

      final connectionState = await scanned.device.connectionState
          .firstWhere((event) => event == BluetoothConnectionState.connected)
          .timeout(const Duration(seconds: 3));

      if (connectionState == BluetoothConnectionState.connected) {
        if (Platform.isAndroid) await scanned.device.requestMtu(512);
        return await _enableServices(scanned.device);
      }

      throw ("${scanned.device.disconnectReason?.description}");
    } catch (error) {
      await scanned.device.disconnect();
      _log.warning("Couldn't connect. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Reconnects to a device by UUID.
  static Future<BrilliantDevice> reconnect(String uuid) async {
    try {
      _log.info("Will re-connect to device: $uuid once found");

      BluetoothDevice device = BluetoothDevice.fromId(uuid);

      await device.connect(
        timeout: const Duration(days: 365),
        autoConnect: Platform.isIOS ? true : false,
        mtu: null,
      ); // TODO Should wait but it throws an error on Android after some time

      final connectionState = await device.connectionState.firstWhere((state) =>
          state == BluetoothConnectionState.connected ||
          (state == BluetoothConnectionState.disconnected &&
              device.disconnectReason != null));

      _log.info("Found reconnectable device: $uuid");

      if (connectionState == BluetoothConnectionState.connected) {
        if (Platform.isAndroid) await device.requestMtu(512);
        return await _enableServices(device);
      }

      throw ("${device.disconnectReason?.description}");
    } catch (error) {
      _log.warning("Couldn't reconnect. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  /// Enables services on the device.
  static Future<BrilliantDevice> _enableServices(BluetoothDevice device) async {
    if (Platform.isAndroid) {
      await device.requestMtu(512);
    }

    BrilliantDevice finalDevice = BrilliantDevice(
      device: device,
      state: BrilliantConnectionState.disconnected,
    );

    List<BluetoothService> services = await device.discoverServices();

    for (var service in services) {
      // If Frame
      if (service.serviceUuid == _serviceUUID) {
        _log.fine("Found Frame service");
        for (var characteristic in service.characteristics) {
          if (characteristic.characteristicUuid == _txCharacteristicUUID) {
            _log.fine("Found Frame TX characteristic");
            finalDevice._txChannel = characteristic;
          }
          if (characteristic.characteristicUuid == _rxCharacteristicUUID) {
            _log.fine("Found Frame RX characteristic");
            finalDevice._rxChannel = characteristic;

            await characteristic.setNotifyValue(true);
            _log.fine("Enabled RX notifications");

            finalDevice.maxStringLength = device.mtuNow - 3;
            finalDevice.maxDataLength = device.mtuNow - 4;
            _log.fine("Max string length: ${finalDevice.maxStringLength}");
            _log.fine("Max data length: ${finalDevice.maxDataLength}");
          }
        }
      }

      // If DFU
      if (service.serviceUuid == Guid('fe59')) {
        _log.fine("Found DFU service");
        for (var characteristic in service.characteristics) {
          if (characteristic.characteristicUuid ==
              Guid('8ec90001-f315-4f60-9fb8-838830daea50')) {
            _log.fine("Found DFU control characteristic");
            finalDevice._dfuControl = characteristic;
            await characteristic.setNotifyValue(true);
            _log.fine("Enabled DFU control notifications");
          }
          if (characteristic.characteristicUuid ==
              Guid('8ec90002-f315-4f60-9fb8-838830daea50')) {
            _log.fine("Found DFU packet characteristic");
            finalDevice._dfuPacket = characteristic;
          }
        }
      }
    }

    if (finalDevice._txChannel != null && finalDevice._rxChannel != null) {
      finalDevice.state = BrilliantConnectionState.connected;
      return finalDevice;
    }

    if (finalDevice._dfuControl != null && finalDevice._dfuPacket != null) {
      finalDevice.state = BrilliantConnectionState.dfuConnected;
      return finalDevice;
    }

    throw ("Incomplete set of services found");
  }
}