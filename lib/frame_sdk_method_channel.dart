import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'frame_sdk_platform_interface.dart';

/// An implementation of [FrameSdkPlatform] that uses method channels.
class MethodChannelFrameSdk extends FrameSdkPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('frame_sdk');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
