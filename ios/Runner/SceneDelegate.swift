import Flutter
import UIKit

/**
 * SceneDelegate for handling scene-based lifecycle events
 * 
 * Note: Screen protection is primarily handled in AppDelegate,
 * but this class can be extended for scene-specific behaviors.
 */
class SceneDelegate: FlutterSceneDelegate {
    
    override func sceneWillResignActive(_ scene: UIScene) {
        super.sceneWillResignActive(scene)
        // App is about to become inactive (app switcher, etc.)
        // The protection overlay is handled by AppDelegate
    }
    
    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)
        // App is back in foreground
    }
    
    override func sceneDidEnterBackground(_ scene: UIScene) {
        super.sceneDidEnterBackground(scene)
        // App is in background
    }
    
    override func sceneWillEnterForeground(_ scene: UIScene) {
        super.sceneWillEnterForeground(scene)
        // App is coming to foreground
    }
}
