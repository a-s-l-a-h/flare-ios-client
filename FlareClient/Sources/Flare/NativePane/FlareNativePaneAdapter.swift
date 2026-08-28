import UIKit
import DivKit
import LayoutKit

public final class FlareNativePaneAdapter: DivCustomBlockFactory {
    private let paneContext: FlareNativePaneContext
    private var activeProviders = NSMapTable<UIView, AnyObject>.weakToStrongObjects()

    public init(paneContext: FlareNativePaneContext) {
        self.paneContext = paneContext
    }

    public func makeBlock(data: CustomBlockData, context: DivBlockModelingContext) -> Block {
        let type = data.name
        guard let provider = FlareNativePaneRegistry.get(type) else {
            return CustomBlock(widthTrait: .intrinsic, heightTrait: .intrinsic) {
                let label = UILabel()
                label.text = "Missing pane: \(type)"
                label.textColor = .systemRed
                label.textAlignment = .center
                return label
            }
        }

        let props = data.data
        return CustomBlock(widthTrait: .intrinsic, heightTrait: .intrinsic) { [weak self] in
            guard let self = self else { return UIView() }
            let view = provider.createView(initialProps: props, paneContext: self.paneContext)
            self.activeProviders.setObject(provider, forKey: view)
            return view
        }
    }
}