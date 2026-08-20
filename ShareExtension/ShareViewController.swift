// The share extension UI is implemented with UIKit (iOS / Mac Catalyst).
// On a native macOS build this file compiles to nothing; see SETUP.md for the
// AppKit-based macOS share extension follow-up.
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point.
///
/// It captures the shared text and/or URL from Safari or the LinkedIn app,
/// writes a `PendingImport` into the shared App Group inbox (`ImportInbox`),
/// and returns. The main app drains the inbox on next launch/foreground and
/// (optionally) parses the offer with Claude.
///
/// Kept deliberately simple and non-blocking: no network calls happen here.
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleShare()
    }

    private func handleShare() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return complete()
        }

        Task {
            var collectedText: String?
            var collectedURL: String?

            for item in extensionItems {
                for provider in item.attachments ?? [] {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                       collectedURL == nil {
                        collectedURL = await loadURL(from: provider)
                    }
                    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                       collectedText == nil {
                        collectedText = await loadText(from: provider)
                    }
                }
                // Fall back to the item's own attributed content title.
                if collectedText == nil, let attributed = item.attributedContentText?.string,
                   !attributed.isEmpty {
                    collectedText = attributed
                }
            }

            let rawText = [collectedText, collectedURL]
                .compactMap { $0 }
                .joined(separator: "\n")

            if !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let item = PendingImport(rawText: rawText, sourceURL: collectedURL)
                try? ImportInbox.enqueue(item)
                await showConfirmation()
            }
            complete()
        }
    }

    // MARK: - Item loading

    private func loadURL(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { data, _ in
                if let url = data as? URL {
                    continuation.resume(returning: url.absoluteString)
                } else if let string = data as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { data, _ in
                continuation.resume(returning: data as? String)
            }
        }
    }

    // MARK: - UI feedback

    @MainActor
    private func showConfirmation() async {
        await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Ajouté à JobTrack",
                message: "L'offre a été importée. Ouvrez JobTrack pour l'analyser.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            present(alert, animated: true)
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
#endif
