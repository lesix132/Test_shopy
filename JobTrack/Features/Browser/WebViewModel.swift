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

    // MARK: Auto-scan

    private let defaults = UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    private let autoScanKey = "web.autoscan.enabled"

    /// When on, each finished page is analysed and a matching offer is outlined.
    /// Off by default — analysis is on-demand via the "Analyser" action.
    var autoScanEnabled: Bool {
        didSet { defaults.set(autoScanEnabled, forKey: autoScanKey) }
    }
    /// Minimum match (%) for an auto-detected offer to be surfaced.
    static let autoMatchThreshold = 30
    /// URLs already scanned this session, so we don't re-analyse (and re-bill) them.
    private var scannedURLs: Set<String> = []

    init() {
        autoScanEnabled = defaults.object(forKey: autoScanKey) as? Bool ?? false
    }

    /// Marks `url` as scanned; returns true only the first time it's seen.
    func markScannedIfNew(_ url: URL) -> Bool {
        scannedURLs.insert(url.absoluteString).inserted
    }

    /// Cheap client-side pre-filter so we only call the AI on pages that look
    /// like a job offer — avoids scanning every random page.
    static func looksLikeJobPage(_ text: String) -> Bool {
        guard text.count > 300 else { return false }
        let t = text.lowercased()
        let signals = ["offre d'emploi", "poste", "cdi", "cdd", "alternance", "stage",
                       "mission", "profil recherché", "expérience", "recrut", "candidat",
                       "compétences", "salaire", "télétravail", "job", "apply", "hiring"]
        return signals.filter { t.contains($0) }.count >= 2
    }

    /// Outlines the likely offer on the page and shows a floating match badge.
    func highlightMatch(score: Int) async {
        guard let webView else { return }
        let js = """
        (function(){
          try{
            var prev=document.getElementById('__jt_badge'); if(prev) prev.remove();
            var old=document.querySelector('[data-jt-outline]');
            if(old){ old.style.outline=''; old.style.outlineOffset=''; old.removeAttribute('data-jt-outline'); }
            var el=document.querySelector('main')||document.querySelector('article')||document.querySelector('[role=main]');
            if(!el){
              var best=null,bestLen=0;
              document.querySelectorAll('section,div').forEach(function(n){
                var len=(n.innerText||'').length;
                if(len>bestLen && len<20000){bestLen=len;best=n;}
              });
              el=best||document.body;
            }
            el.setAttribute('data-jt-outline','1');
            el.style.outline='3px solid #34C759';
            el.style.outlineOffset='6px';
            el.style.borderRadius='10px';
            el.scrollIntoView({behavior:'smooth',block:'start'});
            var b=document.createElement('div'); b.id='__jt_badge';
            b.textContent='✓ Offre compatible à \(score)%';
            b.style.cssText='position:fixed;top:12px;left:50%;transform:translateX(-50%);'+
              'z-index:2147483647;background:#34C759;color:#fff;padding:8px 14px;'+
              'border-radius:20px;font:600 14px -apple-system,system-ui,sans-serif;'+
              'box-shadow:0 4px 12px rgba(0,0,0,.25);';
            document.body.appendChild(b);
          }catch(e){}
        })();
        """
        _ = try? await webView.evaluateJavaScript(js)
    }

    /// Removes any outline/badge added by `highlightMatch`.
    func clearHighlight() async {
        guard let webView else { return }
        let js = """
        (function(){
          var b=document.getElementById('__jt_badge'); if(b) b.remove();
          var o=document.querySelector('[data-jt-outline]');
          if(o){ o.style.outline=''; o.style.outlineOffset=''; o.removeAttribute('data-jt-outline'); }
        })();
        """
        _ = try? await webView.evaluateJavaScript(js)
    }

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
    func reloadOrStop() {
        if isLoading { webView?.stopLoading() } else { webView?.reload() }
    }

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

    /// Best-effort autofill of standard application-form fields (name, email,
    /// phone) from the profile. Works on many sites, not all. User-initiated.
    func autofillStandardFields(fullName: String, email: String, phone: String) async {
        guard let webView else { return }
        let js = """
        (function(){
          function setVal(el,val){ if(!el||!val) return false;
            el.focus(); el.value = val;
            el.dispatchEvent(new Event('input',{bubbles:true}));
            el.dispatchEvent(new Event('change',{bubbles:true})); return true; }
          var email = \(Self.jsString(email));
          var name = \(Self.jsString(fullName));
          var phone = \(Self.jsString(phone));
          var parts = name.split(' '); var first = parts.shift()||''; var last = parts.join(' ');
          var n = 0;
          document.querySelectorAll('input, textarea').forEach(function(el){
            var k = ((el.name||'')+' '+(el.id||'')+' '+(el.autocomplete||'')+' '+
                     (el.placeholder||'')+' '+(el.type||'')).toLowerCase();
            if(el.type==='email' || k.indexOf('email')>=0 || k.indexOf('mail')>=0){ if(setVal(el,email))n++; }
            else if(k.indexOf('phone')>=0||k.indexOf('tel')>=0||k.indexOf('mobile')>=0){ if(setVal(el,phone))n++; }
            else if(k.indexOf('given')>=0||k.indexOf('first')>=0||k.indexOf('prenom')>=0||k.indexOf('prénom')>=0){ if(setVal(el,first))n++; }
            else if(k.indexOf('family')>=0||k.indexOf('last')>=0||k.indexOf('surname')>=0){ if(setVal(el,last))n++; }
            else if(k.indexOf('fullname')>=0||k.indexOf('full-name')>=0||k.indexOf('name')>=0){ if(setVal(el,name))n++; }
          });
          return n;
        })();
        """
        _ = try? await webView.evaluateJavaScript(js)
    }

    /// JSON-encodes a string so it can be safely embedded in JavaScript.
    private static func jsString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "\"\""
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
