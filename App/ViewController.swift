// Main view controller displaying application version.

import UIKit
#if canImport(ExVaultCore)
import ExVaultCore
#endif

final class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.textAlignment = .center
        label.font = UIFont(name: "Menlo", size: 18) ?? UIFont.systemFont(ofSize: 18)
        #if canImport(ExVaultCore)
        label.text = "ExVault " + ExVaultInfo.version
        #else
        label.text = "ExVault 1.0"
        #endif

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
