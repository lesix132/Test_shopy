import SwiftUI
import WebKit

/// SwiftUI wrapper around `WKWebView`, working on both iOS and macOS. Uses the
/// persistent default data store so logins (email, job sites) stick across
/// launches — the user browses with their own session.
struct WebView {
    let model: WebViewModel

    @MainActor
    fileprivate func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.webView = webView
        webView.load(URLRequest(url: model.initialURL))
        return webView
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let model: WebViewModel
        init(model: WebViewModel) { self.model = model }

        private func sync() {
            MainActor.assumeIsolated { model.syncState() }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { sync() }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync() }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { sync() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { sync() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) { sync() }
    }
}

#if os(iOS)
extension WebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
extension WebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(coordinator: context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
