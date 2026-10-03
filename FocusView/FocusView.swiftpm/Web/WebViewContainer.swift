import SwiftUI
import WebKit

/// Hosts the controller's WKWebView in SwiftUI. All behaviour lives in
/// `BrowserController`; this type only puts the view on screen.
struct WebViewContainer: UIViewRepresentable {
    let controller: BrowserController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
