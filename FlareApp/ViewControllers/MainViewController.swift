import UIKit
import FlareClient

class MainViewController: UIViewController {

    private let tfUrl = UITextField()
    private let btnConnect = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 248/255, green: 249/255, blue: 250/255, alpha: 1)

        let titleLabel = UILabel()
        titleLabel.text = "🔥 Flare Dev Client (iOS)"
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        tfUrl.placeholder = "http://localhost:4000/"
        tfUrl.text = UserDefaults.standard.string(forKey: "last_http_url") ?? "http://localhost:4000/"
        tfUrl.borderStyle = .roundedRect
        tfUrl.autocapitalizationType = .none
        tfUrl.autocorrectionType = .no
        tfUrl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tfUrl)

        btnConnect.setTitle("CONNECT TO APP", for: .normal)
        btnConnect.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        btnConnect.backgroundColor = UIColor(red: 52/255, green: 152/255, blue: 219/255, alpha: 1)
        btnConnect.setTitleColor(.white, for: .normal)
        btnConnect.layer.cornerRadius = 12
        btnConnect.translatesAutoresizingMaskIntoConstraints = false
        btnConnect.addTarget(self, action: #selector(onConnectClicked), for: .touchUpInside)
        view.addSubview(btnConnect)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            tfUrl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 36),
            tfUrl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tfUrl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tfUrl.heightAnchor.constraint(equalToConstant: 50),

            btnConnect.topAnchor.constraint(equalTo: tfUrl.bottomAnchor, constant: 20),
            btnConnect.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            btnConnect.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            btnConnect.heightAnchor.constraint(equalToConstant: 54)
        ])
    }

    @objc private func onConnectClicked() {
        guard let rawUrl = tfUrl.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: rawUrl) else { return }

        UserDefaults.standard.set(rawUrl, forKey: "last_http_url")

        let scheme = url.scheme == "https" ? "https" : "http"
        let wsScheme = url.scheme == "https" ? "wss" : "ws"
        let host = url.host ?? "localhost"
        let portStr = url.port != nil ? ":\(url.port!)" : ""

        let baseHttpUrl = "\(scheme)://\(host)\(portStr)"
        let wsUrl = "\(wsScheme)://\(host)\(portStr)/socket"

        var entryScreen = "home"
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.isEmpty { entryScreen = path }

        var entryParams: [String: Any]?
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems {
            var p = [String: Any]()
            for item in items { p[item.name] = item.value ?? "" }
            entryParams = p
        }

        if let storedToken = UserDefaults.standard.string(forKey: "flare_auth_token") {
            FlareClientViewController.launch(from: self, wsUrl: wsUrl, entryScreen: entryScreen, token: storedToken, entryParams: entryParams)
        } else {
            let loginVC = LoginViewController()
            loginVC.baseHttpUrl = baseHttpUrl
            loginVC.wsUrl = wsUrl
            loginVC.entryScreen = entryScreen
            loginVC.entryParams = entryParams
            loginVC.modalPresentationStyle = .fullScreen
            present(loginVC, animated: true)
        }
    }
}