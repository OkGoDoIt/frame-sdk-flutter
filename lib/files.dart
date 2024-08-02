import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart';

import 'frame_sdk.dart';

class Files {
  final Frame frame;
  final logger = Logger('Files');

  Files(this.frame);

  Future<void> writeFile(String path, dynamic data,
      {bool checked = false}) async {
    if (data is String) {
      data = utf8.encode(data);
    } else if (data is! Uint8List) {
      throw ArgumentError('Data must be either a String or Uint8List');
    }
    await _writeFileRawBytes(path, data as Uint8List, checked: checked);
  }

  Future<void> _writeFileRawBytes(String path, Uint8List data,
      {bool checked = false}) async {
    await frame.runLua(
      'w=frame.file.open("$path","write")',
      checked: checked,
      withoutHelpers: true,
    );

    await frame.runLua(
      'frame.bluetooth.receive_callback((function(d)w:write(d)end))',
      checked: checked,
      withoutHelpers: true,
    );

    int currentIndex = 0;
    while (currentIndex < data.length) {
      final int maxPayload = (frame.bluetooth.maxDataLength ?? 0) - 2;
      final int nextChunkLength = data.length - currentIndex > maxPayload
          ? maxPayload
          : data.length - currentIndex;
      if (nextChunkLength == 0) break;

      if (nextChunkLength <= 0) {
        logger.warning(
            "MTU too small to write file, or escape character at end of chunk");
        throw Exception(
            "MTU too small to write file, or escape character at end of chunk");
      }

      await frame.bluetooth
          .sendData(data.sublist(currentIndex, currentIndex + nextChunkLength));

      currentIndex += nextChunkLength;
      if (currentIndex < data.length) {
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }

    await frame.runLua(
      'w:close()',
      checked: checked,
      withoutHelpers: true,
    );

    await frame.runLua(
      'frame.bluetooth.receive_callback(nil)',
      checked: checked,
      withoutHelpers: true,
    );
  }

  Future<bool> fileExists(String path) async {
    final String? response = await frame.bluetooth.sendString(
      'r=frame.file.open("$path","read");print("o");r:close()',
      awaitResponse: true,
    );
    return response == "o";
  }

  Future<bool> deleteFile(String path) async {
    final String? response = await frame.bluetooth.sendString(
      'frame.file.remove("$path");print("d")',
      awaitResponse: true,
    );
    return response == "d";
  }

  Future<Uint8List> readFile(String path) async {
    frame.bluetooth.sendString('printCompleteFile("$path")');
    final Uint8List result = await frame.bluetooth.waitForData();
    // remove any trailing newlines if there are any
    final lengthToRemove = result.lastIndexOf(10);
    if (lengthToRemove != -1) {
      return result.sublist(0, lengthToRemove);
    }
    return result;
  }
}
