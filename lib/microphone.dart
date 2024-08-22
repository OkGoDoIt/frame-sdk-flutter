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
  final Logger logger = Logger('Frame');
  Uint8List? _audioBuffer;
  int _bitDepth = 16;
  int _sampleRate = 8000;
  double silenceThreshold = 0.02;
  Completer<void> _audioFinishedCompleter = Completer<void>();
  double _lastSoundTime = 0;
  double _noiseFloor = 0;
  double? _silenceCutoffLength;
  double _maxLengthInSeconds = 30;

  Microphone(this.frame);

  /// Gets the bit depth (number of bits per audio sample), either 8 or 16.
  int get bitDepth => _bitDepth;

  /// Sets the bit depth (number of bits per audio sample) to either 8 or 16.
  /// 
  /// Throws:
  ///   ArgumentError: If the bit depth is not 8 or 16.
  set bitDepth(int value) {
    if (value != 8 && value != 16) {
      throw ArgumentError('Bit depth must be 8 or 16');
    }
    _bitDepth = value;
  }

  /// Gets the sample rate (number of audio samples per second), either 8000 or 16000.
  int get sampleRate => _sampleRate;

  /// Sets the sample rate (number of audio samples per second) to either 8000 or 16000.
  /// 
  /// Throws:
  ///   ArgumentError: If the sample rate is not 8000 or 16000.
  set sampleRate(int value) {
    if (value != 8000 && value != 16000) {
      throw ArgumentError('Sample rate must be 8000 or 16000');
    }
    _sampleRate = value;
  }

  /// Records audio from the microphone.
  /// 
  /// Args:
  ///   silenceCutoffLength (Duration?): The length of silence to allow before stopping the recording. Defaults to 3 seconds.
  ///   maxLength (Duration): The maximum length of the recording. Defaults to 30 seconds.
  /// 
  /// Returns:
  ///   Future<Uint8List>: The recorded audio data.
  /// 
  /// Throws:
  ///   StateError: If no audio data is recorded.
  Future<Uint8List> recordAudio({
    Duration? silenceCutoffLength = const Duration(seconds: 3),
    Duration maxLength = const Duration(seconds: 30),
  }) async {
    if (!frame.useLibrary) {
      throw Exception("Cannot record audio via SDK without library helpers");
    }
    await frame.runLua('frame.microphone.stop()', checked: true);

    if (silenceCutoffLength != null) {
      _silenceCutoffLength = silenceCutoffLength.inMilliseconds / 1000.0;
    } else {
      _silenceCutoffLength = null;
    }
    _maxLengthInSeconds = maxLength.inMilliseconds / 1000.0;
    _audioBuffer = Uint8List(0);
    _audioFinishedCompleter = Completer<void>();
    StreamSubscription<Uint8List> subscription = frame.bluetooth
        .getDataOfType(FrameDataTypePrefixes.micData)
        .listen(_audioBufferHandler);

    _lastSoundTime = DateTime.now().millisecondsSinceEpoch / 1000;

    logger.info('Starting audio recording at $_sampleRate Hz, $_bitDepth-bit');
    await frame.runLua(
      'microphoneRecordAndSend($_sampleRate,$_bitDepth,nil)',
    );

    await _audioFinishedCompleter.future;
    subscription.cancel();
    await frame.bluetooth.sendBreakSignal();
    await frame.runLua('frame.microphone.stop()');
    await Future.delayed(const Duration(milliseconds: 100));
    await frame.runLua('frame.microphone.stop()');

    if (_audioBuffer == null || _audioBuffer!.isEmpty) {
      throw StateError('No audio data recorded');
    }

    final lengthInSeconds =
        _audioBuffer!.length / (_bitDepth ~/ 8) / _sampleRate;
    final didTimeout = lengthInSeconds >= _maxLengthInSeconds;

    if (!didTimeout && silenceCutoffLength != null) {
      final trimLength = (silenceCutoffLength.inMilliseconds - 500) *
          _sampleRate *
          (_bitDepth ~/ 8) ~/
          1000;
      if (_audioBuffer!.length > trimLength) {
        _audioBuffer =
            _audioBuffer!.sublist(0, _audioBuffer!.length - trimLength.toInt());
      }
    }

    logger.info(
        'Audio recording finished with ${_audioBuffer!.length / (_bitDepth ~/ 8) / _sampleRate} seconds of audio');

    return _audioBuffer!;
  }

  /// Saves the recorded audio to a file.
  /// 
  /// Args:
  ///   filename (String): The name of the file to save the audio to.
  ///   silenceCutoffLength (Duration?): The length of silence to detect before stopping the recording automatically. Defaults to 3 seconds.
  ///   maxLength (Duration): The maximum length of the recording. Defaults to 30 seconds.
  /// 
  /// Returns:
  ///   Future<double>: The length of the recorded audio in seconds.
  /// 
  /// Throws:
  ///   ArgumentError: If no audio data is recorded.
  Future<double> saveAudioFile(
    String filename, {
    Duration? silenceCutoffLength = const Duration(seconds: 3),
    Duration maxLength = const Duration(seconds: 30),
  }) async {
    final audioData = await recordAudio(
      silenceCutoffLength: silenceCutoffLength,
      maxLength: maxLength,
    );

    if (audioData.isEmpty) {
      throw ArgumentError('No audio data recorded');
    }

    final file = File(filename);
    await file.writeAsBytes(_bytesToWav(audioData, bitDepth, sampleRate));

    final lengthInSeconds = audioData.length / (_bitDepth ~/ 8) / _sampleRate;
    return lengthInSeconds;
  }

  /// Handles incoming audio data and updates the audio buffer.
  /// 
  /// Args:
  ///   data (Uint8List): The incoming audio data.
  void _audioBufferHandler(Uint8List data) {
    if (_audioBuffer == null || _audioFinishedCompleter.isCompleted) {
      logger.fine('in _audioBufferHandler, audio buffer is null or the completer is completed');
      return;
    }

    //logger.finer('Appending ${data.length} bytes to the audio buffer for a new total of ${_audioBuffer!.length + data.length} bytes');

    _audioBuffer = Uint8List.fromList([..._audioBuffer!, ...data]);
    if (_audioBuffer!.length >
        (_maxLengthInSeconds * _sampleRate * _bitDepth ~/ 8)) {
      logger.fine('Audio buffer length exceeded max recording length');
      if (!_audioFinishedCompleter.isCompleted) {
        _audioFinishedCompleter.complete();
      }
      return;
    }

    if (_silenceCutoffLength != null) {
      final audioData = _convertBytesToAudioData(data, _bitDepth);
      final minAmplitude = audioData.reduce((a, b) => a < b ? a : b);
      final maxAmplitude = audioData.reduce((a, b) => a > b ? a : b);
      final delta = maxAmplitude - minAmplitude;

      final normalizedDelta = _bitDepth == 8 ? delta / 128.0 : delta / 32768.0;

      _noiseFloor += (normalizedDelta - _noiseFloor) * 0.1;

      if (normalizedDelta - _noiseFloor > silenceThreshold) {
        _lastSoundTime = DateTime.now().millisecondsSinceEpoch / 1000;
        //logger.finer('+');
      } else {
        if (DateTime.now().millisecondsSinceEpoch / 1000 - _lastSoundTime >
            _silenceCutoffLength!) {
          if (!_audioFinishedCompleter.isCompleted) {
            _audioFinishedCompleter.complete();
          }
          return;
        } else {
          //logger.finer('-');
        }
      }
    }
  }

  /// Converts raw audio bytes to a list of audio data.
  /// 
  /// Args:
  ///   audioBuffer (Uint8List): The raw audio data.
  ///   bitDepth (int): The bit depth of the audio data.
  /// 
  /// Returns:
  ///   List<int>: The converted audio data.
  /// 
  /// Throws:
  ///   ArgumentError: If the bit depth is unsupported.
  List<int> _convertBytesToAudioData(Uint8List audioBuffer, int bitDepth) {
    if (bitDepth == 16) {
      return audioBuffer.buffer.asInt16List().toList();
    } else if (bitDepth == 8) {
      return audioBuffer.buffer.asInt8List().toList();
    } else {
      throw ArgumentError('Unsupported bit depth');
    }
  }

  /// Normalizes the audio data.
  /// 
  /// Args:
  ///   audioBuffer (Uint8List): The raw audio data.
  ///   bitDepth (int): The bit depth of the audio data.
  /// 
  /// Returns:
  ///   List<int>: The normalized audio data.
  List<int> _normalizeAudio(Uint8List audioBuffer, int bitDepth) {
    final audioData = _convertBytesToAudioData(audioBuffer, bitDepth);
    final minAmplitude = audioData.reduce((a, b) => a < b ? a : b);
    final maxAmplitude = audioData.reduce((a, b) => a > b ? a : b);
    final delta = maxAmplitude - minAmplitude;
    final normalizedDelta = _bitDepth == 8 ? delta / 128.0 : delta / 32768.0;
    return audioData.map((e) => ((e - minAmplitude) / normalizedDelta).round()).toList();
  }

  /// Plays audio data.
  /// 
  /// Args:
  ///   audioData (Uint8List): The audio data to play.
  ///   sampleRate (int?): The sample rate of the audio data. Defaults to the instance's sample rate.
  ///   bitDepth (int?): The bit depth of the audio data. Defaults to the instance's bit depth.
  Future<void> playAudio(Uint8List audioData,
      {int? sampleRate, int? bitDepth}) async {
    final tempDir = await getTemporaryDirectory();
    File file = await File('${tempDir.path}/audio.wav').create();
    await file.writeAsBytes(_bytesToWav(
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

  /// Converts PCM bytes to a WAV file format.
  /// 
  /// Args:
  ///   pcmBytes (Uint8List): The PCM audio data.
  ///   bitDepth (int): The bit depth of the audio data.
  ///   sampleRate (int): The sample rate of the audio data.
  /// 
  /// Returns:
  ///   Uint8List: The WAV file data.
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
      output.add(_offsetPcm(pcmBytes));
    } catch (error) {
      logger.warning("Could not build audio file: $error");
    }
    return output.toBytes();
  }

  /// Converts a 32-bit integer to a list of 8-bit integers.
  /// 
  /// Args:
  Uint8List _uint32to8(int value) =>
      Uint8List.fromList([
        value & 0xFF,
        (value >> 8) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 24) & 0xFF,
      ]);

  Uint8List _uint16to8(int value) =>
      Uint8List.fromList([value & 0xFF, (value >> 8) & 0xFF]);

  Uint8List _offsetPcm(Uint8List inData) {
    final normalized = _normalizeAudio(inData, bitDepth);
    if (bitDepth == 8) {
      return Int8List.fromList(normalized).buffer.asUint8List();
    } else {
      return Int16List.fromList(normalized).buffer.asUint8List();
    }
  }
}
