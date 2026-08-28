import UIKit
import FlareClient

class LoginViewController: UIViewController {
    var baseHttpUrl: String = ""
    var wsUrl: String = ""
    var entryScreen: String = "home"
    var entryParams: [String: Any]?

    private let tfEmail = UITextField()
    private let tfPassword = UITextField()
    private let btnLogin = UIButton(type: .system)
    private let btnGuest = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 248/255, green: 249/255, blue: 250/255, alpha: 1)

        let titleLabel = UILabel()
        titleLabel.text = "🔥 Flare Demo"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        tfEmail.placeholder = "Email"
        tfEmail.borderStyle = .roundedRect
        tfEmail.autocapitalizationType = .none
        tfEmail.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tfEmail)

        tfPassword.placeholder = "Password"
        tfPassword.isSecureTextEntry = true
        tfPassword.borderStyle = .roundedRect
        tfPassword.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tfPassword)

        btnLogin.setTitle("Sign In", for: .normal)
        btnLogin.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        btnLogin.backgroundColor = UIColor(red: 142/255, green: 68/255, blue: 173/255, alpha: 1)
        btnLogin.setTitleColor(.white, for: .normal)
        btnLogin.layer.cornerRadius = 12
        btnLogin.translatesAutoresizingMaskIntoConstraints = false
        btnLogin.addTarget(self, action: #selector(handleLogin), for: .touchUpInside)
        view.addSubview(btnLogin)

        btnGuest.setTitle("Continue as Guest →", for: .normal)
        btnGuest.setTitleColor(.gray, for: .normal)
        btnGuest.translatesAutoresizingMaskIntoConstraints = false
        btnGuest.addTarget(self, action: #selector(handleGuest), for: .touchUpInside)
        view.addSubview(btnGuest)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        view.addSubview(spinner)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            tfEmail.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 32),
            tfEmail.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tfEmail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tfEmail.heightAnchor.constraint(equalToConstant: 48),

            tfPassword.topAnchor.constraint(equalTo: tfEmail.bottomAnchor, constant: 12),
            tfPassword.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            tfPassword.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            tfPassword.heightAnchor.constraint(equalToConstant: 48),

            btnLogin.topAnchor.constraint(equalTo: tfPassword.bottomAnchor, constant: 24),
            btnLogin.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            btnLogin.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            btnLogin.heightAnchor.constraint(equalToConstant: 54),

            btnGuest.topAnchor.constraint(equalTo: btnLogin.bottomAnchor, constant: 16),
            btnGuest.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            spinner.centerXAnchor.constraint(equalTo: btnLogin.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: btnLogin.centerYAnchor)
        ])
    }

    @objc private func handleLogin() {
        guard let email = tfEmail.text, !email.isEmpty,
              let password = tfPassword.text, !password.isEmpty else { return }
        makeAuthRequest(path: "/auth/login", payload: ["email": email, "password": password])
    }

    @objc private func handleGuest() {
        makeAuthRequest(path: "/auth/guest", payload: [:])
    }

    private func makeAuthRequest(path: String, payload: [String: Any]) {
        guard let url = URL(string: "\(baseHttpUrl)\(path)") else { return }
        spinner.startAnimating()
        btnLogin.isEnabled = false

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.spinner.stopAnimating()
                self.btnLogin.isEnabled = true

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = json["token"] as? String else {
                    return
                }

                let presenting = self.presentingViewController
                self.dismiss(animated: true) {
                    if let presenter = presenting {
                        FlareClientViewController.launch(from: presenter, wsUrl: self.wsUrl, entryScreen: self.entryScreen, token: token, entryParams: self.entryParams)
                    }
                }
            }
        }.resume()
    }
}