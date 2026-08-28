import UIKit
import DivKit
import VGSL

public final class FlareDivViewFactory {
    private let divKitComponents: DivKitComponents

    public init(divKitComponents: DivKitComponents) {
        self.divKitComponents = divKitComponents
    }

    public func createView(layoutJson: [String: Any]) throws -> DivView {
        let cardJson = (layoutJson["card"] as? [String: Any]) ?? layoutJson
        let cardId = (layoutJson["log_id"] as? String) ?? (cardJson["log_id"] as? String) ?? "flare_screen"

        var finalJson = layoutJson
        if finalJson["card"] == nil {
            finalJson = [
                "log_id": cardId,
                "card": cardJson
            ]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: finalJson)
        let divView = DivView(divKitComponents: divKitComponents)
        let source = DivViewSource(kind: .data(jsonData), cardId: DivCardID(rawValue: cardId))
        
        Task { @MainActor in
            await divView.setSource(source)
        }
        
        return divView
    }
}