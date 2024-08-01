import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:frame_sdk/bluetooth.dart';
import 'package:frame_sdk/frame_sdk.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

class Microphone {
  final Frame frame;
  final Logger logger = Logger('Microphone');
  late Uint8List _audioBuffer = Uint8List(0);
  int _bitDepth = 16;
  int _sampleRate = 8000;
  double _silenceThreshold = 0.02;
  final Completer<void> _audioFinishedCompleter = Completer<void>();
  double _lastSoundTime = 0;
  double _noiseFloor = 0;

  Microphone(this.frame);

  double get silenceThreshold => _silenceThreshold;

  set silenceThreshold(double value) {
    _silenceThreshold = value;
  }

  int get bitDepth => _bitDepth;

  set bitDepth(int value) {
    if (value != 8 && value != 16) {
      throw ArgumentError('Bit depth must be 8 or 16');
    }
    _bitDepth = value;
  }

  int get sampleRate => _sampleRate;

  set sampleRate(int value) {
    if (value != 8000 && value != 16000) {
      throw ArgumentError('Sample rate must be 8000 or 16000');
    }
    _sampleRate = value;
  }

  Future<Uint8List> recordAudio({
    int? silenceCutoffLengthInSeconds = 3,
    int maxLengthInSeconds = 30,
  }) async {
    await frame.runLua('frame.microphone.stop()', checked: false);

    _audioBuffer = Uint8List(0);
    StreamSubscription<Uint8List> subscription = frame.bluetooth
        .getDataOfType(FrameDataTypePrefixes.micData)
        .listen(_audioBufferHandler);

    _lastSoundTime = DateTime.now().millisecondsSinceEpoch / 1000;

    logger.info('Starting audio recording at $_sampleRate Hz, $_bitDepth-bit');
    await frame.runLua(
      'microphoneRecordAndSend($_sampleRate,$_bitDepth,nil)',
    );

    bool didTimeout = false;

    await _audioFinishedCompleter.future.timeout(
      Duration(seconds: maxLengthInSeconds),
      onTimeout: () {
        didTimeout = true;
      },
    );
    subscription.cancel();
    
    if (!didTimeout) {
      final trimLength = (silenceCutoffLengthInSeconds! - 0.5) * _sampleRate;
      if (_audioBuffer.length > trimLength) {
        _audioBuffer =
            _audioBuffer.sublist(0, _audioBuffer.length - trimLength.toInt());
      }
    }
    await frame.runLua('frame.microphone.stop()');

    logger.info(
        'Audio recording finished with ${_audioBuffer.length / _sampleRate} seconds of audio');

    return _audioBuffer;
  }

  Future<double> saveAudioFile(
    String filename, {
    int silenceCutoffLengthInSeconds = 3,
    int maxLengthInSeconds = 30,
  }) async {
    final audioData = await recordAudio(
      silenceCutoffLengthInSeconds: silenceCutoffLengthInSeconds,
      maxLengthInSeconds: maxLengthInSeconds,
    );

    if (audioData.isEmpty) {
      throw ArgumentError('No audio data recorded');
    }

    final file = File(filename);
    await file.writeAsBytes(_bytesToWav(audioData, bitDepth, sampleRate));

    final lengthInSeconds = audioData.length / sampleRate;
    return lengthInSeconds;
  }

  void _audioBufferHandler(Uint8List data) {
    if (_audioBuffer.isEmpty) return;

    final audioData = _convertBytesToAudioData(data, _bitDepth);
    _audioBuffer = Uint8List.fromList([..._audioBuffer, ...data]);

    final minAmplitude = audioData.reduce((a, b) => a < b ? a : b);
    final maxAmplitude = audioData.reduce((a, b) => a > b ? a : b);
    final delta = maxAmplitude - minAmplitude;

    final normalizedDelta = _bitDepth == 8 ? delta / 128.0 : delta / 32768.0;

    _noiseFloor += (normalizedDelta - _noiseFloor) * 0.1;

    if (normalizedDelta - _noiseFloor > _silenceThreshold) {
      _lastSoundTime = DateTime.now().millisecondsSinceEpoch / 1000;
      logger.info('+');
    } else {
      if (DateTime.now().millisecondsSinceEpoch / 1000 - _lastSoundTime >
          _silenceThreshold) {
        _audioFinishedCompleter.complete();
      } else {
        logger.info('-');
      }
    }
  }

  List<int> _convertBytesToAudioData(Uint8List audioBuffer, int bitDepth) {
    if (bitDepth == 16) {
      return audioBuffer.buffer.asUint16List().toList();
    } else if (bitDepth == 8) {
      return audioBuffer.toList();
    } else {
      throw ArgumentError('Unsupported bit depth');
    }
  }

  Future<void> playAudio(Uint8List audioData,
      {int? sampleRate, int? bitDepth}) async {
    final tempDir = await getTemporaryDirectory();
    File file = await File('${tempDir.path}/audio.wav').create();
    file.writeAsBytesSync(_bytesToWav(
        audioData, bitDepth ?? _bitDepth, sampleRate ?? _sampleRate));

    try {
      AudioPlayer player = AudioPlayer(handleAudioSessionActivation: false);
      await player.setAudioSource(AudioSource.file(file.path));
      await player.play();
      await player.dispose();
    } catch (error) {
      logger.warning("Error playing audio. $error");
    }
  }

  Uint8List _bytesToWav(Uint8List pcmBytes, int bitDepth, int sampleRate) {
    final output = BytesBuilder();
    try {
      output.add(utf8.encode('RIFF'));
      output.add(_uint32to8(36 + pcmBytes.length));
      output.add(utf8.encode('WAVE'));
      output.add(utf8.encode('fmt '));
      output.add(_uint32to8(16));
      output.add(_uint16to8(1));
      output.add(_uint16to8(1));
      output.add(_uint32to8(sampleRate));
      output.add(_uint32to8((sampleRate * bitDepth) ~/ 8));
      output.add(_uint16to8(bitDepth ~/ 8));
      output.add(_uint16to8(bitDepth));
      output.add(utf8.encode('data'));
      output.add(_uint32to8(pcmBytes.length));
      output.add(_offsetPcm(pcmBytes.buffer.asUint8List()));
    } catch (error) {
      logger.warning("Could not build audio file: $error");
    }
    return output.toBytes();
  }

  Uint8List _uint32to8(int value) =>
      Uint8List(4)..buffer.asUint32List()[0] = value;

  Uint8List _uint16to8(int value) =>
      Uint8List(2)..buffer.asUint16List()[0] = value;

  Uint8List _offsetPcm(Uint8List inData) {
    List<int> outData = [];
    for (var element in inData) {
      outData.add((element + 128) % 256);
    }
    var outDataUint8 = Uint8List.fromList(outData);
    return outDataUint8.buffer.asUint8List();
  }
}
