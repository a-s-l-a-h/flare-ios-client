import UIKit

public final class FlareClientTaskEngine {
    private init() {}

    @discardableResult
    public static func dispatch(host: UIViewController?, taskId: String, params: [String: Any]) -> Bool {
        guard !taskId.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard let task = FlareClientTaskRegistry.get(taskId) else {
            DispatchQueue.main.async {
                if let host = host {
                    let alert = UIAlertController(title: nil, message: "Action unavailable", preferredStyle: .alert)
                    host.present(alert, animated: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { alert.dismiss(animated: true) }
                }
            }
            return false
        }

        task.execute(host: host, params: params)
        return true
    }
}