import Flutter
import UIKit

/**
 * SceneDelegate for handling scene-based lifecycle events.
 *
 * Info.plist names this class as `UISceneDelegateClassName`, so the app runs
 * the UIScene life cycle. Under that life cycle UIKit does **not** call
 * `UIApplicationDelegate.applicationWillResignActive(_:)` or
 * `applicationDidBecomeActive(_:)`, and the window is created by the scene
 * rather than being available in `didFinishLaunchingWithOptions` — which is
 * why screen protection has to be driven from here:
 *
 *  * the Dart method/event channels are attached when the scene's
 *    `FlutterViewController` exists (in the app delegate `window` is still nil,
 *    so the channels were never registered at all: no black overlay, no
 *    screenshot or recording events, and `getProtectionStatus` answered with
 *    `MissingPluginException`);
 *  * the black overlay is raised when the scene stops being active, so the
 *    app-switcher snapshot and anything recording the screen see black;
 *  * the capture-proof secure canvas is re-asserted when the scene becomes
 *    active, because the scene is what owns the window it is attached to;
 *  * the real capture state is re-published when the scene becomes active
 *    again, so a capture that started or stopped while the app was away cannot
 *    leave Dart believing the screen is being recorded — which pauses and mutes
 *    every video player.
 */
class SceneDelegate: FlutterSceneDelegate {

    private var protection: ScreenProtectionManager { ScreenProtectionManager.shared }

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        attachScreenProtection()
    }

    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)
        protection.handleAppWillResignActive()
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        attachScreenProtection()
        protection.handleAppDidBecomeActive()
        // The scene owns the window, so re-assert the capture-proof canvas
        // here: a window replaced while the app was away would otherwise be
        // rendering outside it, leaving captures readable.
        protection.reassertSecureCanvas()
    }

    override func sceneDidEnterBackground(_ scene: UIScene) {
        super.sceneDidEnterBackground(scene)
    }

    override func sceneWillEnterForeground(_ scene: UIScene) {
        super.sceneWillEnterForeground(scene)
    }

    /// Attaches the screen-protection channels once the scene has a Flutter
    /// view controller to talk through. Safe to call repeatedly.
    private func attachScreenProtection() {
        guard !protection.isAttached else { return }
        guard let controller = flutterViewController() else { return }
        protection.setupChannels(with: controller.binaryMessenger)
    }

    private func flutterViewController() -> FlutterViewController? {
        if let controller = window?.rootViewController as? FlutterViewController {
            return controller
        }
        return window?.rootViewController?.children.compactMap { $0 as? FlutterViewController }.first
    }
}
