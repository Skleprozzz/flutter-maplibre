import Flutter
import MapLibre

private final class MapLibreCustomUserLocationAnnotationView: MLNUserLocationAnnotationView {
    private let iconView: UIImageView

    init(image: UIImage, reuseIdentifier: String) {
        iconView = UIImageView(image: image)
        super.init(reuseIdentifier: reuseIdentifier)
        iconView.contentMode = .scaleAspectFit
        iconView.frame = CGRect(origin: .zero, size: image.size)
        addSubview(iconView)
        frame = iconView.frame
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateImage(_ image: UIImage) {
        iconView.image = image
        iconView.frame = CGRect(origin: .zero, size: image.size)
        frame = iconView.frame
    }
}

class MapLibreView: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate, MLNMapViewDelegate {
    private static let userLocationReuseId = "MapLibreUserLocation"
    private static let seedLocationReuseId = "MapLibreSeedLocation"

    private var _view: UIView = .init()
    private var _viewId: Int64
    private var _mapView: MLNMapView!
    private var _registrar: FlutterPluginRegistrar
    private var _locationIconAssetPath: String?
    private var _locationIconImage: UIImage?
    private var _locationModelAssetPath: String?
    private var _locationModelScale: Float = 1
    private var _locationModelController: LocationModelController?
    private var _locationSeedCoordinate: CLLocationCoordinate2D?
    private var _seedAnnotation: MLNPointAnnotation?

    init(
        registrar: FlutterPluginRegistrar,
        frame: CGRect,
        viewId: Int64,
        initStyle: String,
        locationIconAsset: String? = nil,
        locationModelAsset: String? = nil,
        locationModelScale: Double = 1,
        locationSeedLat: Double? = nil,
        locationSeedLon: Double? = nil
    ) {
        _registrar = registrar
        _viewId = viewId
        _locationModelAssetPath = locationModelAsset
        _locationModelScale = Float(locationModelScale)
        if locationModelAsset == nil || locationModelAsset?.isEmpty == true {
            _locationIconAssetPath = locationIconAsset
            if let asset = locationIconAsset, !asset.isEmpty {
                _locationIconImage = Self.loadFlutterAssetImage(
                    asset,
                    registrar: registrar
                )
            }
        } else if let asset = locationModelAsset, !asset.isEmpty {
            _locationModelAssetPath = asset
        }
        if let lat = locationSeedLat, let lon = locationSeedLon {
            _locationSeedCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        super.init() // self can be used after calling super.init()

        let trimmed = initStyle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.starts(with: "{") {
            // Raw JSON
            _mapView = MLNMapView(frame: frame, styleJSON: trimmed)
        } else if trimmed.starts(with: "/") {
            _mapView = MLNMapView(frame: frame, styleURL: URL(fileURLWithPath: trimmed))
        } else if !trimmed.starts(with: "http://"),
                  !trimmed.starts(with: "https://"),
                  !trimmed.starts(with: "mapbox://")
        {
            // flutter asset
            let assetPath = _registrar.lookupKey(forAsset: initStyle)
            let url = URL(string: assetPath, relativeTo: Bundle.main.resourceURL)!
            _mapView = MLNMapView(frame: frame, styleURL: url)
        } else {
            // URI
            _mapView = MLNMapView(frame: frame, styleURL: URL(string: trimmed)!)
        }

        _mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        MapLibreRegistry.addMap(viewId: viewId, map: _mapView)
        _view.addSubview(_mapView)
        _mapView.delegate = self

        // Double tap
        let doubleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(onDoubleTap(sender:))
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        _mapView.addGestureRecognizer(doubleTap)

        let primaryTap = UITapGestureRecognizer(
            target: self,
            action: #selector(onTap(_:))
        )
        primaryTap.numberOfTapsRequired = 1
        primaryTap.cancelsTouchesInView = false
        primaryTap.require(toFail: doubleTap)
        primaryTap.delegate = self
        if #available(iOS 13.4, *) {
            primaryTap.buttonMaskRequired = .primary
        }
        _mapView.addGestureRecognizer(primaryTap)

        if #available(iOS 13.4, *) {
            let secondaryTap = UITapGestureRecognizer(
                target: self,
                action: #selector(onSecondaryTap(_:))
            )
            secondaryTap.numberOfTapsRequired = 1
            secondaryTap.cancelsTouchesInView = false
            secondaryTap.require(toFail: doubleTap)
            secondaryTap.delegate = self
            secondaryTap.buttonMaskRequired = .secondary
            _mapView.addGestureRecognizer(secondaryTap)
        }

        // Long press
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(onLongPress(sender:))
        )

        longPress.minimumPressDuration = 0.5
        longPress.allowableMovement = 10
        longPress.cancelsTouchesInView = false

        // Long press waits for taps
        longPress.require(toFail: primaryTap)
        longPress.require(toFail: doubleTap)

        longPress.delegate = self
        _mapView.addGestureRecognizer(longPress)

