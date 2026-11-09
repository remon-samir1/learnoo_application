import Flutter
import UIKit
import Combine
import UserNotifications

/**
 * AppDelegate with Extreme Screen Protection for iOS
 */
@main
@objc class AppDelegate: FlutterAppDelegate {
    
    private var screenProtection: ScreenProtectionManager { ScreenProtectionManager.shared }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        // flutter_local_notifications: show student notifications while the
        // app is in the foreground and deliver taps to Dart.
        UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

        // `window` is nil here when the app runs the UIScene life cycle, which
        // it does: Info.plist names `SceneDelegate` as UISceneDelegateClassName
        // and the window is created by the scene, after this method. The
        // channels are therefore attached from the scene as well
        // (`SceneDelegate.attachScreenProtection`); this call only covers a
        // launch without a scene.
        attachScreenProtection()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func attachScreenProtection() {
        if let controller = window?.rootViewController as? FlutterViewController {
            screenProtection.setupChannels(with: controller.binaryMessenger)
        }
    }

    override func applicationWillResignActive(_ application: UIApplication) {
        super.applicationWillResignActive(application)
        screenProtection.handleAppWillResignActive()
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        super.applicationDidBecomeActive(application)
        screenProtection.handleAppDidBecomeActive()
    }
}

class ScreenProtectionManager: NSObject {
    /// One manager for the process: both the app delegate and the scene
    /// delegate drive it, and only one of them owns the window.
    static let shared = ScreenProtectionManager()

    private let methodChannelName = "com.learnoo.screen_protection"
    private let eventChannelName = "com.learnoo.screen_protection/events"

    private var methodChannel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?

    /// Last value reported to Dart, so only a real transition is sent. Dart
    /// pauses and mutes every video player while capture is on, so a repeated
    /// or stale `recording_started` is what stops a lecture a few seconds in.
    private var lastReportedCaptured: Bool?

    // Dashboard policy ("Block Screenshots & Recording"), persisted so it
    // applies on cold start before Dart runs. Defaults to protected.
    private static let policyDefaultsKey = "learnoo_global_protection_enabled"
    private var isGlobalEnabled: Bool = {
        UserDefaults.standard.object(forKey: ScreenProtectionManager.policyDefaultsKey) as? Bool ?? true
    }()
    private var protectionWindow: UIWindow?
    private var cancellables = Set<AnyCancellable>()

    /// Renders the app inside a secure text field's canvas, which iOS leaves
    /// out of screenshots, recordings, AirPlay and mirroring. This is the
    /// iOS counterpart of Android's `FLAG_SECURE`; it is an addition to the
    /// detection below, never a replacement (see `SecureCanvasController`).
    private let secureCanvas = SecureCanvasController()

    /// Debug builds only: Dart reports `screenCaptureAllowed` (`kDebugMode`)
    /// with every policy push, and the secure canvas is then skipped, matching
    /// Android, which skips `FLAG_SECURE` in debuggable builds so the app can
    /// be screen-recorded for the store listings. Defaults to `false`, so a
    /// build that never reports stays protected. Detection and the black
    /// overlay are untouched by this - exactly as they are today.
    private var allowCaptureForDebugBuild = false

    /// Whether Dart has asked for protection at least once, so the canvas can
    /// be re-asserted when the scene (and therefore the window) changes.
    private var secureCanvasRequested = false
    
    /// Whether the Dart channels are already attached.
    var isAttached: Bool { methodChannel != nil }

