import 'dart:typed_data';

/// Whether [bytes] contain a non-empty location puck image.
bool hasEnableLocationIconBytes(Uint8List? bytes) =>
    bytes != null && bytes.isNotEmpty;

/// Resolves location puck bytes from sync and/or async sources.
Future<Uint8List?> resolveEnableLocationIconBytes({
  Uint8List? locationIconPng,
  Future<Uint8List?> Function()? resolveLocationIconPng,
}) async {
  if (hasEnableLocationIconBytes(locationIconPng)) {
    return locationIconPng;
  }

  final loader = resolveLocationIconPng;
  if (loader == null) return locationIconPng;

  return loader();
}

/// Whether [enableLocation] should skip enabling (no default puck).
bool shouldDeferEnableLocation({
  required bool requireLocationIcon,
  required Future<Uint8List?> Function()? resolveLocationIconPng,
  required Uint8List? resolvedBytes,
}) {
  if (!requireLocationIcon && resolveLocationIconPng == null) {
    return false;
  }
  return !hasEnableLocationIconBytes(resolvedBytes);
}
