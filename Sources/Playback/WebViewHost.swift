import SwiftUI
import WebKit

/// Attaches the player's web view to the window. Rendered as a hidden 1×1 view.
struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context _: Context) -> WKWebView { self.webView }
    func updateUIView(_: WKWebView, context _: Context) {}
}