    func setupChannels(with messenger: FlutterBinaryMessenger) {
        // Both delegates try; the first one with a window wins.
        guard methodChannel == nil else { return }
        methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }
        
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)
        eventChannel.setStreamHandler(self)
        
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // `UIScreen.main.isCaptured` and the Flutter event sink are both
        // main-thread-only, and these notifications are not guaranteed to be
        // delivered there.
        NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.handleCapturedDidChange() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.sendEvent(name: "screenshot") }
            .store(in: &cancellables)
    }
    
    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enableGlobalProtection":
            readDebugBuildFlag(from: call)
            setGlobalEnabled(true)
            result(true)
        case "disableGlobalProtection":
            readDebugBuildFlag(from: call)
            setGlobalEnabled(false)
            result(true)
        case "isJailbroken":
            result(isJailbroken())
        case "isScreenRecording":
            result(UIScreen.main.isCaptured)
        case "getProtectionStatus":
            result([
                "isGlobalEnabled": isGlobalEnabled,
                "isRecording": UIScreen.main.isCaptured,
                "isJailbroken": isJailbroken(),
                // Diagnostics: whether the capture-proof canvas is in place, or
                // whether the app fell back to detection + overlay only.
                "isSecureCanvasActive": secureCanvas.isIntact,
                "didSecureCanvasFallBack": secureCanvas.didFallBack
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Dart sends `allowCapture` (its `screenCaptureAllowed`, i.e. `kDebugMode`)
    /// with every policy push. A call without it leaves the current value
    /// alone, so protection never relaxes because of a missing argument.
    private func readDebugBuildFlag(from call: FlutterMethodCall) {
        guard let arguments = call.arguments as? [String: Any],
              let allowCapture = arguments["allowCapture"] as? Bool else { return }
        allowCaptureForDebugBuild = allowCapture
    }

    private func setGlobalEnabled(_ enabled: Bool) {
        isGlobalEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: ScreenProtectionManager.policyDefaultsKey)
        secureCanvasRequested = enabled
        syncSecureCanvas()
        if !enabled {
            hideBlackOverlay()
        } else if UIScreen.main.isCaptured {
            showBlackOverlay()
        }
    }

    /// Matches the secure canvas to the dashboard policy.
    ///
    /// Turning the policy off removes it, which gives back a completely normal,
    /// capturable app. Nothing here can throw or leave the app unrendered: when
    /// the canvas cannot be installed the app keeps rendering the way it does
    /// today and the student is still covered by capture detection, the black
    /// overlay and the paused/muted players.
    private func syncSecureCanvas() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.isGlobalEnabled, !self.allowCaptureForDebugBuild else {
                self.secureCanvas.remove()
                return
            }
            guard let window = self.appWindow() else { return }
            self.secureCanvas.apply(to: window)
        }
    }

    /// Re-applies the secure canvas after the scene life cycle may have
    /// replaced the window. Does nothing until Dart has pushed the policy.
    func reassertSecureCanvas() {
        guard secureCanvasRequested else { return }
        syncSecureCanvas()
    }

    private func handleCapturedDidChange() {
        publishCaptureState(force: false)
    }

    /// Reports the screen's real capture state to Dart and matches the overlay
    /// to it.
    ///
    /// Only a change is reported. Re-sending `recording_started` for a state
    /// Dart already knows about re-pauses and re-mutes every video player, and
    /// the balancing `recording_stopped` only ever arrives from a
    /// `capturedDidChange` — so a duplicated or stale "started" left lectures
    /// unplayable. Always reports the current value, never a remembered one, so
    /// a notification missed while the app was in the background is corrected
    /// the next time the app becomes active.
    private func publishCaptureState(force: Bool) {
        let isCaptured = UIScreen.main.isCaptured
        if isCaptured {
            // Events are still sent; Dart ignores them when the dashboard
            // policy is off. The native overlay follows the policy.
            if isGlobalEnabled { showBlackOverlay() }
        } else {
            hideBlackOverlay()
        }
        guard force || lastReportedCaptured != isCaptured else { return }
        lastReportedCaptured = isCaptured
        sendEvent(name: isCaptured ? "recording_started" : "recording_stopped")
    }
    
    private func showBlackOverlay() {
        DispatchQueue.main.async {
            guard self.protectionWindow == nil else { return }
            
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

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
            guard let overlay = self.protectionWindow else { return }
            overlay.isHidden = true
            self.protectionWindow = nil
            // Hand key status back to the app's own window. The overlay was
            // made key when it appeared, and destroying a key window without
            // naming a successor leaves the app without one.
            self.appWindow()?.makeKeyAndVisible()
            // Making a window key and visible can put its layer back under the
            // scene's host layer, which would undo the secure canvas; re-assert
            // it (a no-op when it is still intact).
            self.reassertSecureCanvas()
        }
    }

    /// The app's own (Flutter) window, as opposed to the protection overlay.
    private func appWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { $0 !== protectionWindow }
        return windows.first { $0.rootViewController is FlutterViewController } ?? windows.first
    }
    
    func handleAppWillResignActive() {
        if isGlobalEnabled {
            showBlackOverlay()
        }
    }
    
    func handleAppDidBecomeActive() {
        // Re-reads the screen rather than trusting the last event: a capture
        // that started or stopped while the app was not active produces no
        // notification the app can see, and a believed-but-finished capture
        // would otherwise keep every lecture paused and muted.
        publishCaptureState(force: false)
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
    
    /// Flutter event sinks may only be used from the platform thread.
    private func sendEvent(name: String) {
        if Thread.isMainThread {
            eventSink?(["event": name])
        } else {
            DispatchQueue.main.async { [weak self] in self?.eventSink?(["event": name]) }
        }
    }
}

