import UIKit
import DivKit

public protocol FlareDivActionCallback: AnyObject {
    func onAction(actionType: String, payload: [String: Any], view: UIView?)
    func onClientTask(taskId: String, params: [String: Any])
    func onClientPlugin(pluginId: String, invocation: [String: Any], view: UIView?)
}

public final class FlareDivActionHandler: DivUrlHandler {
    private weak var callback: FlareDivActionCallback?

    public init(callback: FlareDivActionCallback) {
        self.callback = callback
    }

    public func handle(_ url: URL, sender: AnyObject?) {
        guard url.scheme?.lowercased() == "flare" else { return }
        let host = url.host?.lowercased() ?? ""
        let view = sender as? UIView

        switch host {
        case "action":
            handleServerAction(url: url, view: view)
        case "clienttask":
            handleClientTask(url: url)
        case "clientplugin":
            handleClientPlugin(url: url, view: view)
        default:
            break
        }
    }

    private func handleServerAction(url: URL, view: UIView?) {
        var payload = [String: Any]()
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems {
            for item in items {
                payload[item.name] = item.value ?? ""
            }
        }
        guard let actionType = payload["flare_action"] as? String, !actionType.isEmpty else { return }
        callback?.onAction(actionType: actionType, payload: payload, view: view)
    }

    private func handleClientTask(url: URL) {
        var params = [String: Any]()
        var taskId = ""
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems {
            for item in items {
                if item.name == "task" {
                    taskId = item.value ?? ""
                } else {
                    params[item.name] = item.value ?? ""
                }
            }
        }
        callback?.onClientTask(taskId: taskId, params: params)
    }

    private func handleClientPlugin(url: URL, view: UIView?) {
        var pluginParams = [String: Any]()
        var pluginId = ""
        var resultVar = ""
        var onSuccess: String?
        var onError: String?
        var onCancel: String?
        var timeoutMs: TimeInterval = 0
        var expectFields: [String]?

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems {
            for item in items {
                let name = item.name
                let val = item.value ?? ""
                switch name {
                case "plugin": pluginId = val
                case "result_var": resultVar = val
                case "on_success": onSuccess = val
                case "on_error": onError = val
                case "on_cancel": onCancel = val
                case "timeout_ms": timeoutMs = Double(val) ?? 0
                case "expect_fields": expectFields = val.split(separator: ",").map(String.init)
                default: pluginParams[name] = val
                }
            }
        }

        var invocation: [String: Any] = [
            "plugin": pluginId,
            "result_var": resultVar,
            "params": pluginParams,
            "timeout_ms": timeoutMs
        ]
        if let s = onSuccess { invocation["on_success"] = s }
        if let e = onError { invocation["on_error"] = e }
        if let c = onCancel { invocation["on_cancel"] = c }
        if let f = expectFields { invocation["expect_fields"] = f }

        callback?.onClientPlugin(pluginId: pluginId, invocation: invocation, view: view)
    }
}