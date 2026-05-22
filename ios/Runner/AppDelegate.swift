import Flutter
import UIKit
import Combine

/**
 * AppDelegate with Extreme Screen Protection for iOS
 */
@main
@objc class AppDelegate: FlutterAppDelegate {
    
    private var screenProtection: ScreenProtectionManager?
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        screenProtection = ScreenProtectionManager()
        if let controller = window?.rootViewController as? FlutterViewController {
            screenProtection?.setupChannels(with: controller.binaryMessenger)
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    override func applicationWillResignActive(_ application: UIApplication) {
        super.applicationWillResignActive(application)
        screenProtection?.handleAppWillResignActive()
    }
    
    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        screenProtection?.handleAppDidBecomeActive()
    }
}

class ScreenProtectionManager: NSObject {
    private let methodChannelName = "com.learnoo.screen_protection"
    private let eventChannelName = "com.learnoo.screen_protection/events"
    
    private var methodChannel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?
    
    private var isGlobalEnabled = true
    private var protectionWindow: UIWindow?
    private var cancellables = Set<AnyCancellable>()
    
    func setupChannels(with messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
        
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
        eventChannel.setStreamHandler(self)
        
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
            .sink { [weak self] _ in self?.handleCapturedDidChange() }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .sink { [weak self] _ in self?.sendEvent(name: "screenshot") }
            .store(in: &cancellables)
    }
    
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enableGlobalProtection":
            isGlobalEnabled = true
            result(true)
        case "disableGlobalProtection":
            isGlobalEnabled = false
            result(true)
        case "isJailbroken":
            result(isJailbroken())
        case "isScreenRecording":
            result(UIScreen.main.isCaptured)
        case "getProtectionStatus":
            result([
                "isGlobalEnabled": isGlobalEnabled,
                "isRecording": UIScreen.main.isCaptured,
                "isJailbroken": isJailbroken()
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleCapturedDidChange() {
        let isCaptured = UIScreen.main.isCaptured
        if isCaptured {
            showBlackOverlay()
            sendEvent(name: "recording_started")
        } else {
            hideBlackOverlay()
            sendEvent(name: "recording_stopped")
        }
    }
    
    private func showBlackOverlay() {
        DispatchQueue.main.async {
            guard self.protectionWindow == nil else { return }
            
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            
            if let windowScene = windowScene {
                let window = UIWindow(windowScene: windowScene)
                window.windowLevel = .statusBar + 1
                window.backgroundColor = .black
                
                let label = UILabel()
                label.text = "CONTENT PROTECTED"
                label.textColor = .white
                label.textAlignment = .center
                label.font = UIFont.boldSystemFont(ofSize: 20)
                label.translatesAutoresizingMaskIntoConstraints = false
                
                window.addSubview(label)
                NSLayoutConstraint.activate([
                    label.centerXAnchor.constraint(equalTo: window.centerXAnchor),
                    label.centerYAnchor.constraint(equalTo: window.centerYAnchor)
                ])
                
                window.makeKeyAndVisible()
                self.protectionWindow = window
            }
        }
    }
    
    private func hideBlackOverlay() {
        DispatchQueue.main.async {
            self.protectionWindow?.isHidden = true
            self.protectionWindow = nil
        }
    }
    
    func handleAppWillResignActive() {
        if isGlobalEnabled {
            showBlackOverlay()
        }
    }
    
    func handleAppDidBecomeActive() {
        if !UIScreen.main.isCaptured {
            hideBlackOverlay()
        }
    }
    
    private func isJailbroken() -> Bool {
        if TARGET_OS_SIMULATOR != 0 { return false }
        
        let fileManager = FileManager.default
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/"
        ]
        
        for path in jailbreakPaths {
            if fileManager.fileExists(atPath: path) { return true }
        }
        
        return false
    }
    
    private func sendEvent(name: String) {
        eventSink?(["event": name])
    }
}

extension ScreenProtectionManager: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
