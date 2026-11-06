// Application delegate managing app lifecycle, background task, and VaultServer initialization.
import UIKit
#if canImport(ExVaultCore)
import ExVaultCore
#endif

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var server: VaultServer?
    let keepAlive = KeepAlive()
    private var bgTaskId: UIBackgroundTaskIdentifier = .invalid

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let win = UIWindow(frame: UIScreen.main.bounds)
        let vc = ViewController(keepAlive: keepAlive, serverProvider: { [weak self] in self?.server })
        win.rootViewController = vc
        win.makeKeyAndVisible()
        self.window = win

        keepAlive.start()

        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak vc] in
            do {
                let fileManager = FileManager.default
                let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dataDir = docs.appendingPathComponent("ExVault")
                try fileManager.createDirectory(at: dataDir, withIntermediateDirectories: true)

                // Exclude data directory from iCloud / iTunes backup
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                var mutableDir = dataDir
                try mutableDir.setResourceValues(values)

                // Locate Web root in bundle resources
                let resourceURL = Bundle.main.resourceURL ?? Bundle.main.bundleURL
                let webRoot = resourceURL.appendingPathComponent("Web")

                let config = VaultConfig(dataDir: dataDir, webRoot: webRoot, port: 8080)
                let srv = try VaultServer(config: config)
                try srv.start()
                self?.server = srv
            } catch {
                Log.error("Server start failure: \(error)")
                DispatchQueue.main.async {
                    vc?.setErrorMessage("\(error)")
                }
            }
        }

        return true
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Log.warn("Application received memory warning")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        bgTaskId = application.beginBackgroundTask(withName: "ExVaultBackground") { [weak self] in
            if let id = self?.bgTaskId, id != .invalid {
                application.endBackgroundTask(id)
                self?.bgTaskId = .invalid
            }
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        if bgTaskId != .invalid {
            application.endBackgroundTask(bgTaskId)
            bgTaskId = .invalid
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        server?.stop()
        keepAlive.stop()
    }
}