extension ScreenProtectionManager: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // Tell Dart the state the screen is in right now, so capture that was
        // already running before Dart subscribed pauses and mutes the players,
        // and so a subscription made while nothing is being captured starts
        // from a known "clear" instead of whatever Dart assumed.
        lastReportedCaptured = nil
        DispatchQueue.main.async { [weak self] in
            self?.publishCaptureState(force: true)
        }
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

/// Makes the app's own pixels unavailable to iOS capture.
///
/// iOS has no API that blocks a screenshot the way Android's `FLAG_SECURE`
/// does, but it does exclude the rendering canvas of a secure text field
/// (`isSecureTextEntry = true`) from screenshots, screen recordings, AirPlay
/// and mirroring. This controller builds such a field, finds the canvas the
/// field renders itself into, and re-parents the app window's layer into it,
/// so everything the app draws is composited inside the excluded subtree: the
/// student's screenshot and recording come out blank/black.
///
/// Only the **layer** is re-parented, not the views. The view hierarchy stays
/// exactly as Flutter built it (window -> FlutterViewController.view -> ...),
/// because UIKit hit-testing and first-responder/keyboard handling walk views:
/// making the Flutter view a *subview* of a `UITextField` would route every
/// touch through that control and break input. CALayer rendering is
/// independent of that, so moving the layer changes what is composited
/// without changing what is touchable.
///
/// Everything here is defensive. The canvas is located by inspecting the
/// field's own subviews at runtime; no private class name is required. If the
/// hierarchy is not what is expected - or any invariant fails after the
/// move - the controller undoes everything and reports failure, and the app
/// falls back to the existing behaviour (capture detection, black overlay,
/// players paused and muted). It never leaves the app blank or unrendered.
final class SecureCanvasController {

    /// The window whose layer is currently re-parented.
    private weak var protectedWindow: UIWindow?
    /// The secure field; retained by the window as a subview, kept here too.
    private var secureField: UITextField?
    /// The field's own rendering canvas, now hosting the window layer.
    private var canvasLayer: CALayer?
    /// Where the window layer lived before. Held strongly on purpose: the undo
    /// path must be able to put the window layer back even if UIKit would
    /// otherwise have released this layer, because a window whose layer has no
    /// superlayer renders nothing.
    private var hostLayer: CALayer?
    /// The window layer's original z-position among its siblings.
    private var hostIndex: UInt32 = 0

    /// Whether the app window is currently rendering inside the secure canvas.
    private(set) var isActive = false

    /// Whether the last attempt failed and the app is relying on detection
    /// plus the black overlay instead. Reported through `getProtectionStatus`
    /// so this can be checked on a device.
    private(set) var didFallBack = false

    /// Points of slack allowed between the canvas and the window it must cover.
    private static let tolerance: CGFloat = 2.0

    /// Whether the app window is still rendering inside the canvas.
    ///
    /// UIKit can move a window's layer back under the scene's own host layer -
    /// `makeKeyAndVisible()` is one way - which would silently leave the app
    /// capturable again. `apply(to:)` re-installs the canvas when this is
    /// false, so re-asserting it is self-healing.
    var isIntact: Bool {
        guard isActive, let window = protectedWindow, let canvas = canvasLayer else { return false }
        return window.layer.superlayer === canvas && secureField?.superview === window
    }

    // MARK: - Apply

    /// Re-parents `window`'s layer into a secure canvas.
    ///
    /// - Returns: `true` when the window now renders inside the secure canvas,
    ///   `false` when nothing was changed (or everything was undone) and the
    ///   caller must rely on detection + overlay.
    @discardableResult
    func apply(to window: UIWindow) -> Bool {
        return apply(to: window, allowRetry: true)
    }

