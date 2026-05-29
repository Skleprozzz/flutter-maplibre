import 'dart:typed_data';

import 'package:flutter/services.dart';

const _supportedLocationModelExtensions = {'.glb', '.gltf'};

/// Whether [asset] points to a supported glTF / GLB location model.
bool isLocationModelAsset(String asset) {
  final lower = asset.toLowerCase();
  return _supportedLocationModelExtensions.any(lower.endsWith);
}

/// glTF / GLB model files loaded from the Flutter asset bundle.
class LocationModelAssetBundle {
  /// Creates a bundle of model files keyed by file name.
  const LocationModelAssetBundle({required this.fileName, required this.files});

  /// Primary model file name (for example `car.gltf` or `user.glb`).
  final String fileName;

  /// Model files keyed by file name only (no directory segments).
  final Map<String, Uint8List> files;
}

/// Loads bytes for [MapOptions.locationModelAsset] (.glb / .gltf).
Future<Uint8List?> loadLocationModelAssetBytes(String asset) async {
  final bundle = await loadLocationModelAssetBundle(asset);
  return bundle?.files[bundle.fileName];
}

/// Loads the model and any sibling files from the same asset directory.
///
/// glTF models often reference external `.bin` / texture files in the same
/// folder; those are included automatically when declared in `pubspec.yaml`.
Future<LocationModelAssetBundle?> loadLocationModelAssetBundle(
  String asset,
) async {
  if (asset.isEmpty || !isLocationModelAsset(asset)) return null;

  final fileName = locationModelAssetFileName(asset);
  final directory = _assetDirectoryOf(asset);
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final candidates = manifest.listAssets().where((path) {
    if (directory.isEmpty) {
      return path == asset;
    }
    if (!path.startsWith(directory)) {
      return false;
    }
    return !path.substring(directory.length).contains('/');
  });

  final files = <String, Uint8List>{};
  for (final path in candidates) {
    try {
      final data = await rootBundle.load(path);
      final bytes = data.buffer.asUint8List();
      if (bytes.isEmpty) continue;
      files[locationModelAssetFileName(path)] = bytes;
    } on Object {
      // Skip assets that fail to load.
    }
  }

  if (!files.containsKey(fileName)) return null;
  return LocationModelAssetBundle(fileName: fileName, files: files);
}

/// File name extracted from a Flutter asset path (used when writing model cache).
String locationModelAssetFileName(String asset) {
  final normalized = asset.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

String _assetDirectoryOf(String asset) {
  final normalized = asset.replaceAll(r'\', '/');
  final index = normalized.lastIndexOf('/');
  return index < 0 ? '' : normalized.substring(0, index + 1);
}
