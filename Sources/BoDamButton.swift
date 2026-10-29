import SwiftUI
import WebKit

/// Bộ đàm quầy (29/10/2026) — nút ở thanh dưới tab Đơn, cạnh nút xem màn hình Desktop. Giữ nút là app này
/// và máy quầy (Desktop bật Bộ đàm) cùng nói chuyện, thả ra là cả 2 mic tắt; máy quầy tự nhận, không ai phải
/// bấm. Tiếng đi WebRTC trong một WKWebView ẩn nạp trang {api}/bodam/?vaiTro=ql
/// (TraSuaApp.Backend/wwwroot/bodam/index.html) — khử vọng/lọc ồn/Opus của WebKit như gọi thoại.
/// Bấm lần đầu mới nối (1–2 giây, rung báo khi nói được); thả ra 3 giây không bấm lại thì ngắt hẳn (iPhone nhả
/// micro); bấm lại trong 3 giây đó là nói ngay. Ra nền cũng ngắt.
struct BoDamButton: View {
    @StateObject private var model = BoDamModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var dangGiu = false

    var body: some View {
        ZStack {
            // WebView phải nằm trong cây view thì WebKit mới chạy âm thanh/mic.
            BoDamWebView(webView: model.webView)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)

            Image(systemName: bieuTuong)
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(mau)
                .symbolEffectPulse(dangGiu && !model.dangNoi)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !dangGiu else { return }
                            dangGiu = true
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            model.giu(true)
                        }
                        .onEnded { _ in
                            guard dangGiu else { return }
                            dangGiu = false
                            model.giu(false)
                        }
                )
        }
        .overlay(alignment: .top) {
            if dangGiu || model.loi != nil {
                Text(model.moTa)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.white)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(model.mauMoTa))
                    .offset(y: -44)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: dangGiu)
        .animation(.easeOut(duration: 0.15), value: model.trangThai)
        .onAppear { model.chuanBi() }
        // Quầy gọi tới (CuocGoiQuay) — nhả máy quầy cho cuộc gọi.
        .onReceive(NotificationCenter.default.publisher(for: .cuocGoiQuayBatDau)) { _ in
            dangGiu = false
            model.dung()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                dangGiu = false
                model.dung()
            }
        }
        .accessibilityLabel("Bộ đàm quầy — giữ để nói")
    }

    private var bieuTuong: String {
        if model.dangNoi { return "waveform.circle.fill" }
        return "antenna.radiowaves.left.and.right"
    }

    private var mau: Color {
        if model.dangNoi { return .red }
        if dangGiu { return .orange }
        return .brandPrimary
    }
}

private extension View {
    /// Nhấp nháy lúc đang nối (bấm rồi nhưng chưa nói được).
    @ViewBuilder func symbolEffectPulse(_ on: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, isActive: on)
        } else {
            self.opacity(on ? 0.6 : 1)
        }
    }
}

