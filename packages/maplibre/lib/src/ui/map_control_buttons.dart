import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Display a zoom-in and zoom-out button to the [MapLibreMap] by using it in
/// [MapLibreMap.children].
///
/// This widget is purposefully kept simple. If you need to change the design
/// or behavior of the zoom buttons a lot, prefer to copy this class into your
/// app and adjust it according to your needs.
///
/// {@category UI}
@immutable
class MapControlButtons extends StatefulWidget {
  /// Display a zoom-in and zoom-out button to the [MapLibreMap] by using it in
  /// [MapLibreMap.children].
  const MapControlButtons({
    super.key,
    this.padding = const EdgeInsets.symmetric(vertical: 50, horizontal: 12),
    this.alignment = Alignment.bottomRight,
    this.showTrackLocation = false,
    this.locationIconPng,
    this.waitForLocationIcon = false,
    this.resolveLocationIconPng,
    this.resolveInitialLocation,
    this.requestPermissionsExplanation =
        'We need your location to show it on the map.',
  });

  /// The padding.
  final EdgeInsets padding;

  /// The alignment of the buttons.
  final Alignment alignment;

  /// Whether to show the track location button.
  ///
  /// This button is currently not available on web.
  final bool showTrackLocation;

  /// Pre-rendered PNG for Android location puck (see [MapController.enableLocation]).
  final Uint8List? locationIconPng;

  /// When true, defer enabling until [locationIconPng] is non-null.
  ///
  /// Also implied when [resolveLocationIconPng] is set.
  final bool waitForLocationIcon;

  /// Loads puck PNG bytes before enabling location (e.g. async asset rasterization).
  ///
  /// While bytes are loading or still null, location is not enabled and the
  /// default puck is not shown.
  final Future<Uint8List?> Function()? resolveLocationIconPng;

  /// Optional seed fix before enabling (Android cold start / emulator).
  final Future<Geographic?> Function()? resolveInitialLocation;

  /// The explanation to show when requesting location permissions.
  final String requestPermissionsExplanation;

  @override
  State<MapControlButtons> createState() => _MapControlButtonsState();
}

class _MapControlButtonsState extends State<MapControlButtons> {
  late final PermissionManager? _permissionManager;
  _TrackLocationState _trackState = _TrackLocationState.gpsNotFixed;
  late bool _trackLocationButtonInitialized = false;
  bool _pendingLocationEnable = false;
  bool _pendingTrackLocation = true;

  bool get _showLocationButton =>
      MapController.userLocationIsSupported && widget.showTrackLocation;

  bool get _waitsForLocationIcon =>
      widget.waitForLocationIcon || widget.resolveLocationIconPng != null;

  @override
  void initState() {
    super.initState();
    if (_showLocationButton) {
      _permissionManager = PermissionManager();
    }
  }

  @override
  void didUpdateWidget(MapControlButtons oldWidget) {
    super.didUpdateWidget(oldWidget);

    final controller = MapController.maybeOf(context);
    if (controller == null) return;

    final iconReady =
        !_waitsForLocationIcon ||
        (oldWidget.locationIconPng == null &&
            hasEnableLocationIconBytes(widget.locationIconPng));
    final iconChanged = oldWidget.locationIconPng != widget.locationIconPng;

    if (iconReady && _pendingLocationEnable) {
      unawaited(
        _enableLocationServices(
          controller,
          trackLocation: _pendingTrackLocation,
        ),
      );
      return;
    }

    if (!iconChanged) return;
    if (_trackState != _TrackLocationState.gpsFixed) return;
    if (_waitsForLocationIcon &&
        !hasEnableLocationIconBytes(widget.locationIconPng)) {
      return;
    }

    unawaited(_enableLocationServices(controller, trackLocation: false));
  }

