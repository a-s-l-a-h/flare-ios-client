import Foundation

public final class FlareClientPluginRegistry {
    private static var plugins = [String: FlareClientPlugin]()
    private static let lock = NSRecursiveLock()

    private init() {}

    public static func register(_ plugin: FlareClientPlugin) {
        lock.lock()
        defer { lock.unlock() }
        plugins[plugin.id] = plugin
    }

    public static func get(_ id: String) -> FlareClientPlugin? {
        lock.lock()
        defer { lock.unlock() }
        return plugins[id]
    }

    public static func registeredIds() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(plugins.keys)
    }
}