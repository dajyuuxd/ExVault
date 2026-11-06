// Application delegate for iOS application lifecycle.

import UIKit
#if canImport(ExVaultCore)
import ExVaultCore
#endif

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        win.rootViewController = ViewController()
        win.makeKeyAndVisible()
        self.window = win
        return true
    }
}
