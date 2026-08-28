import UIKit
import DivKit

public final class FlareClientPluginEngine {
    private static let defaultTimeoutMs: TimeInterval = 30_000

    public typealias MountLivenessCheck = (_ screenName: String) -> Bool
    public typealias ClientActionFirer = (_ actionName: String, _ originScreenName: String?) -> Void

    private weak var host: UIViewController?
    private let variablesStorage: DivVariablesStorage
    private let context: FlareClientPluginContext
    private let livenessCheck: MountLivenessCheck
    private let actionFirer: ClientActionFirer

    public init(
        host: UIViewController,
        variablesStorage: DivVariablesStorage,
        context: FlareClientPluginContext,
        livenessCheck: @escaping MountLivenessCheck,
        actionFirer: @escaping ClientActionFirer
    ) {
        self.host = host
        self.variablesStorage = variablesStorage
        self.context = context
        self.livenessCheck = livenessCheck
        self.actionFirer = actionFirer
    }

    private class ClosurePluginCallback: FlareClientPluginCallback {
        private let block: (FlareClientPluginResult) -> Void
        init(_ block: @escaping (FlareClientPluginResult) -> Void) { self.block = block }
        func onResult(_ result: FlareClientPluginResult) { block(result) }
    }

    public func dispatch(
        pluginId: String,
        resultVar: String,
        params: [String: Any]?,
        expectFields: [String]?,
        onSuccess: String?,
        onError: String?,
        onCancel: String?,
        timeoutMsOverride: TimeInterval?,
        originScreenName: String?
    ) {
        guard let host = self.host else { return }
        guard let plugin = FlareClientPluginRegistry.get(pluginId) else {
            showNotFoundToast()
            resolve(
                result: .unavailable(pluginId),
                resultVar: resultVar,
                expectFields: expectFields,
                onSuccess: onSuccess,
                onError: onError,
                onCancel: onCancel,
                originScreenName: originScreenName
            )
            return
        }

        let timeoutSec = (timeoutMsOverride != nil && timeoutMsOverride! > 0)
            ? (timeoutMsOverride! / 1000.0)
            : (FlareClientPluginEngine.defaultTimeoutMs / 1000.0)

        var alreadyResolved = false
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, !alreadyResolved else { return }
            alreadyResolved = true
            self.resolve(
                result: .timeout(),
                resultVar: resultVar,
                expectFields: expectFields,
                onSuccess: onSuccess,
                onError: onError,
                onCancel: onCancel,
                originScreenName: originScreenName
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSec, execute: timeoutWorkItem)

        let callback = ClosurePluginCallback { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, !alreadyResolved else { return }
                alreadyResolved = true
                timeoutWorkItem.cancel()
                self.resolve(
                    result: result,
                    resultVar: resultVar,
                    expectFields: expectFields,
                    onSuccess: onSuccess,
                    onError: onError,
                    onCancel: onCancel,
                    originScreenName: originScreenName
                )
            }
        }

        plugin.launch(host: host, params: params ?? [:], context: context, callback: callback)
    }

    private func resolve(
        result: FlareClientPluginResult,
        resultVar: String,
        expectFields: [String]?,
        onSuccess: String?,
        onError: String?,
        onCancel: String?,
        originScreenName: String?
    ) {
        if let origin = originScreenName, !livenessCheck(origin) {
            return
        }

        let projectedEnvelope = applyExpectFieldsProjection(result: result, expectFields: expectFields)
        let varName = DivVariableName(rawValue: resultVar)
        variablesStorage.set(variables: [varName: .dict(projectedEnvelope)], triggerUpdate: true)

        let actionToFire: String?
        switch result.status {
        case "ok": actionToFire = onSuccess
        case "cancelled": actionToFire = onCancel
        default: actionToFire = onError
        }

        if let action = actionToFire, !action.isEmpty {
            actionFirer(action, originScreenName)
        }
    }

    private func applyExpectFieldsProjection(result: FlareClientPluginResult, expectFields: [String]?) -> [String: Any] {
        var envelope = result.toJson()
        guard let expectFields = expectFields, !expectFields.isEmpty,
              result.status == "ok", let data = result.data else {
            return envelope
        }

        let allowedSet = Set(expectFields)
        var trimmed = [String: Any]()
        for (k, v) in data where allowedSet.contains(k) {
            trimmed[k] = v
        }
        envelope["data"] = trimmed
        return envelope
    }

    private func showNotFoundToast() {
        guard let host = self.host else { return }
        let alert = UIAlertController(title: nil, message: "This feature isn't available", preferredStyle: .alert)
        host.present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { alert.dismiss(animated: true) }
    }
}