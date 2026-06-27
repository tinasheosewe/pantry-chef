import UIKit

/// The share-sheet entry point. Its only job is to be *fast and reliable*: pull the
/// shared URL or text out of the extension context, drop it in the App-Group inbox, and
/// get out of the way. The slow, network-bound, memory-hungry AI import happens later, in
/// the main app, when it drains the inbox — never here, where the extension has a tight
/// memory budget and the user is waiting on a share sheet.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await capture() }
    }

    private func capture() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        if let pending = await ShareItemExtractor.extract(from: items) {
            SharedRecipeInbox.add(pending)
            await flash("Saved to PantryChef", success: true)
        } else {
            await flash("Couldn’t read that", success: false)
        }
        try? await Task.sleep(nanoseconds: 650_000_000)
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    @MainActor
    private func flash(_ text: String, success: Bool) {
        label.text = text
        check.text = success ? "✓" : "—"
    }

    // MARK: - Minimal confirmation card (UIKit, no storyboard)

    private let check: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 34, weight: .semibold)
        l.textColor = UIColor(red: 0.75, green: 0.23, blue: 0.17, alpha: 1) // paprika
        l.textAlignment = .center
        l.text = "·"
        return l
    }()

    private let label: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15, weight: .medium)
        l.textColor = UIColor(red: 0.14, green: 0.25, blue: 0.17, alpha: 1) // ink
        l.textAlignment = .center
        l.numberOfLines = 2
        l.text = "Saving…"
        return l
    }()

    private lazy var card: UIView = {
        let stack = UIStackView(arrangedSubviews: [check, label])
        stack.axis = .vertical
        stack.spacing = 6
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 22, left: 26, bottom: 22, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.backgroundColor = UIColor(red: 0.97, green: 0.965, blue: 0.93, alpha: 1) // cream
        stack.layer.cornerRadius = 3
        stack.layer.borderWidth = 1
        stack.layer.borderColor = UIColor(red: 0.14, green: 0.25, blue: 0.17, alpha: 0.25).cgColor
        return stack
    }()
}
