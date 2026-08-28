import UIKit
import DivKit

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
        
        Task { @MainActor in
            await divView.setSource(
                DivViewSource(kind: .data(jsonData), cardId: DivCardID(rawValue: cardId))
            )
        }
        return divView
    }
}