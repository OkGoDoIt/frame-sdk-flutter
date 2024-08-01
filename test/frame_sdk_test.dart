import 'package:flutter_test/flutter_test.dart';
import 'package:frame_sdk/frame_sdk.dart';
import 'package:frame_sdk/frame_sdk_platform_interface.dart';
import 'package:frame_sdk/frame_sdk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFrameSdkPlatform
    with MockPlatformInterfaceMixin
    implements FrameSdkPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FrameSdkPlatform initialPlatform = FrameSdkPlatform.instance;

  test('$MethodChannelFrameSdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFrameSdk>());
  });

  test('getPlatformVersion', () async {
    Frame frameSdkPlugin = Frame();
    MockFrameSdkPlatform fakePlatform = MockFrameSdkPlatform();
    FrameSdkPlatform.instance = fakePlatform;

    expect(await frameSdkPlugin.getPlatformVersion(), '42');
  });
}
