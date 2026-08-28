import UIKit
import DivKit

public protocol FlareDivActionCallback: AnyObject {
    func onAction(actionType: String, payload: [String: Any], view: UIView?)
    func onClientTask(taskId: String, params: [String: Any])
    func onClientPlugin(pluginId: String, invocation: [String: Any], view: UIView?)
}

public final class FlareDivActionHandler: DivActionHandler {
    private static let reservedPluginKeys: Set<String> = [
        "plugin", "result_var", "on_success", "on_error", "on_cancel", "timeout_ms"
    ]

    private weak var callback: FlareDivActionCallback?
    private let variablesStorage: DivVariablesStorage

    public init(callback: FlareDivActionCallback, variablesStorage: DivVariablesStorage) {
        self.callback = callback
        self.variablesStorage = variablesStorage
        super.init(urlOpener: { _ in })
    }

    public override func handle(_ action: DivActionBase, context: DivActionHandlingContext) {
        guard let url = action.url?.evaluate(with: context.expressionResolver) else {
            super.handle(action, context: context)
            return
        }

        if url.scheme?.lowercased() == "flare" {
            let host = url.host?.lowercased() ?? ""
            if host == "action" {
                handleServerAction(url: url, action: action, view: context.cardView)
                return
            } else if host == "clienttask" {
                handleClientTask(url: url)
                return
            } else if host == "clientplugin" {
                handleClientPlugin(url: url, action: action, view: context.cardView)
                return
            }
        }

        super.handle(action, context: context)
    }

    private func handleServerAction(url: URL, action: DivActionBase, view: UIView?) {
        var payload = [String: Any]()
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems {
            for item in items {
                payload[item.name] = item.value ?? ""
            }
        }

        if let rawPayload = action.payload {
            let resolvedPayload = resolvePayload(rawPayload)
            for (k, v) in resolvedPayload where payload[k] == nil {
                payload[k] = v
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

    private func handleClientPlugin(url: URL, action: DivActionBase, view: UIView?) {
        var urlParams = [String: Any]()
        var pluginId = ""
        var resultVar = ""
        var onSuccess: String?
        var onError: String?
        var onCancel: String?
        var timeoutMs: TimeInterval = 0

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems {
            for item in items {
                let name = item.name
                let val = item.value ?? ""
                if name == "plugin" { pluginId = val }
                else if name == "result_var" { resultVar = val }
                else if name == "on_success" { onSuccess = val }
                else if name == "on_error" { onError = val }
                else if name == "on_cancel" { onCancel = val }
                else if name == "timeout_ms" { timeoutMs = Double(val) ?? 0 }
                else { urlParams[name] = val }
            }
        }

        var pluginParams = urlParams
        let rawPayload = action.payload ?? [:]
        let resolvedPayload = resolvePayload(rawPayload)
        if let payloadParams = resolvedPayload["params"] as? [String: Any] {
            for (k, v) in payloadParams { pluginParams[k] = v }
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
        if let expectFields = rawPayload["expect_fields"] as? [String] {
            invocation["expect_fields"] = expectFields
        }

        callback?.onClientPlugin(pluginId: pluginId, invocation: invocation, view: view)
    }

    private func resolvePayload(_ raw: [String: Any]) -> [String: Any] {
        var resolved = [String: Any]()
        for (k, v) in raw {
            if let strVal = v as? String {
                resolved[k] = resolveExpression(strVal)
            } else {
                resolved[k] = v
            }
        }
        return resolved
    }

    private func resolveExpression(_ raw: String) -> String {
        guard raw.hasPrefix("@{") && raw.hasSuffix("}") else { return raw }
        let varName = String(raw.dropFirst(2).dropLast()).trimmingCharacters(in: .whitespaces)

        guard let divVar = variablesStorage.getVariableValue(DivVariableName(rawValue: varName)) else {
            return ""
        }

        switch divVar {
        case .string(let s): return s
        case .integer(let i): return String(i)
        case .number(let n): return String(n)
        case .bool(let b): return String(b)
        case .url(let u): return u.absoluteString
        case .color(let c):
            let uiColor = UIColor(c)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
            return String(
                format: "#%02lX%02lX%02lX%02lX",
                lroundf(Float(a * 255)),
                lroundf(Float(r * 255)),
                lroundf(Float(g * 255)),
                lroundf(Float(b * 255))
            )
        case .dict(let d):
            if let data = try? JSONSerialization.data(withJSONObject: d),
               let str = String(data: data, encoding: .utf8) { return str }
            return ""
        case .array(let a):
            if let data = try? JSONSerialization.data(withJSONObject: a),
               let str = String(data: data, encoding: .utf8) { return str }
            return ""
        @unknown default:
            return ""
        }
    }
}