    @discardableResult
    private func apply(to window: UIWindow, allowRetry: Bool) -> Bool {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.apply(to: window, allowRetry: allowRetry) }
            return false
        }
        if isActive, protectedWindow === window, isIntact { return true }
        if isActive { remove() }

        // The window has to be in the render tree already: its layer's parent
        // is what the secure field's layer takes the place of.
        guard let host = window.layer.superlayer else {
            // Not in the render tree yet (a window still being attached); try
            // again on the next turn of the run loop.
            if allowRetry {
                DispatchQueue.main.async { [weak self] in
                    self?.apply(to: window, allowRetry: false)
                }
                return false
            }
            didFallBack = true
            return false
        }

        let field = makeSecureField()
        window.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: window.topAnchor),
            field.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            field.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])
        // Force the field to build and lay out its internal canvas.
        window.layoutIfNeeded()

        guard let canvas = SecureCanvasController.canvasView(of: field, covering: window) else {
            field.removeFromSuperview()
            // The field builds its canvas lazily, so one layout pass may not be
            // enough on a window that is still settling (launch, rotation).
            // Try once more on the next turn of the run loop before giving up
            // and leaving the student to detection + overlay.
            if allowRetry {
                DispatchQueue.main.async { [weak self] in
                    self?.apply(to: window, allowRetry: false)
                }
                return false
            }
            didFallBack = true
            return false
        }

        let index = SecureCanvasController.index(of: window.layer, in: host)

        // Put the field's layer exactly where the window's layer was, so the
        // z-order against other windows (keyboard, the protection overlay) is
        // unchanged, then nest the window's layer inside the canvas.
        if let index = index {
            host.insertSublayer(field.layer, at: index)
        } else {
            host.addSublayer(field.layer)
        }
        canvas.layer.addSublayer(window.layer)

        protectedWindow = window
        secureField = field
        canvasLayer = canvas.layer
        hostLayer = host
        hostIndex = index ?? UInt32(max(0, (host.sublayers?.count ?? 1) - 1))
        isActive = true

        // Everything must be exactly as intended; anything else is undone
        // rather than risking a blank or shifted app.
        guard window.layer.superlayer === canvas.layer,
              field.layer.superlayer === host else {
            remove()
            didFallBack = true
            return false
        }

        didFallBack = false
        return true
    }

    private func makeSecureField() -> UITextField {
        let field = UITextField()
        field.isSecureTextEntry = true
        // The field exists only to lend its canvas: it must never take a
        // touch, become first responder or bring up a keyboard. Its own views
        // stay in the window, above the Flutter view, so interaction is off.
        field.isUserInteractionEnabled = false
        field.isAccessibilityElement = false
        field.backgroundColor = .clear
        field.textColor = .clear
        field.tintColor = .clear
        field.borderStyle = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    // MARK: - Remove

    /// Puts the window's layer back where it was and tears the field down.
    ///
    /// Safe to call at any time, including when nothing was applied.
    func remove() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.remove() }
            return
        }
        defer {
            secureField = nil
            canvasLayer = nil
            hostLayer = nil
            hostIndex = 0
            protectedWindow = nil
            isActive = false
        }
        guard isActive else { return }

        if let window = protectedWindow {
            if window.layer.superlayer === canvasLayer {
                window.layer.removeFromSuperlayer()
            }
            if let host = hostLayer, window.layer.superlayer == nil {
                let count = UInt32(host.sublayers?.count ?? 0)
                host.insertSublayer(window.layer, at: min(hostIndex, count))
            }
            window.setNeedsLayout()
        }
        secureField?.layer.removeFromSuperlayer()
        secureField?.removeFromSuperview()
    }

    // MARK: - Canvas discovery

    /// Finds the view a secure text field renders itself into.
    ///
    /// No private class name is relied on. Views that are plainly something
    /// else (controls, labels, image and scroll views) are discarded, then the
    /// remaining candidate has to actually cover the window, otherwise the app
    /// would render offset or clipped once nested inside it. A name containing
    /// "canvas" is used only as a preference between candidates, never as a
    /// requirement.
    private static func canvasView(of field: UITextField, covering window: UIWindow) -> UIView? {
        let candidates = field.subviews.filter { isPlainContainer($0) && covers(window, $0) }
        if let named = candidates.first(where: {
            String(describing: type(of: $0)).lowercased().contains("canvas")
        }) {
            return named
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    private static func isPlainContainer(_ view: UIView) -> Bool {
        if view is UIControl { return false }
        if view is UILabel || view is UIImageView || view is UIScrollView { return false }
        if view is UIStackView || view is UIVisualEffectView { return false }
        if view.isHidden { return false }
        return true
    }

    /// Whether `view` lines up with the window's own frame, within a point.
    private static func covers(_ window: UIWindow, _ view: UIView) -> Bool {
        let originInWindow = view.convert(view.bounds.origin, to: window)
        guard abs(originInWindow.x) <= tolerance, abs(originInWindow.y) <= tolerance else {
            return false
        }
        let size = view.bounds.size
        let target = window.bounds.size
        return abs(size.width - target.width) <= tolerance
            && abs(size.height - target.height) <= tolerance
    }

    private static func index(of layer: CALayer, in host: CALayer) -> UInt32? {
        guard let position = host.sublayers?.firstIndex(where: { $0 === layer }) else { return nil }
        return UInt32(position)
    }
}
