import Foundation
import Observation
import WebKit

/// Drives the in-app browser. Holds navigation state and captures the current
/// page's visible text on demand (user-initiated import — not scraping).
@MainActor
@Observable
final class WebViewModel {

    var addressText = ""
    private(set) var currentURL: URL?
    private(set) var pageTitle = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    /// A weak reference to the live WKWebView, set by the representable.
    weak var webView: WKWebView?

    /// The page to load once the web view is created.
    var initialURL = URL(string: "https://candidat.francetravail.fr")!

    init() {}

    // MARK: Navigation

    func load(_ string: String) {
        guard let url = Self.normalizedURL(from: string) else { return }
        addressText = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func loadURL(_ url: URL) {
        addressText = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reloadOrStop() { isLoading ? webView?.stopLoading() : webView?.reload() }

    /// Called by the coordinator on navigation events.
    func syncState() {
        guard let webView else { return }
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? ""
        if let url = webView.url {
            currentURL = url
            addressText = url.absoluteString
        }
    }

    // MARK: Import

    /// Returns the visible text of the current page (user-initiated capture).
    func captureVisibleText() async -> String? {
        guard let webView else { return nil }
        let result = try? await webView.evaluateJavaScript("document.body.innerText")
        return (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Helpers

    /// Turns raw input into a URL: a full URL, a bare domain, or a web search.
    static func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let looksLikeDomain = trimmed.contains(".") && !trimmed.contains(" ")
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if looksLikeDomain {
            return URL(string: "https://\(trimmed)")
        }
        // Fall back to a search query.
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://duckduckgo.com/?q=\(q)")
    }
}

/// Quick shortcuts shown in the browser.
struct WebShortcut: Identifiable {
    let id = UUID()
    let name: String
    let systemImage: String
    let url: URL

    static let all: [WebShortcut] = [
        .init(name: "Gmail", systemImage: "envelope", url: URL(string: "https://mail.google.com")!),
        .init(name: "Outlook", systemImage: "envelope", url: URL(string: "https://outlook.live.com/mail")!),
        .init(name: "LinkedIn", systemImage: "link", url: URL(string: "https://www.linkedin.com/jobs")!),
        .init(name: "Indeed", systemImage: "magnifyingglass", url: URL(string: "https://fr.indeed.com")!),
        .init(name: "France Travail", systemImage: "building.2", url: URL(string: "https://candidat.francetravail.fr")!),
        .init(name: "Welcome to the Jungle", systemImage: "leaf", url: URL(string: "https://www.welcometothejungle.com")!),
        .init(name: "APEC", systemImage: "briefcase", url: URL(string: "https://www.apec.fr")!),
    ]
}
