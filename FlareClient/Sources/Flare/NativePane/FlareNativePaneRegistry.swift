import Foundation

public final class FlareNativePaneRegistry {
    private static var providers = [String: FlareNativePaneProvider]()
    private static let lock = NSRecursiveLock()

    private init() {}

    public static func register(_ provider: FlareNativePaneProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers[provider.id] = provider
    }

    public static func get(_ id: String) -> FlareNativePaneProvider? {
        lock.lock()
        defer { lock.unlock() }
        return providers[id]
    }

    public static func registeredIds() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(providers.keys)
    }
}