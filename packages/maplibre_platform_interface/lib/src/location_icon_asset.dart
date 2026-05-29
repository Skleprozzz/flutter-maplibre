import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 1×1 transparent PNG used to hide the default MapLibre location puck.
Uint8List get transparentLocationIconPng => Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2ZkAAAAASUVORK5CYII=',
  ),
);

/// Loads PNG bytes for a location icon [Flutter asset](https://docs.flutter.dev/ui/assets/assets-and-images) path.
Future<Uint8List?> loadLocationIconAssetBytes(String asset) async {
  if (asset.isEmpty) return null;
  try {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();
    if (bytes.isEmpty) return null;
    return bytes;
  } on Object {
    return null;
  }
}
