import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    private var reconnectOnForeground = false

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Theme.applyAppearance()

        let window = UIWindow(frame: UIScreen.main.bounds)
        if #available(iOS 13.0, *) {
            window.overrideUserInterfaceStyle = .dark
        }
        window.tintColor = Theme.accent
        window.backgroundColor = Theme.background
        window.rootViewController = MainViewController()
        window.makeKeyAndVisible()
        self.window = window

        let settings = AppSettings.shared
        Z21Client.shared.turnoutSwitchTime = settings.turnoutSwitchTime
        application.isIdleTimerDisabled = settings.keepScreenOn
        if settings.autoConnect {
            Z21Client.shared.connect(host: settings.host, port: settings.port)
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Bei der Z21 sauber abmelden; beim Zurückkehren wird neu verbunden
        let client = Z21Client.shared
        reconnectOnForeground = client.connectionState != .disconnected
        if reconnectOnForeground {
            client.disconnect()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        if reconnectOnForeground {
            let settings = AppSettings.shared
            Z21Client.shared.connect(host: settings.host, port: settings.port)
        }
        application.isIdleTimerDisabled = AppSettings.shared.keepScreenOn
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Z21Client.shared.disconnect()
    }
}
