import UIKit

public final class TransitionOverlayView: UIView {
    private let progressView = UIProgressView(progressViewStyle: .bar)
    private let errorCard = UIView()
    private let errorMessageLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let signOutButton = UIButton(type: .system)
    private let connectionLostContainer = UIView()

    public var onSignOut: (() -> Void)?
    public var onErrorShown: (() -> Void)?
    public var onErrorHidden: (() -> Void)?
    public weak var ambientIsland: AmbientIslandView?

    private var timeoutWorkItem: DispatchWorkItem?
    private var onRetryAction: (() -> Void)?
    public private(set) var isVisible: Bool = false

    public init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = UIColor.black.withAlphaComponent(0.01)
        isHidden = true

        connectionLostContainer.translatesAutoresizingMaskIntoConstraints = false
        connectionLostContainer.isHidden = true
        addSubview(connectionLostContainer)

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = UIColor(red: 142/255, green: 68/255, blue: 173/255, alpha: 1)
        addSubview(progressView)

        errorCard.backgroundColor = .systemBackground
        errorCard.layer.cornerRadius = 16
        errorCard.layer.shadowColor = UIColor.black.cgColor
        errorCard.layer.shadowOpacity = 0.15
        errorCard.layer.shadowRadius = 8
        errorCard.translatesAutoresizingMaskIntoConstraints = false
        errorCard.isHidden = true
        addSubview(errorCard)

        errorMessageLabel.textAlignment = .center
        errorMessageLabel.numberOfLines = 0
        errorMessageLabel.font = .systemFont(ofSize: 15, weight: .medium)
        errorMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        errorCard.addSubview(errorMessageLabel)

        retryButton.setTitle("Retry", for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        retryButton.backgroundColor = UIColor(red: 52/255, green: 152/255, blue: 219/255, alpha: 1)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.layer.cornerRadius = 12
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addTarget(self, action: #selector(onRetryTapped), for: .touchUpInside)
        errorCard.addSubview(retryButton)

        signOutButton.setTitle("Sign out", for: .normal)
        signOutButton.setTitleColor(.systemGray, for: .normal)
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        signOutButton.addTarget(self, action: #selector(onSignOutTapped), for: .touchUpInside)
        errorCard.addSubview(signOutButton)

        NSLayoutConstraint.activate([
            connectionLostContainer.topAnchor.constraint(equalTo: topAnchor),
            connectionLostContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
            connectionLostContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            connectionLostContainer.trailingAnchor.constraint(equalTo: trailingAnchor),

            progressView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2),

            errorCard.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorCard.centerYAnchor.constraint(equalTo: centerYAnchor),
            errorCard.widthAnchor.constraint(equalToConstant: 280),

            errorMessageLabel.topAnchor.constraint(equalTo: errorCard.topAnchor, constant: 24),
            errorMessageLabel.leadingAnchor.constraint(equalTo: errorCard.leadingAnchor, constant: 16),
            errorMessageLabel.trailingAnchor.constraint(equalTo: errorCard.trailingAnchor, constant: -16),

            retryButton.topAnchor.constraint(equalTo: errorMessageLabel.bottomAnchor, constant: 20),
            retryButton.leadingAnchor.constraint(equalTo: errorCard.leadingAnchor, constant: 16),
            retryButton.trailingAnchor.constraint(equalTo: errorCard.trailingAnchor, constant: -16),
            retryButton.heightAnchor.constraint(equalToConstant: 44),

            signOutButton.topAnchor.constraint(equalTo: retryButton.bottomAnchor, constant: 8),
            signOutButton.leadingAnchor.constraint(equalTo: errorCard.leadingAnchor, constant: 16),
            signOutButton.trailingAnchor.constraint(equalTo: errorCard.trailingAnchor, constant: -16),
            signOutButton.bottomAnchor.constraint(equalTo: errorCard.bottomAnchor, constant: -16)
        ])
    }

    public func show(onRetry: (() -> Void)?, onTimeoutOverride: (() -> Void)? = nil) {
        self.onRetryAction = onRetry
        isVisible = true
        isHidden = false
        errorCard.isHidden = true
        if connectionLostContainer.subviews.isEmpty { connectionLostContainer.isHidden = true }
        ambientIsland?.setLoading(true)

        timeoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            if let override = onTimeoutOverride {
                override()
            } else {
                self?.showError(message: "Connection problem. Please check your network.", onRetry: onRetry)
            }
        }
        timeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0, execute: item)
    }

    public func hide() {
        timeoutWorkItem?.cancel()
        isVisible = false
        isHidden = true
        ambientIsland?.setLoading(false)
        onErrorHidden?()
    }

    public func showError(message: String, onRetry: (() -> Void)?) {
        timeoutWorkItem?.cancel()
        self.onRetryAction = onRetry
        isVisible = true
        isHidden = false
        errorCard.isHidden = false
        connectionLostContainer.isHidden = true
        errorMessageLabel.text = message
        ambientIsland?.setLoading(false)
        onErrorShown?()
    }

    public func showConnectionLostFallback(_ view: UIView) {
        timeoutWorkItem?.cancel()
        isVisible = true
        isHidden = false
        errorCard.isHidden = true
        connectionLostContainer.isHidden = false
        connectionLostContainer.subviews.forEach { $0.removeFromSuperview() }
        view.frame = connectionLostContainer.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        connectionLostContainer.addSubview(view)
        ambientIsland?.setLoading(false)
        onErrorShown?()
    }

    public func resetFallback() {
        connectionLostContainer.isHidden = true
        connectionLostContainer.subviews.forEach { $0.removeFromSuperview() }
        errorCard.isHidden = true
    }

    public func startIslandLoading() {
        ambientIsland?.setLoading(true)
    }

    public func stopIslandLoading() {
        ambientIsland?.setLoading(false)
    }

    @objc private func onRetryTapped() {
        errorCard.isHidden = true
        ambientIsland?.setLoading(true)
        onRetryAction?()
    }

    @objc private func onSignOutTapped() {
        onSignOut?()
    }
}