        if let asset = _locationModelAssetPath,
           let url = Self.loadFlutterAssetURL(asset, registrar: _registrar)
        {
            _locationModelController = LocationModelController(
                parent: _view,
                modelURL: url,
                scale: _locationModelScale
            )
        }
    }

    var api: FlutterApi? {
        MapLibreRegistry.getFlutterApi(viewId: _viewId)
    }

    @objc private func onTap(_ sender: UITapGestureRecognizer) {
        let screenPosition = sender.location(in: _mapView)
        api?.onTap(screenLocation: screenPosition)
    }

    @objc private func onSecondaryTap(_ sender: UITapGestureRecognizer) {
        let screenPosition = sender.location(in: _mapView)
        api?.onSecondaryTap(screenLocation: screenPosition)
    }

    @objc func onDoubleTap(sender: UITapGestureRecognizer) {
        var screenPosition = sender.location(in: _mapView)
        api?.onDoubleTap(screenLocation: screenPosition)
    }

    @objc func onLongPress(sender: UILongPressGestureRecognizer) {
        guard sender.state == .began else { return }
        var screenPosition = sender.location(in: _mapView)
        api?.onLongPress(screenLocation: screenPosition)
    }

    func view() -> UIView {
        _view
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        // Do not override the default behavior of MapLibre
        true
    }

    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
        api?.didFinishLoadingStyle(mapView: mapView, style: style)
        if _locationModelController != nil {
            refreshLocationModel()
        } else {
            showSeedLocationMarkerIfNeeded()
            if mapView.showsUserLocation, _locationIconImage != nil {
                mapView.updateUserLocationAnnotationView()
            }
        }
    }

    func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
        if _locationModelController != nil {
            refreshLocationModel()
            return
        }
        if userLocation?.location != nil {
            removeSeedLocationMarker()
        }
        if _locationIconAssetPath != nil, _locationIconImage != nil {
            mapView.updateUserLocationAnnotationView()
        }
    }

    func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
        api?.regionWillChangeWithReason(mapView: mapView, reason: reason.rawValue, animated: animated)
    }

    func mapView(_ mapView: MLNMapView, regionIsChangingWith reason: MLNCameraChangeReason) {
        api?.regionIsChangingWithReason(mapView: mapView, reason: reason.rawValue)
    }

    func mapView(_ mapView: MLNMapView, regionDidChangeWith reason: MLNCameraChangeReason, animated: Bool) {
        api?.regionDidChangeWithReason(mapView: mapView, reason: reason.rawValue, animated: animated)
        if _locationModelController != nil {
            refreshLocationModel()
        }
    }

    func mapViewDidBecomeIdle(_ mapView: MLNMapView) {
        api?.didBecomeIdle(mapView: mapView)
    }

    func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        if let seed = _seedAnnotation, annotation === seed {
            guard let image = _locationIconImage else { return nil }
            let annotationView = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.seedLocationReuseId
            ) ?? MLNAnnotationView(reuseIdentifier: Self.seedLocationReuseId)
            Self.configureAnnotationView(annotationView, image: image)
            return annotationView
        }

        guard annotation is MLNUserLocation else { return nil }

        if _locationModelController != nil {
            var hiddenView = mapView.dequeueReusableAnnotationView(
                withIdentifier: "MapLibreHiddenUserLocation"
            )
            if hiddenView == nil {
                hiddenView = MLNAnnotationView(reuseIdentifier: "MapLibreHiddenUserLocation")
            }
            hiddenView?.isHidden = true
            hiddenView?.frame = .zero
            return hiddenView
        }

        if _locationIconAssetPath != nil {
            guard let image = _locationIconImage else {
                return nil
            }
            let annotationView = mapView.dequeueReusableAnnotationView(
                withIdentifier: Self.userLocationReuseId
            ) as? MapLibreCustomUserLocationAnnotationView
                ?? MapLibreCustomUserLocationAnnotationView(
                    image: image,
                    reuseIdentifier: Self.userLocationReuseId
                )
            annotationView.updateImage(image)
            return annotationView
        }

        return nil
    }

    private static func configureAnnotationView(_ view: MLNAnnotationView, image: UIImage) {
        view.frame = CGRect(origin: .zero, size: image.size)
        let iconView: UIImageView
        if let existing = view.viewWithTag(1) as? UIImageView {
            iconView = existing
        } else {
            iconView = UIImageView()
            iconView.tag = 1
            iconView.contentMode = .scaleAspectFit
            view.addSubview(iconView)
        }
        iconView.image = image
        iconView.frame = view.bounds
        iconView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private func showSeedLocationMarkerIfNeeded() {
        guard _locationIconImage != nil,
              _seedAnnotation == nil,
              let coordinate = _locationSeedCoordinate
        else { return }

        if _mapView.userLocation?.location != nil {
            return
        }

        let annotation = MLNPointAnnotation()
        annotation.coordinate = coordinate
        _seedAnnotation = annotation
        _mapView.addAnnotation(annotation)
    }

    private func removeSeedLocationMarker() {
        guard let seed = _seedAnnotation else { return }
        _mapView.removeAnnotation(seed)
        _seedAnnotation = nil
    }

    private func refreshLocationModel() {
        guard let controller = _locationModelController else { return }
        let coordinate = _mapView.userLocation?.location?.coordinate
            ?? _locationSeedCoordinate
        guard let coordinate else {
            controller.update(screenX: 0, screenY: 0, bearing: 0, visible: false)
            return
        }
        let point = _mapView.convert(coordinate, toPointTo: _mapView)
        let bearing = _mapView.userLocation?.location?.course ?? _mapView.direction
        controller.update(
            screenX: point.x,
            screenY: point.y,
            bearing: bearing >= 0 ? bearing : _mapView.direction,
            visible: true
        )
    }

    private static func loadFlutterAssetURL(
        _ assetPath: String,
        registrar: FlutterPluginRegistrar
    ) -> URL? {
        let key = registrar.lookupKey(forAsset: assetPath)
        return Bundle.main.url(forResource: key, withExtension: nil)
    }

    private static func loadFlutterAssetImage(
        _ assetPath: String,
        registrar: FlutterPluginRegistrar
    ) -> UIImage? {
        let key = registrar.lookupKey(forAsset: assetPath)
        guard let url = Bundle.main.url(forResource: key, withExtension: nil) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }
}
