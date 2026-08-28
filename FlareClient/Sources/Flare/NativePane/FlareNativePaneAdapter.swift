import UIKit
import DivKit
import LayoutKit

public final class FlareNativePaneAdapter: DivCustomBlockFactory {
    private let paneContext: FlareNativePaneContext
    private var activeProviders = NSMapTable<UIView, AnyObject>.weakToStrongObjects()

    public init(paneContext: FlareNativePaneContext) {
        self.paneContext = paneContext
    }

    public func makeBlock(data: DivCustomData, context: DivBlockModelingContext) -> Block {
        let type = data.name
        guard let provider = FlareNativePaneRegistry.get(type) else {
            let label = UILabel()
            label.text = "Missing pane: \(type)"
            label.textColor = .systemRed
            label.textAlignment = .center
            return GenericViewBlock.makeIntrinsicSized(for: label)
        }

        let props = data.data
        let view = provider.createView(initialProps: props, paneContext: paneContext)
        activeProviders.setObject(provider, forKey: view)
        return GenericViewBlock.makeIntrinsicSized(for: view)
    }
}