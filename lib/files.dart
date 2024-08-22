import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart';

import 'frame_sdk.dart';

/// A class to handle file operations on the Frame device.
class Files {
  final Frame frame;
  final logger = Logger('Files');

  Files(this.frame);

  /// Writes data to a file on the Frame device.
  ///
  /// Args:
  ///   path (String): The full filename to write on the Frame.
  ///   data (dynamic): The data to write to the file. Must be either a String or Uint8List.
  ///   checked (bool, optional): If true, each step of writing will wait for acknowledgement from the Frame before continuing. Defaults to false.
  ///
  /// Throws:
  ///   ArgumentError: If the data is not a String or Uint8List.
  Future<void> writeFile(String path, dynamic data,
      {bool checked = false}) async {
    if (data is String) {
      data = utf8.encode(data);
    } else if (data is! Uint8List) {
      throw ArgumentError('Data must be either a String or Uint8List');
    }
    await _writeFileRawBytes(path, data as Uint8List, checked: checked);
  }

  /// Writes raw bytes to a file on the Frame device.
  ///
  /// Args:
  ///   path (String): The full filename to write on the Frame.
  ///   data (Uint8List): The data to write to the file as bytes.
  ///   checked (bool, optional): If true, each step of writing will wait for acknowledgement from the Frame before continuing. Defaults to false.
  ///
  /// Throws:
  ///   Exception: If the file cannot be opened, written to, or closed.
  Future<void> _writeFileRawBytes(String path, Uint8List data,
      {bool checked = false}) async {
    await frame.runLua(
      'w=frame.file.open("$path","write")',
      checked: checked,
      withoutHelpers: true,
    );

    await frame.runLua(
      'frame.bluetooth.receive_callback((function(d)if d[1]==2 then w:write(d.sublist(2))end;end))',
      checked: checked,
      withoutHelpers: true,
    );

    int currentIndex = 0;
    while (currentIndex < data.length) {
      final int maxPayload = (frame.bluetooth.maxDataLength ?? 0) - 3;
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

      await frame.bluetooth.sendData(
          Uint8List.fromList([2] + data.sublist(currentIndex, currentIndex + nextChunkLength)));

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

  /// Checks if a file exists on the Frame device.
  ///
  /// Args:
  ///   path (String): The full path to the file to check.
  ///
  /// Returns:
  ///   Future<bool>: True if the file exists, false otherwise.
  Future<bool> fileExists(String path) async {
    final String? response = await frame.bluetooth.sendString(
      'r=frame.file.open("$path","read");print("o");r:close()',
      awaitResponse: true,
    );
    return response == "o";
  }

  /// Deletes a file on the Frame device.
  ///
  /// Args:
  ///   path (String): The full path to the file to delete.
  ///
  /// Returns:
  ///   Future<bool>: True if the file was deleted, false if it didn't exist or failed to delete.
  Future<bool> deleteFile(String path) async {
    final String? response = await frame.bluetooth.sendString(
      'frame.file.remove("$path");print("d")',
      awaitResponse: true,
    );
    return response == "d";
  }

  /// Reads a file from the Frame device.
  ///
  /// Args:
  ///   path (String): The full filename to read on the Frame.
  ///
  /// Returns:
  ///   Future<Uint8List>: The content of the file as bytes.
  ///
  /// Raises:
  ///   Exception: If the file does not exist.
  Future<Uint8List> readFile(String path) async {
    if (!frame.useLibrary) {
      throw Exception("Cannot read file via SDK without library helpers");
    }
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