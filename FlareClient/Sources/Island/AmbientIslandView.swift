import UIKit

/// High-polish Dynamic Island matching Android's AmbientIslandView.
/// Features a continuous 3-dot staggered wave morph and an infinite holographic shimmer sweep.
public final class AmbientIslandView: UIView {
    private let idleWidth: CGFloat = 115
    private let idleHeight: CGFloat = 36
    private let activeWidth: CGFloat = 195
    private let minDisplayMs: TimeInterval = 0.6

    private var idleContainer = UIStackView()
    private var activeContainer = UIStackView()
    private var dot1 = UIView()
    private var dot2 = UIView()
    private var dot3 = UIView()
    private var shimmerBeam = UIView()
    private var beamTrack = UIView()

    public private(set) var isLoading: Bool = false
    private var isHeroCentered: Bool = false
    private var loadStartTime: TimeInterval = 0
    private var pendingExitWorkItem: DispatchWorkItem?

    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    public init() {
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = UIColor(red: 16/255, green: 16/255, blue: 23/255, alpha: 0.95)
        layer.cornerRadius = idleHeight / 2
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
        clipsToBounds = true

        // Idle Container
        idleContainer.axis = .horizontal
        idleContainer.alignment = .center
        idleContainer.spacing = 8
        idleContainer.translatesAutoresizingMaskIntoConstraints = false

        let purpleDot = UIView()
        purpleDot.backgroundColor = UIColor(red: 155/255, green: 81/255, blue: 224/255, alpha: 1)
        purpleDot.layer.cornerRadius = 3.5
        purpleDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            purpleDot.widthAnchor.constraint(equalToConstant: 7),
            purpleDot.heightAnchor.constraint(equalToConstant: 7)
        ])

        let label = UILabel()
        label.text = "Flare"
        label.textColor = .white
        label.font = .systemFont(ofSize: 12, weight: .semibold)

        idleContainer.addArrangedSubview(purpleDot)
        idleContainer.addArrangedSubview(label)
        addSubview(idleContainer)

        // Active Container (Wave + Shimmer)
        activeContainer.axis = .vertical
        activeContainer.alignment = .center
        activeContainer.spacing = 4
        activeContainer.alpha = 0
        activeContainer.isHidden = true
        activeContainer.translatesAutoresizingMaskIntoConstraints = false

        let orbsRow = UIStackView()
        orbsRow.axis = .horizontal
        orbsRow.spacing = 8
        dot1 = createOrb(color: UIColor(red: 142/255, green: 68/255, blue: 173/255, alpha: 1))
        dot2 = createOrb(color: UIColor(red: 0/255, green: 229/255, blue: 255/255, alpha: 1))
        dot3 = createOrb(color: UIColor(red: 255/255, green: 42/255, blue: 133/255, alpha: 1))
        orbsRow.addArrangedSubview(dot1)
        orbsRow.addArrangedSubview(dot2)
        orbsRow.addArrangedSubview(dot3)

        beamTrack.backgroundColor = UIColor.white.withAlphaComponent(0.1)
        beamTrack.layer.cornerRadius = 1
        beamTrack.clipsToBounds = true
        beamTrack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            beamTrack.widthAnchor.constraint(equalToConstant: 110),
            beamTrack.heightAnchor.constraint(equalToConstant: 2)
        ])

        shimmerBeam.backgroundColor = UIColor(red: 0/255, green: 229/255, blue: 255/255, alpha: 1)
        shimmerBeam.layer.cornerRadius = 1
        shimmerBeam.frame = CGRect(x: -45, y: 0, width: 45, height: 2)
        beamTrack.addSubview(shimmerBeam)

        activeContainer.addArrangedSubview(orbsRow)
        activeContainer.addArrangedSubview(beamTrack)
        addSubview(activeContainer)

        NSLayoutConstraint.activate([
            idleContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            idleContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            activeContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            activeContainer.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        widthConstraint = widthAnchor.constraint(equalToConstant: idleWidth)
        heightConstraint = heightAnchor.constraint(equalToConstant: idleHeight)
        widthConstraint?.isActive = true
        heightConstraint?.isActive = true
    }

    private func createOrb(color: UIColor) -> UIView {
        let v = UIView()
        v.backgroundColor = color
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 8),
            v.heightAnchor.constraint(equalToConstant: 8)
        ])
        return v
    }

    public func setupInitialHeroState() {
        isHeroCentered = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let superview = self.superview else { return }
            self.transform = CGAffineTransform(translationX: 0, y: (superview.bounds.height / 2) - 50)
                .scaledBy(x: 1.15, y: 1.15)
            self.setLoading(true)
        }
    }

    public func flyToTop() {
        guard isHeroCentered else { return }
        isHeroCentered = false

        UIView.animate(withDuration: 0.52, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            self.transform = .identity
        }) { _ in
            self.stopLoadingGracefully()
        }
    }

    public func setLoading(_ loading: Bool) {
        if isLoading == loading { return }
        pendingExitWorkItem?.cancel()
        pendingExitWorkItem = nil

        if loading {
            isLoading = true
            loadStartTime = Date().timeIntervalSince1970
            startLoadingAnimation()
        } else {
            if isHeroCentered { return }
            let elapsed = Date().timeIntervalSince1970 - loadStartTime
            if elapsed < minDisplayMs {
                let item = DispatchWorkItem { [weak self] in self?.stopLoadingGracefully() }
                pendingExitWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + (minDisplayMs - elapsed), execute: item)
            } else {
                stopLoadingGracefully()
            }
        }
    }

    private func startLoadingAnimation() {
        widthConstraint?.constant = activeWidth
        UIView.animate(withDuration: 0.3) {
            self.idleContainer.alpha = 0
            self.idleContainer.isHidden = true
            self.activeContainer.alpha = 1
            self.activeContainer.isHidden = false
            self.superview?.layoutIfNeeded()
        }

        // 3-Orb Staggered Wave Pulse
        animateOrb(dot1, delay: 0.0)
        animateOrb(dot2, delay: 0.16)
        animateOrb(dot3, delay: 0.32)

        // Continuous Shimmer Sweep
        let beamAnim = CABasicAnimation(keyPath: "position.x")
        beamAnim.fromValue = -22.5
        beamAnim.toValue = 132.5
        beamAnim.duration = 0.9
        beamAnim.repeatCount = .infinity
        beamAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerBeam.layer.add(beamAnim, forKey: "shimmer_sweep")
    }

    private func animateOrb(_ view: UIView, delay: TimeInterval) {
        let anim = CAKeyframeAnimation(keyPath: "transform.scale")
        anim.values = [0.6, 1.4, 0.6]
        anim.keyTimes = [0.0, 0.5, 1.0]
        anim.duration = 0.7
        anim.beginTime = CACurrentMediaTime() + delay
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(anim, forKey: "orb_pulse")
    }

    private func stopLoadingGracefully() {
        isLoading = false
        dot1.layer.removeAnimation(forKey: "orb_pulse")
        dot2.layer.removeAnimation(forKey: "orb_pulse")
        dot3.layer.removeAnimation(forKey: "orb_pulse")
        shimmerBeam.layer.removeAnimation(forKey: "shimmer_sweep")

        widthConstraint?.constant = idleWidth
        UIView.animate(withDuration: 0.28) {
            self.activeContainer.alpha = 0
            self.activeContainer.isHidden = true
            self.idleContainer.alpha = 1
            self.idleContainer.isHidden = false
            self.superview?.layoutIfNeeded()
        }
    }
}