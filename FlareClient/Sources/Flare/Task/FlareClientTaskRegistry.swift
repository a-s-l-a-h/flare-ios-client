import Foundation

public final class FlareClientTaskRegistry {
    private static var tasks = [String: FlareClientTask]()
    private static let lock = NSRecursiveLock()

    private init() {}

    public static func register(_ task: FlareClientTask) {
        lock.lock()
        defer { lock.unlock() }
        tasks[task.id] = task
    }

    public static func get(_ id: String) -> FlareClientTask? {
        lock.lock()
        defer { lock.unlock() }
        return tasks[id]
    }

    public static func registeredIds() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(tasks.keys)
    }
}