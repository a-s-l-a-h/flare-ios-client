import Foundation

public final class FlareClientPluginResult {
    public let status: String
    public let data: [String: Any]?
    public let error: [String: Any]?

    private init(status: String, data: [String: Any]?, error: [String: Any]?) {
        self.status = status
        self.data = data
        self.error = error
    }

    public static func ok(_ data: [String: Any]?) -> FlareClientPluginResult {
        return FlareClientPluginResult(status: "ok", data: data ?? [:], error: nil)
    }

    public static func error(code: String, message: String) -> FlareClientPluginResult {
        return FlareClientPluginResult(status: "error", data: nil, error: ["code": code, "message": message])
    }

    public static func cancelled() -> FlareClientPluginResult {
        return FlareClientPluginResult(status: "cancelled", data: nil, error: ["code": "USER_CANCELLED", "message": "Cancelled by user"])
    }

    public static func unavailable(_ pluginId: String) -> FlareClientPluginResult {
        return FlareClientPluginResult(status: "unavailable", data: nil, error: ["code": "UNAVAILABLE", "message": "Plugin not registered: \(pluginId)"])
    }

    public static func timeout() -> FlareClientPluginResult {
        return FlareClientPluginResult(status: "error", data: nil, error: ["code": "TIMEOUT", "message": "The plugin did not respond in time."])
    }

    public static func unknown(_ error: Error?) -> FlareClientPluginResult {
        return FlareClientPluginResult(status: "error", data: nil, error: ["code": "UNKNOWN", "message": error?.localizedDescription ?? "Unknown error"])
    }

    public func toJson() -> [String: Any] {
        return [
            "status": status,
            "data": data ?? NSNull(),
            "error": error ?? NSNull()
        ]
    }
}