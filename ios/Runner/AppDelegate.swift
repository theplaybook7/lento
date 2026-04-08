import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 13.0, *) {
      WorkmanagerPlugin.registerPeriodicTask(
        withIdentifier: "payment_check",
        frequency: NSNumber(value: 15 * 60)
      )
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
