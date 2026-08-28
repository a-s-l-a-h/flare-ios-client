import UIKit

public final class FlareServerDirectiveHandler {
    private init() {}

    public static func execute(
        envelope: [String: Any],
        viewController: FlareClientViewController,
        navigate: @escaping (_ screen: String, _ params: [String: Any]?) -> Void,
        storeToken: @escaping (_ token: String) -> Void,
        clearStorage: @escaping () -> Void,
        haptic: @escaping (_ style: String) -> Void
    ) {
        guard let directives = envelope["directives"] as? [[String: Any]] else { return }

        for directive in directives {
            guard let type = directive["type"] as? String else { continue }
            let payload = directive["payload"] as? [String: Any] ?? [:]

            switch type {
            case "navigate":
                if let screen = payload["screen"] as? String {
                    navigate(screen, payload["params"] as? [String: Any])
                }
            case "show_alert":
                let title = payload["title"] as? String ?? ""
                let message = payload["message"] as? String ?? ""
                let button = payload["button"] as? String ?? "OK"
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: button, style: .default, handler: nil))
                viewController.present(alert, animated: true)
            case "store_login_token":
                if let token = payload["token"] as? String {
                    storeToken(token)
                }
            case "clear_login_token":
                clearStorage()
            case "haptic":
                haptic(payload["style"] as? String ?? "success")
            case "hide_scaffold":
                if let region = payload["region"] as? String {
                    viewController.hideScaffold(region)
                }
            case "show_scaffold":
                if let region = payload["region"] as? String {
                    viewController.showScaffold(region)
                }
            default:
                break
            }
        }
    }
}