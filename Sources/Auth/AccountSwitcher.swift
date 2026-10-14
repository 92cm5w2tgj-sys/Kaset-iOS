import Foundation
import WebKit

/// Re-points the shared web session at another identity (personal or brand account).
///
/// Each account carries a server-issued sign-in URL; loading it in a web view that shares the
/// default data store switches the active delegated identity for every web view, including
/// playback. API calls additionally send `onBehalfOfUser` (see `YTMusicClient.brandIdProvider`).
@MainActor
final class AccountSwitcher: NSObject, WKNavigationDelegate {
    static let brandIdKey = "settings.brandAccountId"

    private var continuation: CheckedContinuation<Void, Never>?
    private var webView: WKWebView?

    static var storedBrandId: String? {
        UserDefaults.standard.string(forKey: self.brandIdKey)
    }

    /// Loads the account's sign-in URL and waits for the navigation to settle (or time out).
    func switchSession(to account: UserAccount) async {
        UserDefaults.standard.set(account.brandId, forKey: Self.brandIdKey)
        guard let url = account.signinURL else { return }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            webView.load(URLRequest(url: url))
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.finish()
            }
        }
    }

    private func finish() {
        self.webView?.stopLoading()
        self.webView = nil
        self.continuation?.resume()
        self.continuation = nil
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) { self.finish() }
    func webView(_: WKWebView, didFail _: WKNavigation!, withError _: Error) { self.finish() }
    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) { self.finish() }
}
