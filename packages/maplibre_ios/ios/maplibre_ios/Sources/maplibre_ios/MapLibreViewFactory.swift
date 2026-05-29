import Flutter
import MapLibre
import UIKit

class MapLibreViewFactory: NSObject, FlutterPlatformViewFactory {
    private var _registrar: FlutterPluginRegistrar

    init(withRegistrar registrar: FlutterPluginRegistrar) {
        _registrar = registrar
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        var initStyle = ""
        var locationIconAsset: String?
        var locationSeedLat: Double?
        var locationSeedLon: Double?
        if let dict = args as? [String: Any] {
            initStyle = dict["initStyle"] as? String ?? ""
            locationIconAsset = dict["locationIconAsset"] as? String
            locationSeedLat = dict["locationSeedLat"] as? Double
            locationSeedLon = dict["locationSeedLon"] as? Double
        } else if let style = args as? String {
            initStyle = style
        }
        return MapLibreView(
            registrar: _registrar,
            frame: frame,
            viewId: viewId,
            initStyle: initStyle,
            locationIconAsset: locationIconAsset,
            locationSeedLat: locationSeedLat,
            locationSeedLon: locationSeedLon
        )
    }
}
