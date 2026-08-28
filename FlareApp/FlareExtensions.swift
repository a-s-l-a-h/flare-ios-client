import Foundation
import FlareClient
import FlareClientExtensionsBuiltin

public final class FlareExtensions {
    private init() {}

    public static func registerAll() {
        registerBuiltInTasks()
        registerBuiltInPanes()
    }

    private static func registerBuiltInTasks() {
        OpenBrowserTask().register()
        ForceLogoutTask().register()
        HapticTask().register()
        ShowAlertTask().register()
        ShowScaffoldTask().register()
        HideScaffoldTask().register()
        RetryConnectionTask().register()
    }

    private static func registerBuiltInPanes() {
        PlaceholderPaneProvider().register()
    }
}