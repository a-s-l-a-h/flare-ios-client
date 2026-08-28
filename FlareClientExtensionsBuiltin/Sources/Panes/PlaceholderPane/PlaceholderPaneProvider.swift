import UIKit
import FlareClient

public final class PlaceholderPaneProvider: FlareNativePaneProvider {
    public static let ID = "placeholder_pane"
    public var id: String { return Self.ID }
    public init() {}

    public func createView(initialProps: [String: Any], paneContext: FlareNativePaneContext) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(red: 45/255, green: 52/255, blue: 54/255, alpha: 1)
        container.layer.cornerRadius = 12

        let label = UILabel()
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.textAlignment = .center
        label.tag = 101
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])

        bindView(container, props: initialProps, paneContext: paneContext)
        return container
    }

    public func bindView(_ view: UIView, props: [String: Any], paneContext: FlareNativePaneContext) {
        if let label = view.viewWithTag(101) as? UILabel {
            label.text = props["title"] as? String ?? "Native Placeholder Pane"
        }
    }

    public func releaseView(_ view: UIView) {
        view.subviews.forEach { $0.removeFromSuperview() }
    }
}