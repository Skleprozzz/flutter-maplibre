import 'dart:typed_data';

import 'package:flutter/services.dart';

const _supportedLocationModelExtensions = {'.glb', '.gltf'};

/// Whether [asset] points to a supported glTF / GLB location model.
bool isLocationModelAsset(String asset) {
  final lower = asset.toLowerCase();
  return _supportedLocationModelExtensions.any(lower.endsWith);
}

/// Loads bytes for [MapOptions.locationModelAsset] (.glb / .gltf).
Future<Uint8List?> loadLocationModelAssetBytes(String asset) async {
  if (asset.isEmpty || !isLocationModelAsset(asset)) return null;
  try {
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List();
    if (bytes.isEmpty) return null;
    return bytes;
  } on Object {
    return null;
  }
}

/// File name extracted from a Flutter asset path (used when writing model cache).
String locationModelAssetFileName(String asset) {
  final normalized = asset.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}
