// Main view controller displaying server status, credentials, and logs.
import UIKit
#if canImport(ExVaultCore)
import ExVaultCore
#endif

final class ViewController: UIViewController {
    private let serverProvider: () -> VaultServer?
    private weak var keepAlive: KeepAlive?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let urlLabel = UILabel()
    private let userLabel = UILabel()
    private let passHeaderLabel = UILabel()
    private let passValueLabel = UILabel()
    private let diskLabel = UILabel()
    private let sessionsLabel = UILabel()
    private let logHeaderLabel = UILabel()
    private let logContentLabel = UILabel()

    private let buttonStack = UIStackView()
    private let dimButton = UIButton(type: .system)
    private let copyPassButton = UIButton(type: .system)

    private var timer: Timer?
    private let startTime = Date()
    private var errorMessage: String?

    init(keepAlive: KeepAlive? = nil, serverProvider: @escaping () -> VaultServer? = { nil }) {
        self.keepAlive = keepAlive
        self.serverProvider = serverProvider
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateDashboard()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateDashboard()
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

    func setErrorMessage(_ msg: String) {
        self.errorMessage = msg
        updateDashboard()
    }

    private func setupUI() {
        view.backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.alignment = .fill
        stackView.distribution = .fill
        scrollView.addSubview(stackView)

        let safeGuide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeGuide.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32)
        ])

        let font = UIFont(name: "Menlo", size: 13) ?? UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        func configureMonospaceLabel(_ label: UILabel) {
            label.font = font
            label.textColor = .white
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
        }

        configureMonospaceLabel(titleLabel)
        titleLabel.text = "EXVAULT  v\(ExVaultInfo.version)"

        configureMonospaceLabel(statusLabel)
        configureMonospaceLabel(urlLabel)
        configureMonospaceLabel(userLabel)
        configureMonospaceLabel(passHeaderLabel)
        passHeaderLabel.text = "Pass   :"

        passValueLabel.font = UIFont(name: "Menlo-Bold", size: 22) ?? UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        passValueLabel.textColor = .white
        passValueLabel.numberOfLines = 1

        configureMonospaceLabel(diskLabel)
        configureMonospaceLabel(sessionsLabel)

        configureMonospaceLabel(logHeaderLabel)
        logHeaderLabel.text = "\n--- log (latest 10) ---"

        configureMonospaceLabel(logContentLabel)
        logContentLabel.textColor = UIColor(white: 0.8, alpha: 1.0)

        // Buttons
        buttonStack.axis = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        dimButton.setTitle("Dim screen", for: .normal)
        dimButton.titleLabel?.font = font
        dimButton.setTitleColor(.black, for: .normal)
        dimButton.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        dimButton.layer.cornerRadius = 6
        dimButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        dimButton.addTarget(self, action: #selector(handleDimPressed), for: .touchUpInside)

        copyPassButton.setTitle("Copy pass", for: .normal)
        copyPassButton.titleLabel?.font = font
        copyPassButton.setTitleColor(.black, for: .normal)
        copyPassButton.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
        copyPassButton.layer.cornerRadius = 6
        copyPassButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        copyPassButton.addTarget(self, action: #selector(handleCopyPassPressed), for: .touchUpInside)

        buttonStack.addArrangedSubview(dimButton)
        buttonStack.addArrangedSubview(copyPassButton)

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(statusLabel)
        stackView.addArrangedSubview(urlLabel)
        stackView.addArrangedSubview(userLabel)
        stackView.addArrangedSubview(passHeaderLabel)
        stackView.addArrangedSubview(passValueLabel)
        stackView.addArrangedSubview(diskLabel)
        stackView.addArrangedSubview(sessionsLabel)
        stackView.addArrangedSubview(buttonStack)
        stackView.addArrangedSubview(logHeaderLabel)
        stackView.addArrangedSubview(logContentLabel)
    }

    private func updateDashboard() {
        let server = serverProvider()

        // Uptime calculation
        let elapsed = Int(Date().timeIntervalSince(startTime))
        let hrs = elapsed / 3600
        let mins = (elapsed % 3600) / 60
        let secs = elapsed % 60
        let uptimeStr = String(format: "%02d:%02d:%02d", hrs, mins, secs)

        if let err = errorMessage {
            statusLabel.text = "Status : ERROR \(err)"
            statusLabel.textColor = UIColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        } else if server != nil {
            statusLabel.text = "Status : RUNNING  (uptime \(uptimeStr))"
            statusLabel.textColor = .white
        } else {
            statusLabel.text = "Status : STARTING..."
            statusLabel.textColor = .white
        }

        // IP / URL
        let port = server?.boundPort ?? 8080
        let ips = Net.localIpv4Addresses()
        if ips.isEmpty {
            urlLabel.text = "URL    : (no network)"
        } else {
            let urls = ips.map { "URL    : http://\($0):\(port)" }
            urlLabel.text = urls.joined(separator: "\n")
        }

        // User and Pass
        if let creds = server?.currentCredentials {
            userLabel.text = "User   : \(creds.username)"
            passValueLabel.text = creds.password
        } else {
            userLabel.text = "User   : -"
            passValueLabel.text = "-"
        }

        // Disk space
        if let freeBytes = server?.diskFreeBytes {
            diskLabel.text = "Disk   : \(formatBytes(freeBytes)) free"
        } else {
            diskLabel.text = "Disk   : -"
        }

        // Sessions count
        let sessionCount = server?.activeSessionCount ?? 0
        sessionsLabel.text = "Sessions: \(sessionCount)/3"

        // Logs
        let logs = Log.recentLines(10)
        logContentLabel.text = logs.isEmpty ? "(no logs yet)" : logs.joined(separator: "\n")
    }

    @objc private func handleDimPressed() {
        keepAlive?.setDim(true)
    }

    @objc private func handleCopyPassPressed() {
        if let pass = serverProvider()?.currentCredentials.password {
            UIPasteboard.general.string = pass
            copyPassButton.setTitle("Copied!", for: .normal)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.copyPassButton.setTitle("Copy pass", for: .normal)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_000_000_000 {
            return String(format: "%.1f GB", b / 1_000_000_000.0)
        } else if b >= 1_000_000 {
            return String(format: "%.1f MB", b / 1_000_000.0)
        } else if b >= 1_000 {
            return String(format: "%.1f KB", b / 1_000.0)
        }
        return "\(bytes) B"
    }

    deinit {
        timer?.invalidate()
    }
}
