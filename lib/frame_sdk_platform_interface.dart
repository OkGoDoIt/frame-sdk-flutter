import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'frame_sdk_method_channel.dart';

abstract class FrameSdkPlatform extends PlatformInterface {
  /// Constructs a FrameSdkPlatform.
  FrameSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static FrameSdkPlatform _instance = MethodChannelFrameSdk();

  /// The default instance of [FrameSdkPlatform] to use.
  ///
  /// Defaults to [MethodChannelFrameSdk].
  static FrameSdkPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FrameSdkPlatform] when
  /// they register themselves.
  static set instance(FrameSdkPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
