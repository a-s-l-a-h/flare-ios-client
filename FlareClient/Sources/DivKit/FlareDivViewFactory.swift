import UIKit
import DivKit

public final class FlareDivViewFactory {
    private let divKitComponents: DivKitComponents

    public init(divKitComponents: DivKitComponents) {
        self.divKitComponents = divKitComponents
    }

    public func createView(layoutJson: [String: Any]) throws -> DivView {
        var cardJson = layoutJson
        if let card = layoutJson["card"] as? [String: Any] {
            cardJson = card
        }

        let templatesJson = layoutJson["templates"] as? [String: Any]
        let templateResolver: DivTemplateResolver?
        if let templatesJson = templatesJson {
            templateResolver = DivTemplates(raw: templatesJson)
        } else {
            templateResolver = nil
        }

        let divData = try DivData(
            raw: cardJson,
            templateResolver: templateResolver
        )

        let divView = DivView(divKitComponents: divKitComponents)
        divView.setSource(
            DivViewSource(
                data: divData,
                cardId: DivCardID(rawValue: cardJson["log_id"] as? String ?? "flare_screen")
            )
        )
        return divView
    }
}