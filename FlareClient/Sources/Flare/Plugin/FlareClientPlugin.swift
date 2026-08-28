import UIKit

public protocol FlareClientPlugin: AnyObject {
    var id: String { get }
    var category: String { get }
    func launch(host: UIViewController, params: [String: Any], context: FlareClientPluginContext, callback: FlareClientPluginCallback)
}

public extension FlareClientPlugin {
    var category: String { return "capture" }
    func register() {
        FlareClientPluginRegistry.register(self)
    }
}