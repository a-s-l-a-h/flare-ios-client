import UIKit

public protocol FlareNativePaneProvider: AnyObject {
    var id: String { get }
    func createView(initialProps: [String: Any], paneContext: FlareNativePaneContext) -> UIView
    func bindView(_ view: UIView, props: [String: Any], paneContext: FlareNativePaneContext)
    func releaseView(_ view: UIView)
}

public extension FlareNativePaneProvider {
    func register() {
        FlareNativePaneRegistry.register(self)
    }
}