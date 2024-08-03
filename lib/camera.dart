import 'dart:io';
import 'dart:typed_data';
import 'package:frame_sdk/bluetooth.dart';

import 'frame_sdk.dart';
import 'package:image/image.dart';

/// Enum representing the quality of the photo.
enum PhotoQuality {
  low(10),
  medium(25),
  high(50),
  full(100);

  const PhotoQuality(this.value);
  final int value;
}

/// Enum representing the type of autofocus.
enum AutoFocusType {
  average("AVERAGE", 1),
  centerWeighted("CENTER_WEIGHTED", 2),
  spot("SPOT", 3);

  const AutoFocusType(this.name, this.exifValue);
  final String name;
  final int exifValue;
}

/// Class representing the Camera.
class Camera {
  final Frame frame;
  bool isAwake = true;

  Camera(this.frame);

  bool autoProcessPhoto = true;

  /// Takes a photo with the camera.
  ///
  /// Args:
  ///   autofocusSeconds (int?): The number of seconds to autofocus. Defaults to 3.
  ///   quality (PhotoQuality): The quality of the photo. Defaults to PhotoQuality.medium.
  ///   autofocusType (AutoFocusType): The type of autofocus. Defaults to AutoFocusType.average.
  ///
  /// Returns:
  ///   Future<Uint8List>: The photo as a byte array.
  ///
  /// Throws:
  ///   Exception: If the photo capture fails.
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

    final response =
        frame.bluetooth.waitForDataOfType(FrameDataTypePrefixes.photoData);
    await frame.runLua(
        "cameraCaptureAndSend(${quality.value},${autofocusSeconds ?? 'nil'},'${autofocusType.name}')");
    final imageBuffer = await response;

    if (imageBuffer.isEmpty) {
      throw Exception("Failed to get photo");
    }

    if (autoProcessPhoto) {
      return processPhoto(imageBuffer, autofocusType);
    }
    return imageBuffer;
  }

  /// Saves a photo to a file.
  ///
  /// Args:
  ///   filename (String): The name of the file to save the photo.
  ///   autofocusSeconds (int): The number of seconds to autofocus. Defaults to 3.
  ///   quality (PhotoQuality): The quality of the photo. Defaults to PhotoQuality.medium.
  ///   autofocusType (AutoFocusType): The type of autofocus. Defaults to AutoFocusType.average.
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

  /// Processes a photo to correct rotation and add metadata.
  ///
  /// Args:
  ///   imageBuffer (Uint8List): The photo as a byte array.
  ///   autofocusType (AutoFocusType?): The type of autofocus that was used to capture the photo.
  ///
  /// Returns:
  ///   Uint8List: The processed photo as a byte array.
  Uint8List processPhoto(Uint8List imageBuffer, AutoFocusType? autofocusType) {
    ExifData exif = decodeJpgExif(imageBuffer) ?? ExifData();

    exif.exifIfd.make = "Brilliant Labs";
    exif.exifIfd.model = "Frame";
    exif.exifIfd.software = "Frame Dart SDK";
    if (autofocusType != null) {
      exif.imageIfd.data[0x9207] = IfdValueShort(autofocusType.exifValue);
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