import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String,
       !mapsApiKey.isEmpty,
       !mapsApiKey.contains("$(") {
      GMSServices.provideAPIKey(mapsApiKey)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let mapsConfigChannel = FlutterMethodChannel(
      name: "citiride/google_maps_config",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    mapsConfigChannel.setMethodCallHandler { call, result in
      guard call.method == "apiKey" else {
        result(FlutterMethodNotImplemented)
        return
      }

      let apiKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String
      result(apiKey)
    }
  }
}
