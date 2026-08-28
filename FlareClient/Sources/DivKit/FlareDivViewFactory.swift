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
        
        let cardIdObj = DivCardID(rawValue: cardId)
        let source = DivViewSource(kind: .data(jsonData), cardId: cardIdObj)
        
        divView.setSource(source, cardId: cardIdObj)
        return divView
    }

    public func updateView(_ divView: DivView, cardId: String) {
        let cardIdObj = DivCardID(rawValue: cardId)
        divView.setSource(divView.source, cardId: cardIdObj)
    }
}