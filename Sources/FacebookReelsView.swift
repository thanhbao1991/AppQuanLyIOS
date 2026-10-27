import SwiftUI
import WebKit

/// Menu → "Reels Giả thuyết Kiến trúc" (27/10/2026, thay mục "Voucher Shopee ≥25%" đã bỏ). Mở trang Reels của
/// page Facebook "Giả thuyết Kiến trúc - Architecture hypothesis" trong WebView. Facebook bắt đăng nhập mới xem
/// được Reels — đăng nhập 1 lần ngay trong WebView, cookie lưu ở websiteDataStore mặc định nên lần sau vào thẳng.
/// Chỉ xem, không đọc/gọi gì thêm. Page của người khác nên không lấy được qua Graph API.
struct FacebookReelsView: View {
    @StateObject private var web = FacebookReelsWebModel()

    var body: some View {
        FacebookReelsWebView(webView: web.webView)
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if web.loading { ProgressView() }
            }
            .navigationTitle("Reels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        web.moLai()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
    }
}

@MainActor
private final class FacebookReelsWebModel: NSObject, ObservableObject, WKNavigationDelegate {
    static let reelsURL = URL(string: "https://m.facebook.com/Architecture.Hypothesis/reels/")!

    let webView: WKWebView
    @Published var loading = true

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Reels phát ngay trong trang, không bật trình phát toàn màn hình của iOS.
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: Self.reelsURL))
    }

    func moLai() {
        loading = true
        webView.load(URLRequest(url: Self.reelsURL))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.loading = false }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loading = false }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.loading = false }
    }
}

private struct FacebookReelsWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