@MainActor
final class BoDamModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    @Published var trangThai = "dung"
    @Published var loi: String?
    private var chay = false
    private var daNap = false
    private var dangNap = false
    private var muonNoi = false
    private var henNgat: Task<Void, Never>?
    private var henXoaLoi: Task<Void, Never>?

    /// Thả nút xong giữ kết nối bao lâu (bấm lại trong khoảng này là nói ngay).
    private static let giuKetNoi: UInt64 = 3

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let proxy = BoDamMessageProxy()
        config.userContentController.add(proxy, name: "bodam")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        super.init()
        proxy.model = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    var dangNoi: Bool { trangThai == "dangNoi" }

    var moTa: String {
        if let loi { return loi }
        switch trangThai {
        case "dangNoi": return "Đang nói với quầy"
        case "sanSang": return "Đã nối quầy"
        case "khongThayQuay": return "Không thấy máy quầy"
        case "quayBan": return "Quầy đang nói với máy khác"
        case "matMang": return "Mất mạng, đang thử lại…"
        default: return "Đang nối quầy…"
        }
    }

    var mauMoTa: Color {
        if loi != nil { return .red }
        switch trangThai {
        case "dangNoi": return .red
        case "sanSang": return .green
        case "khongThayQuay", "quayBan", "matMang": return .orange
        default: return .gray
        }
    }

    /// Nạp sẵn trang (chưa xin mic, chưa nối) để lần bấm đầu đỡ mất thời gian tải.
    func chuanBi() {
        guard !daNap, !dangNap else { return }
        dangNap = true
        let url = URL(string: Prefs.apiBase + "/bodam/?vaiTro=ql")!
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    func giu(_ on: Bool) {
        muonNoi = on
        henNgat?.cancel()
        if on {
            loi = nil
            if CuocGoiQuay.shared.dangCo {
                muonNoi = false
                baoLoi("Đang có cuộc gọi với quầy")
                return
            }
            if !chay { batDau() }
            if trangThai == "sanSang" || trangThai == "dangNoi" { chayJS("boDam.noi(true)") }
        } else {
            chayJS("boDam.noi(false)")
            henNgat = Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.giuKetNoi * 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.dung()
            }
        }
    }

    private func batDau() {
        chay = true
        trangThai = "dangKetNoi"
        guard daNap else { chuanBi(); return }
        // Trang nạp hỏng (lỗi mạng/server lúc nạp sẵn) thì không có window.boDam — nạp lại từ đầu.
        webView.evaluateJavaScript("typeof window.boDam") { [weak self] value, _ in
            Task { @MainActor in
                guard let self, self.chay else { return }
                if (value as? String) == "object" {
                    self.guiToken()
                    self.chayJS("boDam.batDau()")
                } else {
                    self.daNap = false
                    self.chuanBi()
                }
            }
        }
    }

    func dung() {
        henNgat?.cancel()
        muonNoi = false
        guard chay else { return }
        chay = false
        trangThai = "dung"
        chayJS("boDam.dung()")
    }

    fileprivate func nhanTin(_ body: Any) {
        guard let dict = body as? [String: Any], let loai = dict["loai"] as? String else { return }
        let giaTri = dict["giaTri"] as? String ?? ""
        if loai == "trangThai" {
            if giaTri == "sanSangNap" || !chay { return }
            let cu = trangThai
            trangThai = giaTri
            if giaTri == "sanSang", cu != "sanSang", cu != "dangNoi", muonNoi {
                // Vừa nối xong mà tay vẫn giữ nút → mở mic luôn, rung báo "nói được rồi".
                chayJS("boDam.noi(true)")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else if giaTri == "khongThayQuay", muonNoi {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        } else if loai == "loi" {
            if giaTri.contains("NotAllowed") || giaTri.lowercased().contains("permission") {
                baoLoi("Chưa cho phép micro — Cài đặt → ĐENN → Micro")
                dung()
            }
        }
    }

    private func baoLoi(_ text: String) {
        loi = text
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        henXoaLoi?.cancel()
        henXoaLoi = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.loi = nil
        }
    }

    private func guiToken() {
        let token = Prefs.token ?? ""
        guard let data = try? JSONSerialization.data(withJSONObject: [token]),
              let json = String(data: data, encoding: .utf8) else { return }
        chayJS("boDam.setToken(\(json)[0])")
    }

    private func chayJS(_ js: String) {
        // evaluateJavaScript là method Objective-C — không kéo libswiftWebKit (xem WebKitJS.swift).
        webView.evaluateJavaScript("window.boDam && \(js)", completionHandler: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.dangNap = false
            let value = try? await self.webView.evaluateJavaScriptObjC("typeof window.boDam")
            self.daNap = (value as? String) == "object"
            guard self.chay else { return }
            if self.daNap {
                self.guiToken()
                self.chayJS("boDam.batDau()")
            } else {
                // Server trả trang lỗi (vd 401/502) — thử lại sau 3 giây.
                self.trangThai = "matMang"
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if self.chay, !self.daNap { self.chuanBi() }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.dangNap = false
            if self.chay { self.trangThai = "matMang" }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !self.daNap else { return }
            self.chuanBi()
        }
    }

    // Trang của chính mình xin micro — cho luôn, khỏi hộp hỏi lần 2 của WebKit. Quyền micro của app
    // (NSMicrophoneUsageDescription) iOS vẫn hỏi một lần đầu như bình thường.
    nonisolated func webView(_ webView: WKWebView,
                             requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                             initiatedByFrame frame: WKFrameInfo,
                             type: WKMediaCaptureType,
                             decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host.hasSuffix("denncoffee.com") ? .grant : .deny)
    }
}

private extension WKWebView {
    /// Bọc evaluateJavaScript bản completion (Objective-C) thành async — tránh bản async của Swift nằm ở
    /// libswiftWebKit (iOS < 26 không có, xem WebKitJS.swift).
    func evaluateJavaScriptObjC(_ js: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { cont in
            evaluateJavaScript(js) { value, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: value) }
            }
        }
    }
}

/// WKUserContentController giữ handler mạnh — tách proxy giữ model yếu để không vòng tham chiếu.
private final class BoDamMessageProxy: NSObject, WKScriptMessageHandler {
    weak var model: BoDamModel?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor in self.model?.nhanTin(body) }
    }
}

private struct BoDamWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
