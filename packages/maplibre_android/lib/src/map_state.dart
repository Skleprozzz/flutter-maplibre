import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' hide Layer;
import 'package:flutter/services.dart';
import 'package:jni/jni.dart';
import 'package:maplibre_android/src/extensions.dart';
import 'package:maplibre_android/src/flutter_api.dart';
import 'package:maplibre_android/src/functions.dart';
import 'package:maplibre_android/src/location_model_bridge.dart';
import 'package:maplibre_android/src/jni.g.dart' as jni;
import 'package:maplibre_android/src/registry.dart';
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';

part 'style_controller.dart';

/// The implementation that gets used for state of the [MapLibreMap] widget on
/// android using JNI and Pigeon as a fallback.
final class MapLibreMapStateAndroid extends MapLibreMapState
    with WidgetsBindingObserver {
  late final int _viewId;
  jni.MapView? _mapView;
  jni.MapLibreMap? _jMap;
  jni.Projection? _cachedJProjection;
  jni.LocationComponent? _cachedJLocationComponent;
  bool _mapViewStarted = false;
  bool _locationServicesEnabled = false;
  bool _pendingEnableLocation = false;
  Uint8List? _locationIconBytes;
  Future<Uint8List?>? _locationIconBytesFuture;
  LocationModelAssetBundle? _locationModelBundle;
  Future<LocationModelAssetBundle?>? _locationModelBundleFuture;
  bool _locationModelAttached = false;

  @override
  StyleControllerAndroid? style;

  jni.FrameLayout get _platformView => Registry.platformViews[_viewId]!;

  jni.Projection get _jProjection => _cachedJProjection ??= _jMap!.projection;

  jni.LocationComponent get _jLocationComponent =>
      _cachedJLocationComponent ??= _jMap!.locationComponent;

  late final _mapClickListener = jni.MapLibreMap$OnMapClickListener.implement(
    jni.$MapLibreMap$OnMapClickListener(
      onMapClick: (latLng) => using((arena) {
        latLng.releasedBy(arena);
        final screenLocation = _jProjection.toScreenLocation(latLng)
          ..releasedBy(arena);
        final pixelRatio = View.of(context).devicePixelRatio;
        widget.onEvent?.call(
          MapEventClick(
            point: latLng.toGeographic(),
            screenPoint: screenLocation.toOffset() / pixelRatio,
          ),
        );
        return true;
      }),
    ),
  );
  late final _mapLongClickListener =
      jni.MapLibreMap$OnMapLongClickListener.implement(
        jni.$MapLibreMap$OnMapLongClickListener(
          onMapLongClick: (latLng) => using((arena) {
            latLng.releasedBy(arena);
            final screenLocation = _jProjection.toScreenLocation(latLng)
              ..releasedBy(arena);
            final pixelRatio = View.of(context).devicePixelRatio;
            widget.onEvent?.call(
              MapEventLongClick(
                point: latLng.toGeographic(),
                screenPoint: screenLocation.toOffset() / pixelRatio,
              ),
            );
            return true;
          }),
        ),
      );
  late final _mapCameraMoveListener =
      jni.MapLibreMap$OnCameraMoveListener.implement(
        jni.$MapLibreMap$OnCameraMoveListener(
          onCameraMove: () => using((arena) {
            final mapCamera = getCamera();
            if (mounted) {
              setState(() => camera = mapCamera);
              widget.onEvent?.call(MapEventMoveCamera(camera: mapCamera));
              _updateLocationModelOverlay();
            }
          }),
        ),
      );
  late final _mapCameraIdleListener =
      jni.MapLibreMap$OnCameraIdleListener.implement(
        jni.$MapLibreMap$OnCameraIdleListener(
          onCameraIdle: () => using((arena) {
            widget.onEvent?.call(const MapEventCameraIdle());
          }),
        ),
      );
  late final _cameraMoveStartedListener =
      jni.MapLibreMap$OnCameraMoveStartedListener.implement(
        jni.$MapLibreMap$OnCameraMoveStartedListener(
          onCameraMoveStarted: (reason) => using((arena) {
            final moveReason = switch (reason) {
              jni.MapLibreMap$OnCameraMoveStartedListener.REASON_API_GESTURE =>
                CameraChangeReason.apiGesture,
              jni
                  .MapLibreMap$OnCameraMoveStartedListener
                  .REASON_API_ANIMATION =>
                CameraChangeReason.apiAnimation,
              jni
                  .MapLibreMap$OnCameraMoveStartedListener
                  .REASON_DEVELOPER_ANIMATION =>
                CameraChangeReason.developerAnimation,
              _ => null,
            };
            if (moveReason == null) return;
            widget.onEvent?.call(MapEventStartMoveCamera(reason: moveReason));
          }),
        ),
      );

  @override
  Widget buildPlatformWidget(BuildContext context) {
    const viewType = 'plugins.flutter.io/maplibre';
    jni.MapLibreRegistry.INSTANCE.flutterApi = jni.FlutterApi.implement(
      const FlutterApi(),
    );

    if (options.androidMode == AndroidPlatformViewMode.tlhc_vd) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: widget.gestureRecognizers,
      );
    }
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers:
              widget.gestureRecognizers ??
              const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final viewController = switch (options.androidMode) {
          // This attempts to use the newest and most efficient platform view
          // implementation when possible. In cases where that is not
          // supported, it falls back to using Hybrid Composition, which is
          // the mode used by initExpensiveAndroidView.
          // https://api.flutter.dev/flutter/services/PlatformViewsService/initSurfaceAndroidView.html
          // https://github.com/flutter/flutter/blob/master/docs/platforms/android/Android-Platform-Views.md#selecting-a-mode
          AndroidPlatformViewMode.tlhc_hc =>
            PlatformViewsService.initSurfaceAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              onFocus: () => params.onFocusChanged(true),
            ),
          AndroidPlatformViewMode.tlhc_vd =>
            PlatformViewsService.initAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              onFocus: () => params.onFocusChanged(true),
            ),
          AndroidPlatformViewMode.hc =>
            PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
              onFocus: () => params.onFocusChanged(true),
            ),
          // https://github.com/flutter/flutter/blob/master/docs/platforms/android/Virtual-Display.md
          AndroidPlatformViewMode.vd => PlatformViewsService.initAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            onFocus: () => params.onFocusChanged(true),
          ),
        };
        return viewController
          ..addOnPlatformViewCreatedListener((id) {
            params.onPlatformViewCreated(id);
            _onPlatformViewCreated(id);
          })
          ..create();
      },
    );
  }

  /// This method gets called when the platform view is created. It is not
  /// guaranteed that the map is ready.
  void _onPlatformViewCreated(int viewId) => using((arena) {
    _viewId = viewId;
    final jContext = getJContext();
    final cameraBuilder = jni.CameraPosition$Builder()
      ..releasedBy(arena)
      ..zoom(options.initZoom)
      ..bearing(options.initBearing)
      ..tilt(options.initPitch);
    if (options.initCenter case final Geographic center) {
      cameraBuilder.target(center.toLatLng()..releasedBy(arena));
    }
    final jMapOptions = jni.MapLibreMapOptions.createFromAttributes(jContext)
      ..releasedBy(arena)
      ..attributionEnabled(false)
      ..logoEnabled(false)
      ..compassEnabled(false)
      // TODO: textureMode comes at a significant performance penalty, https://maplibre.org/maplibre-native/android/api/-map-libre%20-native%20-android/org.maplibre.android.maps/-map-libre-map-options/texture-mode.html
      ..textureMode(options.androidTextureMode)
      ..foregroundLoadColor(options.androidForegroundLoadColor.toARGB32())
      ..translucentTextureSurface(options.androidTranslucentTextureSurface)
      ..minZoomPreference(options.minZoom)
      ..maxZoomPreference(options.maxZoom)
      ..minPitchPreference(options.minPitch)
      ..maxPitchPreference(options.maxPitch)
      ..rotateGesturesEnabled(options.gestures.rotate)
      ..zoomGesturesEnabled(options.gestures.zoom)
      ..doubleTapGesturesEnabled(options.gestures.zoom)
      ..scrollGesturesEnabled(options.gestures.zoom)
      ..quickZoomGesturesEnabled(options.gestures.zoom)
      ..tiltGesturesEnabled(options.gestures.pitch)
      ..camera(cameraBuilder.build()..releasedBy(arena));
    _mapView = jni.MapView.new$4(jContext, jMapOptions)
      ..getMapAsync(
        jni.OnMapReadyCallback.implement(_MapReadyCallback(_onMapReady)),
      );
    _platformView.addView(_mapView);

    // In some environments (notably `integration_test` on Android/CI),
    // `didChangeAppLifecycleState(AppLifecycleState.resumed)` is not reliably
    // delivered. MapLibre's `MapView` expects `onStart/onResume` to be called
    // before certain operations (e.g. projections / feature queries) behave
    // deterministically.
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    final shouldStartNow =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    if (shouldStartNow && !_mapViewStarted) {
      _mapView?.onStart();
      _mapView?.onResume();
      _mapViewStarted = true;
    }
  });

  void _onMapReady(jni.MapLibreMap jMap) => using((arena) {
    _jMap = jMap
      ..addOnMapClickListener(_mapClickListener)
      ..addOnMapLongClickListener(_mapLongClickListener)
      ..addOnCameraMoveListener(_mapCameraMoveListener)
      ..addOnCameraIdleListener(_mapCameraIdleListener)
      ..addOnCameraMoveStartedListener(_cameraMoveStartedListener)
      ..latLngBoundsForCameraTarget = options.maxBounds?.toJLatLngBounds(
        arena: arena,
      );
    setStyle(options.initStyle);
    widget.onEvent?.call(MapEventMapCreated(mapController: this));
    widget.onMapCreated?.call(this);
    camera = getCamera();
    isInitialized = true;
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
    unawaited(_ensureLocationIconBytes());
    unawaited(_ensureLocationModelBundle());
  }

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    _updateOptions(oldWidget);
    layerManager?.updateLayers(widget.layers);
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_jMap case final jMap?) {
      jMap.removeOnMapClickListener(_mapClickListener);
      jMap.removeOnMapLongClickListener(_mapLongClickListener);
      jMap.removeOnCameraMoveListener(_mapCameraMoveListener);
      jMap.removeOnCameraIdleListener(_mapCameraIdleListener);
      jMap.removeOnCameraMoveStartedListener(_cameraMoveStartedListener);
      _jMap = null;
      jMap.release();
    }
    _mapClickListener.release();
    _mapLongClickListener.release();
    _mapCameraMoveListener.release();
    _mapCameraIdleListener.release();
    _cameraMoveStartedListener.release();
    if (_cachedJProjection case final jProjection?) {
      _cachedJProjection = null;
      jProjection.release();
    }
    if (_cachedJLocationComponent case final jLocationComponent?) {
      _cachedJLocationComponent = null;
      jLocationComponent.release();
    }
    if (_mapView case final mapView?) {
      _mapView = null;
      if (_mapViewStarted) {
        mapView.onPause();
        mapView.onStop();
        _mapViewStarted = false;
      }
      mapView.onDestroy();
      mapView.release();
    }
    if (_hasCustomLocationModel &&
        Registry.platformViews.containsKey(_viewId)) {
      unawaited(LocationModelBridge.detach(_viewId));
      unawaited(LocationModelBridge.unregisterPlatformView(_viewId));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Start MapView only if it was stopped
      if (!_mapViewStarted) {
        _mapView?.onStart();
        _mapViewStarted = true;
      }
      _mapView?.onResume();
      _jMap?.triggerRepaint();
    } else {
      _mapView?.onPause();
      if (_mapViewStarted) {
        _mapView?.onStop();
        _mapViewStarted = false;
      }
    }
  }

  @override
  void didHaveMemoryPressure() => _mapView?.onLowMemory();

  Future<void> _updateOptions(MapLibreMap oldWidget) async => using((arena) {
    final jMap = _jMap;
    // jMap can be null if the widget rebuilds while the map hasn't been initialized.
    if (jMap == null) return;

    final oldOptions = oldWidget.options;
    final options = this.options;
    if (this.options == oldOptions) return;

    jMap.minZoomPreference = options.minZoom;
    jMap.maxZoomPreference = options.maxZoom;
    jMap.minPitchPreference = options.minPitch;
    jMap.maxPitchPreference = options.maxPitch;

    // map bounds
    final oldBounds = oldOptions.maxBounds;
    final newBounds = options.maxBounds;
    if (oldBounds != null && newBounds == null) {
      jMap.latLngBoundsForCameraTarget = null;
    } else if ((oldBounds == null && newBounds != null) ||
        (newBounds != null && oldBounds != newBounds)) {
      final bounds = newBounds.toJLatLngBounds(arena: arena);
      jMap.latLngBoundsForCameraTarget = bounds;
    }

    // gestures
    final uiSettings = jMap.uiSettings..releasedBy(arena);
    if (options.gestures.rotate != oldOptions.gestures.rotate) {
      uiSettings.rotateGesturesEnabled = options.gestures.rotate;
    }
    // TODO: pan is not handled, there is no setPanGestureEnabled on Android.
    /*if (options.gestures.pan != oldOptions.gestures.pan) {
        uiSettings.setPanGesturesEnabled(options.gestures.pan);
      }*/
    if (options.gestures.zoom != oldOptions.gestures.zoom) {
      uiSettings.zoomGesturesEnabled = options.gestures.zoom;
      uiSettings.doubleTapGesturesEnabled = options.gestures.zoom;
      uiSettings.scrollGesturesEnabled = options.gestures.zoom;
      uiSettings.quickZoomGesturesEnabled = options.gestures.zoom;
    }
    if (options.gestures.pitch != oldOptions.gestures.pitch) {
      uiSettings.tiltGesturesEnabled = options.gestures.pitch;
    }
  });

  @override
  Future<void> moveCamera({
    Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    EdgeInsets padding = EdgeInsets.zero,
  }) async => using((arena) {
    assert(_jMap != null, '_jMapLibreMap needs to be not null.');
    final cameraPosBuilder = jni.CameraPosition$Builder()..releasedBy(arena);
    if (center != null) cameraPosBuilder.target(center.toLatLng());
    if (zoom != null) cameraPosBuilder.zoom(zoom);
    if (pitch != null) cameraPosBuilder.tilt(pitch);
    if (bearing != null) cameraPosBuilder.bearing(bearing);
    final pixelRatio = View.of(context).devicePixelRatio;
    cameraPosBuilder.padding$1(
      padding.left * pixelRatio,
      padding.top * pixelRatio,
      padding.right * pixelRatio,
      padding.bottom * pixelRatio,
    );

    final cameraPosition = cameraPosBuilder.build()..releasedBy(arena);
    final cameraUpdate = jni.CameraUpdateFactory.newCameraPosition(
      cameraPosition,
    )..releasedBy(arena);
    _jMap?.moveCamera(cameraUpdate);
    return;
  });

  @override
  Future<void> animateCamera({
    Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    Duration nativeDuration = const Duration(seconds: 2),
    double webSpeed = 1.2,
    Duration? webMaxDuration,
    EdgeInsets padding = EdgeInsets.zero,
  }) async => using((arena) async {
    final jMap = _jMap;
    if (jMap == null) return;

    final cameraPosBuilder = jni.CameraPosition$Builder()..releasedBy(arena);
    if (center != null) cameraPosBuilder.target(center.toLatLng());
    if (zoom != null) cameraPosBuilder.zoom(zoom);
    if (pitch != null) cameraPosBuilder.tilt(pitch);
    if (bearing != null) cameraPosBuilder.bearing(bearing);
    final pixelRatio = View.of(context).devicePixelRatio;
    cameraPosBuilder.padding$1(
      padding.left * pixelRatio,
      padding.top * pixelRatio,
      padding.right * pixelRatio,
      padding.bottom * pixelRatio,
    );

    final cameraUpdate = jni.CameraUpdateFactory.newCameraPosition(
      cameraPosBuilder.build()..releasedBy(arena),
    )..releasedBy(arena);

    final completer = Completer<void>();
    jMap.animateCamera$3(
      cameraUpdate,
      nativeDuration.inMilliseconds,
      jni.MapLibreMap$CancelableCallback.implement(
        _CameraMovementCallback(completer),
      )..releasedBy(arena),
    );
    return completer.future;
  });

  @override
  Future<void> fitBounds({
    required LngLatBounds bounds,
    double? bearing,
    double? pitch,
    Duration nativeDuration = const Duration(seconds: 2),
    double webSpeed = 1.2,
    Duration? webMaxDuration,
    Offset offset = Offset.zero,
    double webMaxZoom = double.maxFinite,
    bool webLinear = false,
    EdgeInsets padding = EdgeInsets.zero,
  }) async => using((arena) async {
    final jMap = _jMap;
    if (jMap == null) return;

    final pixelRatio = View.of(context).devicePixelRatio;
    final cameraUpdate = jni.CameraUpdateFactory.newLatLngBounds$3(
      bounds.toJLatLngBounds(arena: arena),
      bearing ?? -1.0,
      pitch ?? -1.0,
      (padding.left * pixelRatio).toInt(),
      (padding.top * pixelRatio).toInt(),
      (padding.right * pixelRatio).toInt(),
      (padding.bottom * pixelRatio).toInt(),
    )..releasedBy(arena);

    final completer = Completer<void>();
    jMap.animateCamera$3(
      cameraUpdate,
      nativeDuration.inMilliseconds,
      jni.MapLibreMap$CancelableCallback.implement(
        _CameraMovementCallback(completer),
      )..releasedBy(arena),
    );
    return completer.future;
  });

  void _onStyleLoaded(jni.Style jStyle) {
    // We need to refresh the cached style for when the style reloads.
    style?.dispose();
    final styleCtrl = StyleControllerAndroid._(jStyle);
    style = styleCtrl;

    widget.onEvent?.call(MapEventStyleLoaded(styleCtrl));
    widget.onStyleLoaded?.call(styleCtrl);
    layerManager = LayerManager(styleCtrl, widget.layers);
    if (mounted) setState(() {});
    unawaited(() async {
      if (_hasCustomLocationModel) {
        await _setupCustomLocationModel();
      } else if (_hasCustomLocationIcon) {
        await _setupCustomLocationPuck();
      }
      if (_locationServicesEnabled || _pendingEnableLocation) {
        await _applyEnableLocation();
      }
    }());
  }

  bool get _hasCustomLocationModel {
    final asset = options.locationModelAsset;
    return asset != null && asset.isNotEmpty && isLocationModelAsset(asset);
  }

  bool get _hasCustomLocationIcon {
    if (_hasCustomLocationModel) return false;
    final asset = options.locationIconAsset;
    return asset != null && asset.isNotEmpty;
  }

  Geographic? get _locationSeed =>
      options.initialLocation ??
      options.initCenter ??
      ((_hasCustomLocationIcon || _hasCustomLocationModel)
          ? getCamera().center
          : null);

  Future<void> _setupCustomLocationModel() async {
    final bundle = await _ensureLocationModelBundle();
    if (bundle == null) return;
    await LocationModelBridge.attach(
      viewId: _viewId,
      fileName: bundle.fileName,
      files: bundle.files,
      scale: options.locationModelScale,
    );
    _locationModelAttached = true;
    _updateLocationModelOverlay();
  }

  void _updateLocationModelOverlay() {
    if (!_locationModelAttached) return;
    final location = _currentLocationForOverlay();
    if (location == null) {
      unawaited(
        LocationModelBridge.update(
          viewId: _viewId,
          screenX: 0,
          screenY: 0,
          bearing: 0,
          visible: false,
        ),
      );
      return;
    }
    final screen = toScreenLocation(location.geographic);
    final pixelRatio = View.of(context).devicePixelRatio;
    unawaited(
      LocationModelBridge.update(
        viewId: _viewId,
        screenX: screen.dx * pixelRatio,
        screenY: screen.dy * pixelRatio,
        bearing: location.bearing,
        visible: true,
      ),
    );
  }

  ({Geographic geographic, double bearing})? _currentLocationForOverlay() {
    if (_locationServicesEnabled || _pendingEnableLocation) {
      final lastKnown = using((arena) {
        final location = _jLocationComponent.lastKnownLocation
          ?..releasedBy(arena);
        if (location == null) return null;
        return (
          geographic: Geographic(
            lon: location.longitude,
            lat: location.latitude,
          ),
          bearing: location.bearing,
        );
      });
      if (lastKnown != null) return lastKnown;
    }
    final seed = _locationSeed;
    if (seed == null) return null;
    return (geographic: seed, bearing: getCamera().bearing);
  }

  Future<LocationModelAssetBundle?> _ensureLocationModelBundle() async {
    final asset = options.locationModelAsset;
    if (asset == null || asset.isEmpty || !isLocationModelAsset(asset)) {
      return null;
    }
    if (_locationModelBundle != null) return _locationModelBundle;
    return _locationModelBundleFuture ??= loadLocationModelAssetBundle(asset)
        .then((bundle) {
          _locationModelBundle = bundle;
          return bundle;
        });
  }

  /// Activates the location component with the custom icon and a seeded
  /// position, without starting the GPS engine yet.
  Future<void> _setupCustomLocationPuck() async {
    if (!await _registerLocationIcon()) return;
    await _applyEnableLocation(useLocationEngine: false);
  }

  Future<Uint8List?> _ensureLocationIconBytes() async {
    final asset = options.locationIconAsset;
    if (asset == null || asset.isEmpty) return null;
    if (_locationIconBytes != null) return _locationIconBytes;
    return _locationIconBytesFuture ??= loadLocationIconAssetBytes(asset).then((
      bytes,
    ) {
      _locationIconBytes = bytes;
      return bytes;
    });
  }

  Future<bool> _registerLocationIcon() async {
    final asset = options.locationIconAsset;
    if (asset == null || asset.isEmpty) return true;

    final style = this.style;
    if (style == null) return false;

    final bytes = await _ensureLocationIconBytes();
    if (bytes == null) return false;

    await style.addImage(MapController.defaultLocationIconStyleId, bytes);
    return true;
  }

  @override
  MapCamera getCamera() => using((arena) {
    final jniCamera = _jMap!.cameraPosition..releasedBy(arena);
    final jniTarget = jniCamera.target!..releasedBy(arena);
    return MapCamera(
      center: Geographic(lon: jniTarget.longitude, lat: jniTarget.latitude),
      zoom: jniCamera.zoom,
      pitch: jniCamera.tilt,
      bearing: jniCamera.bearing,
    );
    // camera = mapCamera;
  });

  List<RenderedFeature> _nativeQueryToRenderedFeatures(
    JList<jni.Feature?> query,
  ) {
    final features = query.asDart().where((f) => f != null).map((f) => f!);

    final gson = jni.Gson();
    return features
        .map(
          (feature) => RenderedFeature(
            id: feature.id()?.toDartString(releaseOriginal: true),
            properties:
                jsonDecode(
                      gson.toJson(feature.properties())?.toString() ?? '{}',
                    )
                    as Map<String, Object?>,
          ),
        )
        .toList(growable: false);
  }

  @override
  List<RenderedFeature> featuresAtPoint(
    Offset point, {
    List<String>? layerIds,
  }) {
    final style = this.style;
    final map = _jMap;
    if (style == null || map == null) {
      return [];
    }
    if (layerIds?.isEmpty ?? false) {
      // https://github.com/maplibre/maplibre-native/issues/2828
      return [];
    }

    final scaledPoint = point * View.of(context).devicePixelRatio;

    final query = map.queryRenderedFeatures(
      jni.PointF.new$3(scaledPoint.dx, scaledPoint.dy),
      layerIds != null
          ? JArray.of(JString.type, layerIds.map((s) => s.toJString()))
          : null,
    );

    return _nativeQueryToRenderedFeatures(query);
  }

  @override
  List<RenderedFeature> featuresInRect(Rect rect, {List<String>? layerIds}) {
    final style = this.style;
    final map = _jMap;
    if (style == null || map == null) {
      return [];
    }
    if (layerIds?.isEmpty ?? false) {
      // https://github.com/maplibre/maplibre-native/issues/2828
      return [];
    }

    final devicePixelRatio = View.of(context).devicePixelRatio;
    final scaledRect = Rect.fromLTRB(
      rect.left * devicePixelRatio,
      rect.top * devicePixelRatio,
      rect.right * devicePixelRatio,
      rect.bottom * devicePixelRatio,
    );

    final query = map.queryRenderedFeatures$2(
      jni.RectF.new$3(
        scaledRect.left,
        scaledRect.top,
        scaledRect.right,
        scaledRect.bottom,
      ),
      layerIds != null
          ? JArray.of(JString.type, layerIds.map((s) => s.toJString()))
          : null,
    );

    return _nativeQueryToRenderedFeatures(query);
  }

  @override
  List<QueriedLayer> queryLayers(Offset screenLocation) => using((arena) {
    final jMap = _jMap;
    if (jMap == null) {
      throw Exception(
        "queryLayers can't be called before the map is initialized.",
      );
    }
    final style = this.style;
    // there are no sources without a loaded style.
    if (style == null) return [];

    final jniLayers = style._getLayers()..releasedBy(arena);
    final queriedLayers = <QueriedLayer>[];
    for (var i = jniLayers.size() - 1; i >= 0; i--) {
      final jniLayer = jniLayers.get(i)!..releasedBy(arena);
      JString? jLayerId;
      late final JString jSourceId;
      late final JString jSourceLayer;
      if (jniLayer.isA(jni.LineLayer.type)) {
        final layer = jniLayer.as(jni.LineLayer.type)..releasedBy(arena);
        jLayerId = layer.id;
        jSourceId = layer.sourceId;
        jSourceLayer = layer.sourceLayer;
      } else if (jniLayer.isA(jni.FillLayer.type)) {
        final layer = jniLayer.as(jni.FillLayer.type)..releasedBy(arena);
        jLayerId = layer.id;
        jSourceId = layer.sourceId;
        jSourceLayer = layer.sourceLayer;
      } else if (jniLayer.isA(jni.FillExtrusionLayer.type)) {
        final layer = jniLayer.as(jni.FillExtrusionLayer.type)
          ..releasedBy(arena);
        jLayerId = layer.id;
        jSourceId = layer.sourceId;
        jSourceLayer = layer.sourceLayer;
      } else if (jniLayer.isA(jni.SymbolLayer.type)) {
        final layer = jniLayer.as(jni.SymbolLayer.type)..releasedBy(arena);
        jLayerId = layer.id;
        jSourceId = layer.sourceId;
        jSourceLayer = layer.sourceLayer;
      } else if (jniLayer.isA(jni.CircleLayer.type)) {
        final layer = jniLayer.as(jni.CircleLayer.type)..releasedBy(arena);
        jLayerId = layer.id;
        jSourceId = layer.sourceId;
        jSourceLayer = layer.sourceLayer;
      }
      if (jLayerId == null) continue; // ignore all other layers
      jLayerId.releasedBy(arena);
      jSourceId.releasedBy(arena);
      jSourceLayer.releasedBy(arena);

      final queryLayerIds = JArray.withLength(JString.type, 1)
        ..releasedBy(arena)
        ..[0] = jLayerId;
      // query one layer at a time
      final pixelRatio = View.of(context).devicePixelRatio;
      final scaledPoint = (screenLocation * pixelRatio).toJPointF(arena: arena);
      final jniFeatures = jMap.queryRenderedFeatures(scaledPoint, queryLayerIds)
        ..releasedBy(arena);
      if (jniFeatures.isEmpty()) continue; // layer hasn't been clicked if empty
      final sourceLayer = jSourceLayer.toDartString();
      final queriedLayer = QueriedLayer(
        layerId: jLayerId.toDartString(),
        sourceId: jSourceId.toDartString(),
        sourceLayer: sourceLayer.isEmpty ? null : sourceLayer,
      );
      queriedLayers.add(queriedLayer);
    }
    return queriedLayers;
  });

  @override
  Future<void> enableLocation({
    Duration fastestInterval = const Duration(milliseconds: 750),
    Duration maxWaitTime = const Duration(seconds: 1),
    bool pulseFade = true,
    bool accuracyAnimation = true,
    bool compassAnimation = true,
    bool pulse = true,
    BearingRenderMode bearingRenderMode = BearingRenderMode.gps,
  }) async {
    _locationServicesEnabled = true;
    if (style == null) {
      _pendingEnableLocation = true;
      return;
    }
    await _applyEnableLocation(
      fastestInterval: fastestInterval,
      maxWaitTime: maxWaitTime,
      pulseFade: pulseFade,
      accuracyAnimation: accuracyAnimation,
      compassAnimation: compassAnimation,
      pulse: pulse,
      bearingRenderMode: bearingRenderMode,
    );
  }

  Future<void> _applyEnableLocation({
    Duration fastestInterval = const Duration(milliseconds: 750),
    Duration maxWaitTime = const Duration(seconds: 1),
    bool pulseFade = true,
    bool accuracyAnimation = true,
    bool compassAnimation = true,
    bool pulse = true,
    BearingRenderMode bearingRenderMode = BearingRenderMode.gps,
    bool useLocationEngine = true,
  }) async {
    if (useLocationEngine) {
      _pendingEnableLocation = false;
    }
    final style = this.style;
    if (style == null) return;

    final iconAsset = options.locationIconAsset;
    Uint8List? bytes;
    if (_hasCustomLocationIcon && iconAsset != null && iconAsset.isNotEmpty) {
      if (!await _registerLocationIcon()) return;
      bytes = _locationIconBytes;
    }

    final seedLocation = _locationSeed;

    using((arena) {
      final bearing = switch (bearingRenderMode) {
        BearingRenderMode.none => jni.RenderMode.NORMAL,
        BearingRenderMode.compass => jni.RenderMode.COMPASS,
        BearingRenderMode.gps => jni.RenderMode.GPS,
      };
      final renderMode = useLocationEngine ? bearing : jni.RenderMode.NORMAL;
      final jniContext = getJContext();
      var locOptionsBuilder =
          jni.LocationComponentOptions.builder(jniContext)
                .pulseFadeEnabled(pulseFade)!
                .accuracyAnimationEnabled(accuracyAnimation)!
                .compassAnimationEnabled(compassAnimation.toJBoolean())!
            ..releasedBy(arena);
      if (bytes != null && bytes.isNotEmpty) {
        final iconId = MapController.defaultLocationIconStyleId.toJString()
          ..releasedBy(arena);
        locOptionsBuilder = locOptionsBuilder
            .pulseEnabled(false)!
            .accuracyAlpha(0)
            .enableStaleState(false)
            .foregroundName(iconId)
            .gpsName(iconId)
            .bearingName(iconId)
            .backgroundName(iconId)
            .foregroundStaleName(iconId)
            .backgroundStaleName(iconId);
      } else if (_hasCustomLocationModel) {
        locOptionsBuilder = locOptionsBuilder
            .pulseEnabled(false)!
            .accuracyAlpha(0)
            .enableStaleState(false)!;
      } else {
        locOptionsBuilder = locOptionsBuilder.pulseEnabled(pulse)!;
      }
      final locOptions = locOptionsBuilder.build()..releasedBy(arena);
      final locationEngineRequestBuilder =
          jni.LocationEngineRequest$Builder(750) // TODO integrate as parameter
                .setFastestInterval(fastestInterval.inMilliseconds)!
                .setMaxWaitTime(maxWaitTime.inMilliseconds)!
                .setPriority(jni.LocationEngineRequest.PRIORITY_HIGH_ACCURACY)!
            ..releasedBy(arena);
      final locationEngineRequest = locationEngineRequestBuilder.build()
        ?..releasedBy(arena);
      final activationOptionsBuilder =
          jni.LocationComponentActivationOptions.builder(
                  jniContext,
                  style._jStyle,
                )
                .locationComponentOptions(locOptions)!
                .useDefaultLocationEngine(useLocationEngine)!
                .locationEngineRequest(locationEngineRequest)!
            ..releasedBy(arena);
      final activationOptions = activationOptionsBuilder.build()!
        ..releasedBy(arena);

      _jLocationComponent.activateLocationComponent(activationOptions);
      _jLocationComponent.renderMode = renderMode;
      _jLocationComponent.locationComponentEnabled = true;

      if (seedLocation != null) {
        final provider = 'maplibre-seed'.toJString()..releasedBy(arena);
        final location = jni.Location.new$1(provider)..releasedBy(arena);
        location.latitude = seedLocation.lat;
        location.longitude = seedLocation.lon;
        location.time = DateTime.now().millisecondsSinceEpoch;
        _jLocationComponent.forceLocationUpdate(location);
      }
    });

    if (_hasCustomLocationModel) {
      _updateLocationModelOverlay();
    }

    if (seedLocation != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _jMap == null) return;
        using((arena) {
          final provider = 'maplibre-seed'.toJString()..releasedBy(arena);
          final location = jni.Location.new$1(provider)..releasedBy(arena);
          location.latitude = seedLocation.lat;
          location.longitude = seedLocation.lon;
          location.time = DateTime.now().millisecondsSinceEpoch;
          _jLocationComponent.forceLocationUpdate(location);
        });
      });
    }
  }

  @override
  Future<void> trackLocation({
    bool trackLocation = true,
    BearingTrackMode trackBearing = BearingTrackMode.gps,
  }) async {
    final mode = switch (trackBearing) {
      BearingTrackMode.none =>
        trackLocation
            // only location
            ? jni.CameraMode.TRACKING
            // neither location nor bearing
            : jni.CameraMode.NONE,

      BearingTrackMode.compass =>
        trackLocation
            // location with compass bearing
            ? jni.CameraMode.TRACKING_COMPASS
            // only compass bearing
            : jni.CameraMode.NONE_COMPASS,

      BearingTrackMode.gps =>
        trackLocation
            // location with gps bearing
            ? jni.CameraMode.TRACKING_GPS
            // only gps bearing
            : jni.CameraMode.NONE_GPS,
    };
    _jLocationComponent.cameraMode = mode;
  }

  @override
  Geographic toLngLat(Offset screenLocation) => using((arena) {
    final pixelRatio = View.of(context).devicePixelRatio;
    final screenPoint = (screenLocation * pixelRatio).toJPointF(arena: arena);
    return _jProjection.fromScreenLocation(screenPoint).toGeographic();
  });

  @override
  List<Geographic> toLngLats(List<Offset> screenLocations) =>
      screenLocations.map(toLngLat).toList(growable: false);

  @override
  Offset toScreenLocation(Geographic lngLat) => using((arena) {
    final screenLocation = _jProjection.toScreenLocation(
      lngLat.toLatLng()..releasedBy(arena),
    )..releasedBy(arena);
    final pixelRatio = View.of(context).devicePixelRatio;
    return screenLocation.toOffset() / pixelRatio;
  });

  @override
  List<Offset> toScreenLocations(List<Geographic> lngLats) =>
      lngLats.map(toScreenLocation).toList(growable: false);

  @override
  double getMetersPerPixelAtLatitude(double latitude) =>
      _jProjection.getMetersPerPixelAtLatitude(latitude);

  @override
  LngLatBounds getVisibleRegion() => using((arena) {
    final region = _jProjection.visibleRegion..releasedBy(arena);
    final jniBounds = region.latLngBounds..releasedBy(arena);
    return jniBounds.toLngLatBounds();
  });

  /// Note, that [MapController.setStyle] is synchronous.
  @override
  Future<void> setStyle(String style) async => using((arena) async {
    final trimmed = style.trim();
    final builder = jni.Style$Builder()..releasedBy(arena);
    if (trimmed.startsWith('{')) {
      // Raw JSON
      builder.fromJson(trimmed.toJString()..releasedBy(arena));
    } else if (trimmed.startsWith('/')) {
      builder.fromUri('file://$trimmed'.toJString()..releasedBy(arena));
    } else if (!trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://') &&
        !trimmed.startsWith('mapbox://')) {
      // flutter asset
      final content = await rootBundle.loadString(trimmed);
      builder.fromJson(content.toJString()..releasedBy(arena));
    } else {
      // URI
      builder.fromUri(trimmed.toJString()..releasedBy(arena));
    }
    _jMap?.setStyle$1(
      builder,
      jni.Style$OnStyleLoaded.implement(_StyleLoadedCallback(_onStyleLoaded))
        ..releasedBy(arena),
    );
  });
}

final class _CameraMovementCallback with jni.$MapLibreMap$CancelableCallback {
  const _CameraMovementCallback(this.completer);

  final Completer<void> completer;

  @override
  void onCancel() {
    // Overlapping animateCamera/fitBounds calls cancel the previous animation.
    // This is expected; do not surface as an unhandled async error.
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  void onFinish() {
    if (!completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  bool get onCancel$async => true;

  @override
  bool get onFinish$async => true;
}

final class _StyleLoadedCallback with jni.$Style$OnStyleLoaded {
  const _StyleLoadedCallback(this.callback);

  final void Function(jni.Style jStyle) callback;

  @override
  void onStyleLoaded(jni.Style style) {
    callback.call(style);
  }
}

final class _MapReadyCallback with jni.$OnMapReadyCallback {
  const _MapReadyCallback(this.callback);

  final void Function(jni.MapLibreMap jMap) callback;

  @override
  void onMapReady(jni.MapLibreMap jMap) {
    callback.call(jMap);
  }
}
