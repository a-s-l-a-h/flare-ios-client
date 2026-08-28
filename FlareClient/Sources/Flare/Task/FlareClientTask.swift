import UIKit

public protocol FlareClientTask: AnyObject {
    var id: String { get }
    func execute(host: UIViewController?, params: [String: Any])
}

public extension FlareClientTask {
    func register() {
        FlareClientTaskRegistry.register(self)
    }
}