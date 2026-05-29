import 'package:flutter/services.dart';

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
