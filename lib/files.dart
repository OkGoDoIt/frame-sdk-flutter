import 'dart:convert';
import 'dart:typed_data';
import 'frame_sdk.dart';

class Files {
  final Frame frame;

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
    final String? openResponse = await frame.bluetooth.sendString(
      'w=frame.file.open("$path","write")${checked ? ';print("o")' : ''}',
      awaitResponse: checked,
    );
    if (checked && openResponse != "o") {
      throw Exception('Couldn\'t open file "$path" for writing: $openResponse');
    }

    final String? callbackResponse = await frame.bluetooth.sendString(
      'frame.bluetooth.receive_callback((function(d)w:write(d)end))${checked ? ';print("c")' : ''}',
      awaitResponse: checked,
    );
    if (checked && callbackResponse != "c") {
      throw Exception(
          'Couldn\'t register callback for writing to file "$path": $callbackResponse');
    }

    int currentIndex = 0;
    while (currentIndex < data.length) {
      final int maxPayload = (frame.bluetooth.maxDataLength ?? 0) - 1;
      final int nextChunkLength = data.length - currentIndex > maxPayload
          ? maxPayload
          : data.length - currentIndex;
      if (nextChunkLength == 0) break;

      if (nextChunkLength <= 0) {
        throw Exception(
            "MTU too small to write file, or escape character at end of chunk");
      }

      final Uint8List chunk =
          data.sublist(currentIndex, currentIndex + nextChunkLength);
      await frame.bluetooth.sendData(chunk);

      currentIndex += nextChunkLength;
      if (currentIndex < data.length) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    final String? closeResponse = await frame.bluetooth.sendString(
      'w:close();print("c")',
      awaitResponse: checked,
    );
    if (checked && closeResponse != "c") {
      throw Exception("Error closing file");
    }

    final String? removeCallbackResponse = await frame.bluetooth.sendString(
      'frame.bluetooth.receive_callback(nil)${checked ? ';print("c")' : ''}',
      awaitResponse: checked,
    );
    if (checked && removeCallbackResponse != "c") {
      throw Exception('Couldn\'t remove callback for writing to file "$path"');
    }
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
    await frame.bluetooth.sendString('printCompleteFile("$path")');
    final Uint8List result = await frame.bluetooth.waitForData();
    // remove trailing newline if there is one
    return result.isNotEmpty
        ? result.sublist(0, result.length - (result.last == 10 ? 1 : 0))
        : result;
  }
}
