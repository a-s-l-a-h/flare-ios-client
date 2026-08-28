import UIKit
import DivKit

public class FlareClientViewController: UIViewController, FlareDivActionCallback {

    private final class Mount {
        let region: String
        let container: UIView
        var channel: PhoenixChannelClient.PhoenixChannel?
        var screenName: String?
        var divView: DivView?
        var pendingActions = Set<String>()
        var cachedLayoutJson: [String: Any]?

        init(region: String, container: UIView) {
            self.region = region
            self.container = container
        }
    }

    private struct BackStackEntry {
        let screenName: String
        let params: [String: Any]?
    }

    public static var EXTRA_WS_URL = "flare_ws_url"
    public static var EXTRA_ENTRY_SCREEN = "flare_entry_screen"
    public static var EXTRA_TOKEN = "flare_token"
    public static var EXTRA_ENTRY_PARAMS = "flare_entry_params"

    private let PREF_TOKEN = "flare_auth_token"
    private let PREF_DARK_MODE = "local_dark_mode"
    public static let PENDING_VAR = "local_flare_pending"

    private static let COLOR_BG_LIGHT = UIColor(red: 244/255, green: 245/255, blue: 249/255, alpha: 1)
    private static let COLOR_BG_DARK  = UIColor(red: 14/255, green: 14/255, blue: 20/255, alpha: 1)

    private var contentMount: Mount!
    private var persistentMounts = [String: Mount]()
    private let ACTIVE_SCAFFOLD_REGIONS = ["bottom_bar"]

    private var socket: PhoenixChannelClient.PhoenixSocket?
    public var wsUrl: String = ""
    public var entryScreen: String = "home"
    public var entryParams: [String: Any]?
    public var initialToken: String?

    private var currentContentScreen: String?
    private var currentContentParams: [String: Any]?
    private var backStack = [BackStackEntry]()
    private var initializedLocalVars = Set<String>()
    private var exportedVariableNames = Set<String>()

    private var hasEverLoadedContent = false
    private var isResumingFromBackground = false
    private var reconnectFailureStreak = 0
    private var contentJoinFailureStreak = 0

    private var transitionOverlay = TransitionOverlayView()
    private var ambientIsland = AmbientIslandView()

    private var divKitComponents: DivKitComponents!
    private var clientPluginEngine: FlareClientPluginEngine!
    private var variablesStorage: DivVariablesStorage!

    private var cachedConnectionLostLayoutJson: [String: Any]?
    private var connectionLostLayoutLoadAttempted = false
    private var cachedScreenErrorLayoutJson: [String: Any]?
    private var screenErrorLayoutLoadAttempted = false

    public static func launch(from presenter: UIViewController, wsUrl: String, entryScreen: String, token: String? = nil, entryParams: [String: Any]? = nil) {
        let vc = FlareClientViewController()
        vc.wsUrl = wsUrl
        vc.entryScreen = entryScreen
        vc.initialToken = token
        vc.entryParams = entryParams
        vc.modalPresentationStyle = .fullScreen
        presenter.present(vc, animated: true)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupDivKit()
        setupGestures()
        setupLifecycleObservers()
        buildAndConnectSocket(entryScreen: entryScreen)
    }

    private func setupUI() {
        let isDarkMode = UserDefaults.standard.bool(forKey: PREF_DARK_MODE)
        let bgColor = isDarkMode ? Self.COLOR_BG_DARK : Self.COLOR_BG_LIGHT
        view.backgroundColor = bgColor

        let mainContainer = UIView()
        mainContainer.translatesAutoresizingMaskIntoConstraints = false
        mainContainer.backgroundColor = bgColor
        view.addSubview(mainContainer)

        let flContent = UIView()
        flContent.translatesAutoresizingMaskIntoConstraints = false
        flContent.backgroundColor = bgColor
        mainContainer.addSubview(flContent)

        let flBottomBar = UIView()
        flBottomBar.translatesAutoresizingMaskIntoConstraints = false
        flBottomBar.backgroundColor = bgColor
        mainContainer.addSubview(flBottomBar)

        ambientIsland.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ambientIsland)

        transitionOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transitionOverlay)

        NSLayoutConstraint.activate([
            mainContainer.topAnchor.constraint(equalTo: view.topAnchor),
            mainContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            flContent.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            flContent.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            flContent.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            flContent.bottomAnchor.constraint(equalTo: flBottomBar.topAnchor),

            flBottomBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            flBottomBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            flBottomBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            flBottomBar.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            ambientIsland.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            ambientIsland.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            transitionOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            transitionOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            transitionOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transitionOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        contentMount = Mount(region: "content", container: flContent)
        persistentMounts["bottom_bar"] = Mount(region: "bottom_bar", container: flBottomBar)

        transitionOverlay.ambientIsland = ambientIsland
        transitionOverlay.onSignOut = { [weak self] in self?.clearStorage() }
        transitionOverlay.onErrorShown = { [weak self] in self?.hideScaffold("bottom_bar") }
        transitionOverlay.onErrorHidden = { [weak self] in self?.showScaffold("bottom_bar") }
        ambientIsland.setupInitialHeroState()
    }

    private func setupGestures() {
        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleScreenEdgePan(_:)))
        edgePan.edges = .left
        view.addGestureRecognizer(edgePan)
    }

    @objc private func handleScreenEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        if recognizer.state == .ended {
            handleBack()
        }
    }

    private func setupDivKit() {
        variablesStorage = DivVariablesStorage()
        let isDarkMode = UserDefaults.standard.bool(forKey: PREF_DARK_MODE)
        variablesStorage.set(
            variables: [
                DivVariableName(rawValue: FlareClientViewController.PENDING_VAR): .bool(false),
                DivVariableName(rawValue: "local_dark_mode"): .bool(isDarkMode)
            ],
            triggerUpdate: false
        )
        initializedLocalVars.insert("local_dark_mode")

        let actionHandler = FlareDivActionHandler(callback: self)
        let paneContext = NativePaneContextImpl(controller: self)
        let customBlockFactory = FlareNativePaneAdapter(paneContext: paneContext)

        divKitComponents = DivKitComponents(
            divCustomBlockFactory: customBlockFactory,
            urlHandler: actionHandler,
            variablesStorage: variablesStorage
        )

        let pluginContext = PluginContextImpl(controller: self)
        clientPluginEngine = FlareClientPluginEngine(
            host: self,
            variablesStorage: variablesStorage,
            context: pluginContext,
            livenessCheck: { [weak self] screenName in
                guard let self = self else { return false }
                return screenName == self.contentMount.screenName || self.persistentMounts[screenName] != nil
            },
            actionFirer: { [weak self] actionName, originScreen in
                guard let self = self else { return }
                var target = self.contentMount!
                if let origin = originScreen, origin != self.contentMount.screenName, let m = self.persistentMounts[origin] {
                    target = m
                }
                self.handleResolvedAction(eventType: actionName, payload: ["flare_action": actionName], sourceMount: target)
            }
        )
    }

    private func buildAndConnectSocket(entryScreen: String) {
        if let token = initialToken {
            UserDefaults.standard.set(token, forKey: PREF_TOKEN)
        }
        let storedToken = UserDefaults.standard.string(forKey: PREF_TOKEN)

        var builder = PhoenixChannelClient.PhoenixSocket.Builder(endpointBase: wsUrl)
            .timeout(10_000)
            .heartbeatIntervalMs(30_000)
            .decoder(FlareMessageDecoder())

        if let token = storedToken {
            builder = builder.param(key: "token", value: token)
        }

        socket = builder.build()

        _ = socket?.onOpen { [weak self] in
            guard let self = self else { return }
            self.reconnectFailureStreak = 0
            DispatchQueue.main.async {
                self.joinPersistentScreens()
                if self.transitionOverlay.isVisible && self.hasEverLoadedContent {
                    self.retryCurrentScreen()
                } else if self.transitionOverlay.isVisible {
                    self.transitionOverlay.show(onRetry: { [weak self] in self?.retryCurrentScreen() })
                    self.retryCurrentScreen()
                }
            }
        }

        _ = socket?.onClose { [weak self] code, _ in
            DispatchQueue.main.async {
                self?.clearAllPendingActions()
                if code != 1000 { self?.handleConnectionFailure("Connection lost. Reconnecting…") }
            }
        }

        _ = socket?.onError { [weak self] _ in
            DispatchQueue.main.async {
                self?.clearAllPendingActions()
                self?.handleConnectionFailure("Connection error. Please check your network.")
            }
        }

        socket?.connect()
        navigateTo(screenName: entryScreen, params: entryParams)
    }

    public func navigateTo(screenName: String, params: [String: Any]? = nil) {
        if let currentChan = contentMount.channel {
            currentChan.leave()
            contentMount.channel = nil
        }
        clearPendingForMount(contentMount)

        transitionOverlay.resetFallback()
        transitionOverlay.show(onRetry: { [weak self] in self?.retryCurrentScreen() })

        if screenName != currentContentScreen {
            if let cur = currentContentScreen {
                backStack.append(BackStackEntry(screenName: cur, params: currentContentParams))
            }
            contentMount.divView = nil
        }
        currentContentScreen = screenName
        currentContentParams = params

        joinChannel(mount: contentMount, screenName: screenName, params: params)
    }

    public func handleBack() {
        if transitionOverlay.isVisible {
            transitionOverlay.hide()
            if !backStack.isEmpty {
                let prev = backStack.removeLast()
                navigateBack(screenName: prev.screenName, params: prev.params)
            } else {
                dismiss(animated: true)
            }
            return
        }

        if !backStack.isEmpty {
            let prev = backStack.removeLast()
            navigateBack(screenName: prev.screenName, params: prev.params)
        } else {
            dismiss(animated: true)
        }
    }

    private func navigateBack(screenName: String, params: [String: Any]?) {
        if let currentChan = contentMount.channel {
            currentChan.leave()
            contentMount.channel = nil
        }
        contentMount.divView = nil
        clearPendingForMount(contentMount)

        transitionOverlay.resetFallback()
        transitionOverlay.show(onRetry: { [weak self] in self?.retryCurrentScreen() })

        currentContentScreen = screenName
        currentContentParams = params
        joinChannel(mount: contentMount, screenName: screenName, params: params)
    }

    private func joinPersistentScreens() {
        for (region, mount) in persistentMounts {
            if mount.channel == nil || mount.channel!.isClosed {
                joinChannel(mount: mount, screenName: region, params: nil)
            }
        }
    }

    private func joinChannel(mount: Mount, screenName: String, params: [String: Any]?) {
        mount.screenName = screenName
        let topic = "flare:\(screenName)"
        let chan = socket?.channel(topic, chanParams: params)
        mount.channel = chan

        _ = chan?.on(event: "init") { [weak self] payload, _, _ in
            DispatchQueue.main.async { self?.handleInit(envelope: payload, region: mount.region) }
        }
        _ = chan?.on(event: "patch") { [weak self] payload, _, _ in
            DispatchQueue.main.async { self?.handlePatch(envelope: payload, region: mount.region) }
        }
        _ = chan?.on(event: "layout_update") { [weak self] payload, _, _ in
            DispatchQueue.main.async { self?.handleLayoutUpdate(envelope: payload, region: mount.region) }
        }

        chan?.join()
            .receive("ok") { [weak self] _, _, _ in
                DispatchQueue.main.async {
                    if mount.region == "content" { self?.contentJoinFailureStreak = 0 }
                }
            }
            .receive("error") { [weak self] payload, _, _ in
                DispatchQueue.main.async {
                    self?.handleJoinFailure(screenName: screenName, region: mount.region, payload: payload)
                }
            }
            .receive("timeout") { [weak self] _, _, _ in
                DispatchQueue.main.async {
                    self?.handleJoinFailure(screenName: screenName, region: mount.region, payload: nil)
                }
            }
    }

    private func handleInit(envelope: [String: Any], region: String) {
        let mount = (region == "content") ? contentMount! : persistentMounts[region]!
        let parsed = FlareEnvelope.fromInit(envelope)

        if let layout = parsed.layout {
            mount.cachedLayoutJson = layout
            registerActionPendingVars(layoutJson: layout)
        }

        if let variables = envelope["variables"] as? [[String: Any]] {
            for v in variables {
                guard let name = v["name"] as? String else { continue }
                if name == FlareClientViewController.PENDING_VAR { continue }
                if name.hasPrefix("local_") && initializedLocalVars.contains(name) { continue }
                if name.hasPrefix("local_") { initializedLocalVars.insert(name) }
                registerVariable(name: name, type: v["type"] as? String, value: v["value"])
                if v["exported"] as? Bool == true { exportedVariableNames.insert(name) }
            }
        }

        if let state = parsed.state {
            for (k, v) in state { updateVariable(name: k, value: v) }
        }

        if region == "content", let scaffold = parsed.scaffold {
            applyScaffold(scaffold)
        }

        guard let layout = parsed.layout else {
            if region == "content" {
                showScreenErrorFallback(mount: mount, message: "Server sent empty layout for screen: \(currentContentScreen ?? "")", onRetry: { [weak self] in self?.retryCurrentScreen() })
            }
            return
        }

        let factory = FlareDivViewFactory(divKitComponents: divKitComponents)
        if let divView = try? factory.createView(layoutJson: layout) {
            divView.translatesAutoresizingMaskIntoConstraints = false
            let oldViews = mount.container.subviews
            mount.container.addSubview(divView)

            NSLayoutConstraint.activate([
                divView.topAnchor.constraint(equalTo: mount.container.topAnchor),
                divView.leadingAnchor.constraint(equalTo: mount.container.leadingAnchor),
                divView.trailingAnchor.constraint(equalTo: mount.container.trailingAnchor),
                divView.bottomAnchor.constraint(equalTo: mount.container.bottomAnchor)
            ])

            oldViews.forEach { $0.removeFromSuperview() }
            mount.divView = divView

            if region == "content" {
                hasEverLoadedContent = true
                isResumingFromBackground = false
                reconnectFailureStreak = 0
                contentJoinFailureStreak = 0
                transitionOverlay.resetFallback()
                transitionOverlay.hide()
                ambientIsland.flyToTop()
            }
        } else if region == "content" {
            showScreenErrorFallback(mount: mount, message: "Error rendering layout", onRetry: { [weak self] in self?.retryCurrentScreen() })
        }

        FlareServerDirectiveHandler.execute(
            envelope: envelope,
            viewController: self,
            navigate: { [weak self] s, p in self?.navigateTo(screenName: s, params: p) },
            storeToken: { [weak self] t in self?.storeToken(t) },
            clearStorage: { [weak self] in self?.clearStorage() },
            haptic: { [weak self] s in self?.triggerHaptic(s) }
        )
    }

    private func registerActionPendingVars(layoutJson: [String: Any]) {
        var actions = Set<String>()
        extractFlareActions(obj: layoutJson, found: &actions)
        var varsToSet: [DivVariableName: DivVariableValue] = [:]
        for action in actions {
            let varName = "local_flare_pending_\(action)"
            varsToSet[DivVariableName(rawValue: varName)] = .bool(false)
        }
        if !varsToSet.isEmpty {
            divKitComponents.variablesStorage.set(variables: varsToSet, triggerUpdate: false)
        }
    }

    private func extractFlareActions(obj: Any, found: inout Set<String>) {
        if let dict = obj as? [String: Any] {
            if let action = dict["flare_action"] as? String {
                found.insert(action)
            }
            for (_, value) in dict {
                extractFlareActions(obj: value, found: &found)
            }
        } else if let arr = obj as? [Any] {
            for item in arr {
                extractFlareActions(obj: item, found: &found)
            }
        }
    }

    private func handlePatch(envelope: [String: Any], region: String) {
        let mount = (region == "content") ? contentMount! : persistentMounts[region]!

        if let state = envelope["state"] as? [String: Any] {
            for (k, v) in state { 
                updateVariable(name: k, value: v) 
            }
        }
        clearPendingForMount(mount)

        FlareServerDirectiveHandler.execute(
            envelope: envelope,
            viewController: self,
            navigate: { [weak self] s, p in self?.navigateTo(screenName: s, params: p) },
            storeToken: { [weak self] t in self?.storeToken(t) },
            clearStorage: { [weak self] in self?.clearStorage() },
            haptic: { [weak self] s in self?.triggerHaptic(s) }
        )
    }

    private func handleLayoutUpdate(envelope: [String: Any], region: String) {
        handleInit(envelope: envelope, region: region)
    }

    private func findMount(for view: UIView?) -> Mount {
        guard let view = view else { return contentMount }
        for (_, mount) in persistentMounts {
            if let divView = mount.divView, view === divView || view.isDescendant(of: divView) {
                return mount
            }
            if view.isDescendant(of: mount.container) {
                return mount
            }
        }
        if let contentDiv = contentMount.divView, view === contentDiv || view.isDescendant(of: contentDiv) {
            return contentMount
        }
        return contentMount
    }

    public func onAction(actionType: String, payload: [String: Any], view: UIView?) {
        let sourceMount = findMount(for: view)
        handleResolvedAction(eventType: actionType, payload: payload, sourceMount: sourceMount)
    }

    public func onClientTask(taskId: String, params: [String: Any]) {
        FlareClientTaskEngine.dispatch(host: self, taskId: taskId, params: params)
    }

    public func onClientPlugin(pluginId: String, invocation: [String: Any], view: UIView?) {
        let sourceMount = findMount(for: view)
        clientPluginEngine.dispatch(
            pluginId: pluginId,
            resultVar: invocation["result_var"] as? String ?? "",
            params: invocation["params"] as? [String: Any],
            expectFields: invocation["expect_fields"] as? [String],
            onSuccess: invocation["on_success"] as? String,
            onError: invocation["on_error"] as? String,
            onCancel: invocation["on_cancel"] as? String,
            timeoutMsOverride: invocation["timeout_ms"] as? TimeInterval,
            originScreenName: sourceMount.screenName ?? currentContentScreen
        )
    }

    private func handleResolvedAction(eventType: String, payload: [String: Any], sourceMount: Mount) {
        if eventType == "toggle_dark_mode" {
            let next = !UserDefaults.standard.bool(forKey: PREF_DARK_MODE)
            UserDefaults.standard.set(next, forKey: PREF_DARK_MODE)
            updateVariable(name: "local_dark_mode", value: next)
            let newColor = next ? Self.COLOR_BG_DARK : Self.COLOR_BG_LIGHT
            view.backgroundColor = newColor
            contentMount.container.backgroundColor = newColor
            persistentMounts["bottom_bar"]?.container.backgroundColor = newColor
            return
        }

        if eventType == "open_drawer" || eventType == "close_drawer" ||
           eventType == "open_end_drawer" || eventType == "close_end_drawer" {
            let isOpen = eventType.hasPrefix("open_")
            let varName = eventType.hasSuffix("end_drawer") ? "local_end_drawer_open" : "local_drawer_open"
            initializedLocalVars.insert(varName)
            updateVariable(name: varName, value: isOpen)
            return
        }

        if sourceMount.pendingActions.contains(eventType) { return }
        sourceMount.pendingActions.insert(eventType)
        updateVariable(name: "local_flare_pending_\(eventType)", value: true)

        let eventPayload: [String: Any] = [
            "screen": sourceMount.screenName ?? "",
            "type": eventType,
            "payload": payload
        ]

        sourceMount.channel?.push(event: "event", payload: eventPayload)
            .receive("ok") { [weak self] _, _, _ in
                DispatchQueue.main.async { self?.releasePendingAction(mount: sourceMount, eventType: eventType) }
            }
            .receive("error") { [weak self] _, _, _ in
                DispatchQueue.main.async { self?.releasePendingAction(mount: sourceMount, eventType: eventType) }
            }
            .receive("timeout") { [weak self] _, _, _ in
                DispatchQueue.main.async { self?.releasePendingAction(mount: sourceMount, eventType: eventType) }
            }
    }

    public func applyScaffold(_ list: [String]) {
        let set = Set(list)
        UIView.animate(withDuration: 0.25) {
            for r in self.ACTIVE_SCAFFOLD_REGIONS {
                self.persistentMounts[r]?.container.isHidden = !set.contains(r)
            }
            self.view.layoutIfNeeded()
        }
    }

    public func showScaffold(_ region: String) {
        UIView.animate(withDuration: 0.25) {
            self.persistentMounts[region]?.container.isHidden = false
            self.view.layoutIfNeeded()
        }
    }

    public func hideScaffold(_ region: String) {
        UIView.animate(withDuration: 0.25) {
            self.persistentMounts[region]?.container.isHidden = true
            self.view.layoutIfNeeded()
        }
    }

    public func storeToken(_ token: String) {
        let isFirstToken = UserDefaults.standard.string(forKey: PREF_TOKEN) == nil
        UserDefaults.standard.set(token, forKey: PREF_TOKEN)

        if isFirstToken {
            let screenToRejoin = currentContentScreen ?? entryScreen
            if let chan = contentMount.channel {
                chan.leave()
                contentMount.channel = nil
            }
            for (_, m) in persistentMounts {
                m.channel?.leave()
                m.channel = nil
            }
            socket?.shutdown()
            socket = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.buildAndConnectSocket(entryScreen: screenToRejoin)
            }
        }
    }

    public func clearStorage() {
        UserDefaults.standard.removeObject(forKey: PREF_TOKEN)
        dismiss(animated: true)
    }

    public func triggerHaptic(_ style: String) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case "light": generator = UIImpactFeedbackGenerator(style: .light)
        case "heavy": generator = UIImpactFeedbackGenerator(style: .heavy)
        default: generator = UIImpactFeedbackGenerator(style: .medium)
        }
        generator.impactOccurred()
    }

    private func registerVariable(name: String, type: String?, value: Any?) {
        let divValue = parseDivVariable(type: type, value: value)
        let varName = DivVariableName(rawValue: name)
        divKitComponents.variablesStorage.set(variables: [varName: divValue], triggerUpdate: false)
    }

    public func updateVariable(name: String, value: Any?) {
        let varName = DivVariableName(rawValue: name)
        let divValue = parseDivVariable(type: nil, value: value)
        divKitComponents.variablesStorage.set(variables: [varName: divValue], triggerUpdate: true)

        if exportedVariableNames.contains(name) {
            FlareExportedVariables.set(name: name, value: value)
        }
    }

    private func parseDivVariable(type: String?, value: Any?) -> DivVariableValue {
        guard let value = value, !(value is NSNull) else {
            return .string("")
        }

        if let type = type?.lowercased() {
            switch type {
            case "integer":
                if let num = value as? NSNumber { return .integer(num.intValue) }
                if let str = value as? String, let intVal = Int(str) { return .integer(intVal) }
                return .integer(0)
            case "number":
                if let num = value as? NSNumber { return .number(num.doubleValue) }
                if let str = value as? String, let dVal = Double(str) { return .number(dVal) }
                return .number(0.0)
            case "boolean":
                if let num = value as? NSNumber { return .bool(num.boolValue) }
                if let str = value as? String { return .bool(str.lowercased() == "true") }
                return .bool(false)
            case "dict":
                if let dict = value as? [String: Any] { return .dict(toDivDictionary(dict)) }
                return .dict([:])
            case "array":
                if let arr = value as? [Any] { return .array(toDivArray(arr)) }
                return .array([])
            default:
                return .string("\(value)")
            }
        }

        if let dict = value as? [String: Any] {
            return .dict(toDivDictionary(dict))
        } else if let arr = value as? [Any] {
            return .array(toDivArray(arr))
        } else if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            } else if CFNumberIsFloatType(num as CFNumber) {
                return .number(num.doubleValue)
            } else {
                return .integer(num.intValue)
            }
        } else if let str = value as? String {
            return .string(str)
        } else {
            return .string("\(value)")
        }
    }

    private func toDivDictionary(_ dict: [String: Any]) -> [String: AnyHashable] {
        var result = [String: AnyHashable]()
        for (k, v) in dict {
            if let nestedDict = v as? [String: Any] {
                result[k] = toDivDictionary(nestedDict)
            } else if let nestedArr = v as? [Any] {
                result[k] = toDivArray(nestedArr)
            } else if let num = v as? NSNumber {
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    result[k] = num.boolValue
                } else if CFNumberIsFloatType(num as CFNumber) {
                    result[k] = num.doubleValue
                } else {
                    result[k] = num.intValue
                }
            } else if let h = v as? AnyHashable {
                result[k] = h
            } else {
                result[k] = String(describing: v)
            }
        }
        return result
    }

    private func toDivArray(_ arr: [Any]) -> [AnyHashable] {
        return arr.map { item in
            if let nestedDict = item as? [String: Any] {
                return toDivDictionary(nestedDict)
            } else if let nestedArr = item as? [Any] {
                return toDivArray(nestedArr)
            } else if let num = item as? NSNumber {
                if CFGetTypeID(num) == CFBooleanGetTypeID() {
                    return num.boolValue
                } else if CFNumberIsFloatType(num as CFNumber) {
                    return num.doubleValue
                } else {
                    return num.intValue
                }
            } else if let h = item as? AnyHashable {
                return h
            } else {
                return String(describing: item)
            }
        }
    }

    private func releasePendingAction(mount: Mount, eventType: String) {
        mount.pendingActions.remove(eventType)
        updateVariable(name: "local_flare_pending_\(eventType)", value: false)
    }

    private func clearPendingForMount(_ mount: Mount) {
        let snapshot = mount.pendingActions
        mount.pendingActions.removeAll()
        snapshot.forEach { updateVariable(name: "local_flare_pending_\($0)", value: false) }
    }

    private func clearAllPendingActions() {
        clearPendingForMount(contentMount)
        for (_, m) in persistentMounts {
            clearPendingForMount(m)
        }
    }

    public func retryCurrentScreen() {
        guard let cur = currentContentScreen else { return }
        clearPendingForMount(contentMount)
        joinChannel(mount: contentMount, screenName: cur, params: currentContentParams)
    }

    public func retryConnection() {
        reconnectFailureStreak = 0
        contentJoinFailureStreak = 0
        if socket?.isConnected != true { socket?.connect() }

        if transitionOverlay.isVisible {
            transitionOverlay.show(onRetry: { [weak self] in self?.retryCurrentScreen() })
        } else {
            transitionOverlay.startIslandLoading()
        }
        retryCurrentScreen()
    }

    private func handleConnectionFailure(_ message: String) {
        reconnectFailureStreak += 1
        if !hasEverLoadedContent {
            if reconnectFailureStreak >= 2 {
                showConnectionLostFallback(message: message, onRetry: { [weak self] in self?.retryCurrentScreen() })
            }
        } else if isResumingFromBackground {
            if reconnectFailureStreak >= 3 {
                isResumingFromBackground = false
                showConnectionLostFallback(message: message, onRetry: { [weak self] in self?.retryCurrentScreen() })
            }
        } else {
            if reconnectFailureStreak >= 3 {
                showConnectionLostFallback(message: message, onRetry: { [weak self] in self?.retryCurrentScreen() })
            } else {
                ambientIsland.setLoading(true)
            }
        }
    }

    private func handleJoinFailure(screenName: String, region: String, payload: [String: Any]?) {
        let reason = payload?["reason"] as? String ?? ""
        if reason == "authentication_required" || reason == "session_expired" || reason == "invalid_token" {
            clearStorage()
        } else if region == "content" {
            contentJoinFailureStreak += 1
            if !hasEverLoadedContent {
                if contentJoinFailureStreak >= 2 {
                    showConnectionLostFallback(message: "This screen isn't loading after several attempts.", onRetry: { [weak self] in self?.retryCurrentScreen() })
                }
            } else {
                showScreenErrorFallback(mount: contentMount, message: "Could not load screen: \(screenName)", onRetry: { [weak self] in self?.retryCurrentScreen() })
            }
        } else {
            persistentMounts[region]?.container.isHidden = true
        }
    }

    private func showConnectionLostFallback(message: String?, onRetry: @escaping () -> Void) {
        guard let layoutJson = loadConnectionLostLayoutJson() else {
            ambientIsland.flyToTop()
            transitionOverlay.showError(message: message ?? "Connection problem.", onRetry: onRetry)
            return
        }

        let icon = isResumingFromBackground ? "✨" : "📡"
        let title = isResumingFromBackground ? "Welcome back" : "No internet connection"
        let desc = isResumingFromBackground ? "Resuming your session and syncing..." : (message ?? "Please check your network connection.")

        if isResumingFromBackground {
            ambientIsland.setupInitialHeroState()
        } else {
            ambientIsland.flyToTop()
        }

        updateVariable(name: "local_connection_lost_icon", value: icon)
        updateVariable(name: "local_connection_lost_title", value: title)
        updateVariable(name: "local_connection_lost_message", value: desc)

        let factory = FlareDivViewFactory(divKitComponents: divKitComponents)
        if let view = try? factory.createView(layoutJson: layoutJson) {
            transitionOverlay.showConnectionLostFallback(view)
        } else {
            transitionOverlay.showError(message: desc, onRetry: onRetry)
        }
    }

    private func showScreenErrorFallback(mount: Mount, message: String, onRetry: @escaping () -> Void) {
        if mount.region == "content" {
            ambientIsland.flyToTop()
            transitionOverlay.hide()
            transitionOverlay.stopIslandLoading()
        }

        guard let layoutJson = loadScreenErrorLayoutJson() else {
            showContentInlineErrorFallback(mount: mount, message: message, onRetry: onRetry)
            return
        }

        updateVariable(name: "local_screen_error_message", value: message)

        let factory = FlareDivViewFactory(divKitComponents: divKitComponents)
        if let view = try? factory.createView(layoutJson: layoutJson) {
            mount.container.subviews.forEach { $0.removeFromSuperview() }
            view.translatesAutoresizingMaskIntoConstraints = false
            mount.container.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: mount.container.topAnchor),
                view.leadingAnchor.constraint(equalTo: mount.container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: mount.container.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: mount.container.bottomAnchor)
            ])
            mount.divView = view
        } else {
            showContentInlineErrorFallback(mount: mount, message: message, onRetry: onRetry)
        }
    }

    private func showContentInlineErrorFallback(mount: Mount, message: String, onRetry: @escaping () -> Void) {
        mount.container.subviews.forEach { $0.removeFromSuperview() }
        let label = UILabel()
        label.text = "\(message)\n\n(Tap to retry)"
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .systemRed
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(onInlineRetryTapped)))
        label.translatesAutoresizingMaskIntoConstraints = false
        mount.container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: mount.container.topAnchor),
            label.leadingAnchor.constraint(equalTo: mount.container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: mount.container.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: mount.container.bottomAnchor)
        ])
    }

    @objc private func onInlineRetryTapped() {
        retryCurrentScreen()
    }

    private func loadJsonResource(_ name: String) -> [String: Any]? {
        let bundles: [Bundle] = [
            Bundle.main,
            Bundle(for: FlareClientViewController.self)
        ]
        
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                return json
            }
        }
        return nil
    }

    private func loadConnectionLostLayoutJson() -> [String: Any]? {
        if cachedConnectionLostLayoutJson != nil || connectionLostLayoutLoadAttempted { return cachedConnectionLostLayoutJson }
        connectionLostLayoutLoadAttempted = true
        cachedConnectionLostLayoutJson = loadJsonResource("connection_lost_screen")
        return cachedConnectionLostLayoutJson
    }

    private func loadScreenErrorLayoutJson() -> [String: Any]? {
        if cachedScreenErrorLayoutJson != nil || screenErrorLayoutLoadAttempted { return cachedScreenErrorLayoutJson }
        screenErrorLayoutLoadAttempted = true
        cachedScreenErrorLayoutJson = loadJsonResource("screen_error_screen")
        return cachedScreenErrorLayoutJson
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isResumingFromBackground = true
            self?.socket?.onActivityPause()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if self.socket?.isConnected != true {
                if self.isResumingFromBackground {
                    self.showConnectionLostFallback(message: nil, onRetry: { [weak self] in self?.retryCurrentScreen() })
                }
                self.socket?.onActivityResume()
            } else {
                self.isResumingFromBackground = false
                if self.transitionOverlay.isVisible {
                    self.transitionOverlay.resetFallback()
                    self.transitionOverlay.hide()
                }
            }
        }
    }

    private class PluginContextImpl: FlareClientPluginContext {
        private weak var controller: FlareClientViewController?
        init(controller: FlareClientViewController) { self.controller = controller }
        func getAuthToken() -> String? { UserDefaults.standard.string(forKey: "flare_auth_token") }
        func getBaseHttpUrl() -> String? { controller?.wsUrl.replacingOccurrences(of: "ws://", with: "http://").replacingOccurrences(of: "wss://", with: "https://") }
        func getScreenName() -> String? { controller?.currentContentScreen }
        func notifyAuthFailure() { controller?.clearStorage() }
    }

    private class NativePaneContextImpl: FlareNativePaneContext {
        private weak var controller: FlareClientViewController?
        init(controller: FlareClientViewController) { self.controller = controller }
        func getScreenName() -> String? { controller?.currentContentScreen }
        func getAuthToken() -> String? { UserDefaults.standard.string(forKey: "flare_auth_token") }
        func getBaseHttpUrl() -> String? { controller?.wsUrl.replacingOccurrences(of: "ws://", with: "http://").replacingOccurrences(of: "wss://", with: "https://") }
        func notifyAuthFailure() { controller?.clearStorage() }
        func setVariable(name: String, value: Any) { controller?.updateVariable(name: name, value: value) }
        func fireAction(actionName: String, payload: [String: Any]?) {
            guard let c = controller else { return }
            c.handleResolvedAction(eventType: actionName, payload: payload ?? [:], sourceMount: c.contentMount)
        }
    }
}