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

    /// Whether the app should be rendering inside the secure canvas.
    private var wantsSecureCanvas: Bool { isGlobalEnabled && !allowCaptureForDebugBuild }

    /// Hosts the scene's Flutter view inside the secure canvas. Called by the
    /// scene delegate once the window exists; uses the persisted policy, so a
    /// cold start is protected before Dart runs.
    func installSecureCanvas(in window: UIWindow) {
        secureCanvas.install(in: window, protected: wantsSecureCanvas)
    }

    /// Matches the secure canvas to the dashboard policy.
    ///
    /// Turning the policy off gives back a completely normal, capturable app.
    /// When the canvas cannot be used the app keeps rendering normally and the
    /// student is still covered by capture detection, the black overlay and
    /// the paused/muted players.
    private func syncSecureCanvas() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.secureCanvas.setProtected(self.wantsSecureCanvas)
        }
    }

    /// Re-applies the policy when the scene becomes active again. Does nothing
    /// until Dart has pushed the policy.
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
        }
    }

    /// The app's own (Flutter) window, as opposed to the protection overlay.
    private func appWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { $0 !== protectionWindow }
        return windows.first {
            $0.rootViewController is SecureContainerViewController
                || $0.rootViewController is FlutterViewController
        } ?? windows.first
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
        #if targetEnvironment(simulator)
        return false
        #else
        
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
        #endif
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
/// does, but it leaves the rendering canvas of a secure text field
/// (`isSecureTextEntry = true`) out of screenshots, screen recordings, AirPlay
/// and mirroring. The Flutter view is therefore hosted *inside* that canvas:
///
///     window
///       └ SecureContainerViewController.view
///           └ SecureHostField (UITextField, full screen)
///               └ the field's canvas view        ← excluded from capture
///                   └ FlutterViewController.view
///
/// The Flutter view is moved as a **view**, with UIKit's own `addSubview`, so
/// the view tree and the layer tree always agree. (Moving only the window's
/// layer under a subview of that same window made them disagree, and UIKit
/// crashed in its next layout pass at launch.)
///
/// Protection is switched by flipping `isSecureTextEntry`; nothing is torn
/// down. When the canvas cannot be found the Flutter view is hosted in the
/// field itself: the app works exactly as before and stays covered by capture
/// detection, the black overlay and the paused/muted players.
final class SecureCanvasController {
    private weak var container: SecureContainerViewController?
    private var wantsProtection = false

    /// Whether the Flutter view is rendering inside the secure canvas now.
    var isIntact: Bool { container?.isSecureCanvasActive ?? false }

    /// Whether protection was asked for but the canvas could not be used.
    var didFallBack: Bool { wantsProtection && container != nil && !isIntact }

    /// Wraps the window's `FlutterViewController` in the secure container.
    /// Safe to call repeatedly; does nothing for any other root.
    func install(in window: UIWindow, protected: Bool) {
        wantsProtection = protected
        if let existing = window.rootViewController as? SecureContainerViewController {
            container = existing
            existing.setProtected(protected)
            return
        }
        guard let flutter = window.rootViewController as? FlutterViewController else { return }
        let wrapper = SecureContainerViewController(content: flutter)
        window.rootViewController = wrapper
        container = wrapper
        wrapper.setProtected(protected)
    }

    func setProtected(_ protected: Bool) {
        wantsProtection = protected
        container?.setProtected(protected)
    }
}

/// Root view controller that hosts Flutter inside a secure text field.
///
/// Everything UIKit asks the root about (status bar, home indicator, edge
/// gestures, orientations) is answered by the Flutter view controller.
final class SecureContainerViewController: UIViewController {
    let content: UIViewController
    private let field = SecureHostField()

    init(content: UIViewController) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var isSecureCanvasActive: Bool { isViewLoaded && field.isHostedInSecureCanvas }

    override func loadView() {
        let root = UIView()
        root.backgroundColor = .black
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        field.frame = view.bounds
        field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(field)
        addChild(content)
        field.host(content.view)
        content.didMove(toParent: self)
    }

    func setProtected(_ protected: Bool) {
        loadViewIfNeeded()
        field.setProtected(protected)
    }

    override var childForStatusBarStyle: UIViewController? { content }
    override var childForStatusBarHidden: UIViewController? { content }
    override var childForHomeIndicatorAutoHidden: UIViewController? { content }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { content }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        content.supportedInterfaceOrientations
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        content.preferredInterfaceOrientationForPresentation
    }
    override var shouldAutorotate: Bool { content.shouldAutorotate }
}

/// A secure text field used only for its capture-proof canvas.
///
/// It never edits, never becomes first responder and never shows a keyboard.
/// Touches and accessibility go straight to the hosted Flutter view, and the
/// field's own gesture recognizers are refused, so it behaves as a plain
/// pass-through container.
final class SecureHostField: UITextField {
    private weak var hostedView: UIView?
    private(set) var isHostedInSecureCanvas = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        borderStyle = .none
        backgroundColor = .clear
        textColor = .clear
        tintColor = .clear
        autocorrectionType = .no
        spellCheckingType = .no
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var canBecomeFirstResponder: Bool { false }
    override var canBecomeFocused: Bool { false }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        recognizer.view === self ? false : super.gestureRecognizerShouldBegin(recognizer)
    }

    /// Hit-tests the hosted view directly. The canvas may be smaller than the
    /// screen; going through it would drop touches outside its bounds.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hosted = hostedView, !isHidden, isUserInteractionEnabled, alpha > 0.01 else {
            return nil
        }
        return hosted.hitTest(convert(point, to: hosted), with: event)
    }

    override var accessibilityElements: [Any]? {
        get { hostedView.map { [$0] } }
        set {}
    }

    func host(_ view: UIView) {
        hostedView = view
        placeHostedView()
    }

    func setProtected(_ protected: Bool) {
        if isSecureTextEntry != protected { isSecureTextEntry = protected }
        setNeedsLayout()
        layoutIfNeeded()
        placeHostedView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeHostedView()
    }

    /// Keeps the hosted view in the secure canvas when protected, otherwise in
    /// the field itself, always on top and always covering the field exactly.
    private func placeHostedView() {
        guard let hosted = hostedView else { return }
        let canvas = isSecureTextEntry ? secureCanvas(excluding: hosted) : nil
        let target: UIView = canvas ?? self
        if hosted.superview !== target {
            target.addSubview(hosted)
        } else if target.subviews.last !== hosted {
            target.bringSubviewToFront(hosted)
        }
        let frame = target.convert(bounds, from: self)
        if hosted.frame != frame { hosted.frame = frame }
        isHostedInSecureCanvas = canvas != nil
    }

    /// The view the secure field renders its text into.
    ///
    /// No private class name is required: controls, labels, image/scroll views
    /// and anything that clips are ruled out (a clipping canvas would cut the
    /// app off). A name containing "canvas" only breaks a tie.
    private func secureCanvas(excluding hosted: UIView) -> UIView? {
        let candidates = subviews.filter { view in
            view !== hosted
                && !view.isHidden
                && !(view is UIControl || view is UILabel || view is UIImageView
                     || view is UIScrollView || view is UIStackView || view is UIVisualEffectView)
                && !view.clipsToBounds
                && !view.layer.masksToBounds
        }
        if let named = candidates.first(where: {
            String(describing: type(of: $0)).lowercased().contains("canvas")
        }) {
            return named
        }
        return candidates.count == 1 ? candidates.first : nil
    }
}
