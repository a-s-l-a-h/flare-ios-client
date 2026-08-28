import Foundation

/// Safe, one-directional read-only mirror of variables declared `"exported": true`.
/// Thread-safe via NSRecursiveLock.
public final class FlareExportedVariables {
    public typealias Listener = (_ name: String, _ value: Any?) -> Void

    private static var values = [String: Any]()
    private static var listenersByName = [String: [UUID: Listener]]()
    private static let lock = NSRecursiveLock()

    private init() {}

    public static func set(name: String, value: Any?) {
        lock.lock()
        if let val = value {
            values[name] = val
        } else {
            values.removeValue(forKey: name)
        }
        let currentListeners = listenersByName[name]?.values.map { $0 } ?? []
        lock.unlock()

        currentListeners.forEach { listener in
            listener(name, value)
        }
    }

    public static func get(name: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[name]
    }

    @discardableResult
    public static func subscribe(name: String, listener: @escaping Listener) -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        var dict = listenersByName[name] ?? [:]
        dict[id] = listener
        listenersByName[name] = dict
        return id
    }

    public static func unsubscribe(name: String, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        listenersByName[name]?.removeValue(forKey: id)
    }
}