import 'dart:typed_data';

import 'package:flutter/services.dart';

/// MethodChannel bridge for native glTF location model rendering on Android.
abstract final class LocationModelBridge {
  static const _channel = MethodChannel('maplibre/location_model');

  static Future<void> attach({
    required int viewId,
    required String fileName,
    required Map<String, Uint8List> files,
    required double scale,
  }) async {
    await _channel.invokeMethod<void>('attach', {
      'viewId': viewId,
      'fileName': fileName,
      'files': files,
      'scale': scale,
    });
  }

  static Future<void> update({
    required int viewId,
    required double screenX,
    required double screenY,
    required double bearing,
    required bool visible,
  }) async {
    await _channel.invokeMethod<void>('update', {
      'viewId': viewId,
      'screenX': screenX,
      'screenY': screenY,
      'bearing': bearing,
      'visible': visible,
    });
  }

  static Future<void> detach(int viewId) async {
    await _channel.invokeMethod<void>('detach', {'viewId': viewId});
  }

  static Future<void> unregisterPlatformView(int viewId) async {
    await _channel.invokeMethod<void>('unregisterPlatformView', {
      'viewId': viewId,
    });
  }
}
