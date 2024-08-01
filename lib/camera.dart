import 'dart:io';
import 'dart:typed_data';
import 'frame_sdk.dart';
import 'package:image/image.dart';

enum PhotoQuality {
  low(10),
  medium(25),
  high(50),
  full(100);

  const PhotoQuality(this.value);
  final int value;
}

enum AutoFocusType {
  average("AVERAGE", 1),
  centerWeighted("CENTER_WEIGHTED", 2),
  spot("SPOT", 3);

  const AutoFocusType(this.value, this.exifValue);
  final String value;
  final int exifValue;
}

class Camera {
  final Frame frame;
  bool isAwake = true;

  Camera(this.frame);

  bool autoProcessPhoto = true;

  Future<Uint8List> takePhoto({
    int? autofocusSeconds = 3,
    PhotoQuality quality = PhotoQuality.medium,
    AutoFocusType autofocusType = AutoFocusType.average,
  }) async {
    if (!isAwake) {
      await frame.runLua("frame.camera.wake()", checked: true);
      await Future.delayed(const Duration(milliseconds: 500));
      isAwake = true;
    }
    
    final response = frame.bluetooth.waitForData();
    await frame.runLua(
        "cameraCaptureAndSend($quality,${autofocusSeconds ?? 'nil'},$autofocusType)");
    final imageBuffer = await response;

    if (imageBuffer.isEmpty) {
      throw Exception("Failed to get photo");
    }

    if (autoProcessPhoto) {
      return processPhoto(imageBuffer, autofocusType);
    }
    return imageBuffer;
  }

  Future<void> savePhoto(
    String filename, {
    int autofocusSeconds = 3,
    PhotoQuality quality = PhotoQuality.medium,
    AutoFocusType autofocusType = AutoFocusType.average,
  }) async {
    final imageBuffer = await takePhoto(
      autofocusSeconds: autofocusSeconds,
      quality: quality,
      autofocusType: autofocusType,
    );

    final file = File(filename);
    await file.writeAsBytes(imageBuffer);
  }

  Uint8List processPhoto(Uint8List imageBuffer, AutoFocusType? autofocusType) {
    ExifData exif = decodeJpgExif(imageBuffer) ?? ExifData();

    exif.exifIfd.make = "Brilliant Labs";
    exif.exifIfd.model = "Frame";
    exif.exifIfd.software = "Frame Dart SDK";
    if (autofocusType != null) {
      exif.exifIfd.data[0x9207] = IfdValueShort(autofocusType.exifValue);
    }

    exif.imageIfd.data[0x9003] =
        IfdValueAscii(DateTime.now().toIso8601String());

    // Set orientation to rotate 90 degrees clockwise
    exif.imageIfd.orientation = 6;

    // Inject updated EXIF data back into the image
    final updatedImageBuffer = injectJpgExif(imageBuffer, exif);
    if (updatedImageBuffer == null) {
      throw Exception("Failed to inject EXIF data");
    }
    return updatedImageBuffer;
  }
}