  @override
  Widget build(BuildContext context) {
    final controller = MapController.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();

    if (_showLocationButton) {
      if (!_trackLocationButtonInitialized) {
        _trackLocationButtonInitialized = true;
        if (_permissionManager?.locationPermissionsGranted ?? false) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await _initializeLocation(controller, trackLocation: false);
          });
        }
      }
    }

    return SafeArea(
      child: Container(
        alignment: widget.alignment,
        padding: widget.padding,
        child: PointerInterceptor(
          child: Column(
            spacing: 8,
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton(
                heroTag: 'MapLibreZoomInButton',
                onPressed: () => controller.animateCamera(
                  zoom: controller.getCamera().zoom + 1,
                  nativeDuration: const Duration(milliseconds: 200),
                ),
                child: const Icon(Icons.add),
              ),
              FloatingActionButton(
                heroTag: 'MapLibreZoomOutButton',
                onPressed: () => controller.animateCamera(
                  zoom: controller.getCamera().zoom - 1,
                  nativeDuration: const Duration(milliseconds: 200),
                ),
                child: const Icon(Icons.remove),
              ),
              if (_showLocationButton) ...[
                FloatingActionButton(
                  heroTag: 'MapLibreTrackLocationButton',
                  onPressed: () async => _initializeLocation(controller),
                  child: _trackState == _TrackLocationState.loading
                      ? const SizedBox.square(
                          dimension: kDefaultFontSize,
                          child: CircularProgressIndicator(),
                        )
                      : Icon(
                          _trackState == _TrackLocationState.gpsFixed
                              ? Icons.gps_fixed
                              : Icons.gps_not_fixed,
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _initializeLocation(
    MapController controller, {
    bool trackLocation = true,
  }) async {
    try {
      if (PermissionManager.isSupported &&
          !_permissionManager!.locationPermissionsGranted) {
        setState(() => _trackState = _TrackLocationState.loading);

        await _permissionManager.requestLocationPermissions(
          explanation: widget.requestPermissionsExplanation,
        );
      }
    } finally {
      await _enableLocationServices(controller, trackLocation: trackLocation);
    }
  }

  Future<void> _enableLocationServices(
    MapController controller, {
    bool trackLocation = true,
  }) async {
    _pendingLocationEnable = false;
    _pendingTrackLocation = trackLocation;

    if (!_permissionManager!.locationPermissionsGranted) {
      setState(() => _trackState = _TrackLocationState.gpsNotFixed);
      return;
    }

    if (controller.style == null) {
      _pendingLocationEnable = true;
      _pendingTrackLocation = trackLocation;
      setState(() => _trackState = _TrackLocationState.loading);
      for (var i = 0; i < 30; i++) {
        if (!mounted) return;
        if (controller.style != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (controller.style == null) {
        setState(() => _trackState = _TrackLocationState.gpsNotFixed);
        return;
      }
    }

    try {
      if (_waitsForLocationIcon && mounted) {
        setState(() => _trackState = _TrackLocationState.loading);
      }

      final initial = widget.resolveInitialLocation != null
          ? await widget.resolveInitialLocation!()
          : null;

      final enabled = await controller.enableLocation(
        locationIconPng: widget.locationIconPng,
        resolveLocationIconPng: widget.resolveLocationIconPng,
        requireLocationIcon: _waitsForLocationIcon,
        initialLocation: initial,
      );
      if (!mounted) return;
      if (!enabled) {
        _pendingLocationEnable = true;
        _pendingTrackLocation = trackLocation;
        setState(() => _trackState = _TrackLocationState.loading);
        return;
      }

      setState(() => _trackState = _TrackLocationState.gpsFixed);

      if (trackLocation) await controller.trackLocation();
    } on Exception {
      if (!mounted) return;
      setState(() => _trackState = _TrackLocationState.gpsNotFixed);
    }
  }
}

/// Location tracking state.
enum _TrackLocationState {
  /// Whether the permission is currently being fetched.
  loading,

  /// The permission is granted.
  gpsFixed,

  /// The permission is denied.
  gpsNotFixed,
}
