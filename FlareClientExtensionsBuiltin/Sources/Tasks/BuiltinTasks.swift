import UIKit
import FlareClient

public final class OpenBrowserTask: FlareClientTask {
    public static let ID = "open_browser"
    public var id: String { return Self.ID }
    public init() {}

    public func execute(host: UIViewController?, params: [String: Any]) {
        guard let urlStr = params["url"] as? String, let url = URL(string: urlStr),
              let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") else { return }
        UIApplication.shared.open(url)
    }
}

public final class ForceLogoutTask: FlareClientTask {
    public static let ID = "force_logout"
    public var id: String { return Self.ID }
    public init() {}

    public func execute(host: UIViewController?, params: [String: Any]) {
        (host as? FlareClientViewController)?.clearStorage()
    }
}

public final class HapticTask: FlareClientTask {
    public static let ID = "haptic"
    public var id: String { return Self.ID }
    public init() {}

    public func execute(host: UIViewController?, params: [String: Any]) {
        let style = params["style"] as? String ?? "success"
        (host as? FlareClientViewController)?.triggerHaptic(style)
    }
}

public final class ShowAlertTask: FlareClientTask {
    public static let ID = "show_alert"
    public var id: String { return Self.ID }
    public init() {}

    public func execute(host: UIViewController?, params: [String: Any]) {
        guard let host = host else { return }
        let title = params["title"] as? String ?? ""
        let message = params["message"] as? String ?? ""
        let button = params["button"] as? String ?? "OK"
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: button, style: .default))
        host.present(alert, animated: true)
    }
}

public final class ShowScaffoldTask: FlareClientTask {
    public static let ID = "show_scaffold"
    public var id: String { return Self.ID }
    public init() {}

    public func execute(host: UIViewController?, params: [String: Any]) {
        if let region = params["region"] as? String {
            (host as? FlareClientViewController)?.showScaffold(region)
        }
    }
}

public final class HideScaffoldTask: FlareClientTask {
    public static let ID = "hide_scaffold"
    public var id: String { return Self.ID }
    public init() {}

    public func execute(host: UIViewController?, params: [String: Any]) {
        if let region = params["region"] as? String {
            (host as? FlareClientViewController)?.hideScaffold(region)
        }
    }
}

public final class RetryConnectionTask: FlareClientTask {
    public static let ID = "retry_connection"
    public var id: String { return Self.ID }
    public init() {}

    public func execute(host: UIViewController?, params: [String: Any]) {
        (host as? FlareClientViewController)?.retryConnection()
    }
}