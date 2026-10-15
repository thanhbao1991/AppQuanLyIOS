import SwiftUI
import WebKit

/// Menu → "Voucher Shopee ≥20%". Mở Ví voucher của tài khoản Shopee trong WebView (dùng chung cookie đăng
/// nhập với "Nhập từ Shopee"), đợi trang tự tải xong rồi đọc chữ trên các thẻ voucher ĐANG HIỆN SẴN —
/// không gọi API, không cuộn để tải thêm, không bấm gì. Ví có hơn 2000 voucher nhưng Shopee xếp voucher
/// ngon lên đầu nên lần tải đầu (~50 thẻ) là đủ. Có mã từ 20% trở lên thì bật popup; bấm vào mã thì cuộn
/// tới thẻ đó.
/// Đọc theo chữ ("25%", "HSD", "Lưu"…) chứ không theo class CSS — Shopee đổi giao diện vẫn chạy được,
/// chỉ hỏng nếu thẻ voucher thành ảnh.
struct ShopeeVoucherView: View {
    @StateObject private var web = ShopeeVoucherWebModel()
    @State private var all: [ShopeeVoucher] = []
    @State private var found: [ShopeeVoucher] = []
    @State private var showPopup = false

    private static let nguong = 20

    var body: some View {
        ShopeeVoucherWebView(webView: web.webView)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Voucher Shopee ≥\(Self.nguong)%")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if web.scanning {
                        ProgressView()
                    } else {
                        Button("Quét") { Task { await scan() } }.fontWeight(.bold)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let status = web.status {
                    Text(status)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                }
            }
            .onAppear {
                web.onPageReady = { Task { await scan() } }
            }
            .sheet(isPresented: $showPopup) {
                popup
            }
    }

    private var popup: some View {
        NavigationStack {
            List {
                if !found.isEmpty {
                    Section {
                        ForEach(found) { voucherRow($0, hot: true) }
                    }
                } else {
                    Section {
                        Text(web.status ?? "Không có mã từ \(Self.nguong)% trở lên.")
                            .font(.subheadline)
                    }
                    // Không có mã đạt ngưỡng thì vẫn cho xem mấy mã % cao nhất đã đọc được — biết là app
                    // có đọc trang chứ không phải bấm không ăn.
                    if !all.isEmpty {
                        Section("Mã % cao nhất trong \(all.count) voucher đầu") {
                            ForEach(all.sorted { $0.pct > $1.pct }.prefix(8)) { voucherRow($0, hot: false) }
                        }
                    }
                }
            }
            .navigationTitle(found.isEmpty ? "Không có mã ≥\(Self.nguong)%" : "Có \(found.count) mã ≥\(Self.nguong)%")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showPopup = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func voucherRow(_ v: ShopeeVoucher, hot: Bool) -> some View {
        Button {
            showPopup = false
            web.reveal(v)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(v.pct)%")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                    .frame(width: 64, height: 44)
                    .background(hot ? Color.orange : Color.gray, in: RoundedRectangle(cornerRadius: 8))
                Text(v.text)
                    .font(.footnote)
                    .foregroundColor(.primary)
                    .lineLimit(4)
            }
        }
    }

    /// Lần quét nào cũng bật popup (kể cả không có mã / lỗi) — trước đây chỉ có mã ≥25% mới bật, còn lại
    /// chỉ hiện dòng chữ nhỏ dưới đáy nên bấm "Quét" tưởng như không có gì xảy ra.
    private func scan() async {
        let result = await web.scan()
        // nil mà không có lý do = đang có lượt quét khác chạy, để lượt đó bật popup.
        if result == nil && web.status == nil { return }
        all = result ?? []
        found = all.filter { $0.pct >= Self.nguong }.sorted { $0.pct > $1.pct }
        if result == nil {
            // web.status đã ghi lý do lỗi.
        } else if all.isEmpty {
            web.status = "Chưa thấy thẻ voucher nào trên trang (\(web.pageInfo)). Đợi trang tải xong / đăng nhập Shopee ngay trên trang rồi bấm \"Quét\" lại."
        } else if found.isEmpty {
            web.status = "Đã xem \(all.count) voucher đầu, không có mã từ \(Self.nguong)% trở lên."
        } else {
            web.status = "Có \(found.count) mã ≥\(Self.nguong)% trong \(all.count) voucher đầu."
        }
        showPopup = true
    }
}

struct ShopeeVoucher: Decodable, Identifiable {
    let id: Int
    let pct: Int
    let text: String
}

@MainActor
private final class ShopeeVoucherWebModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var scanning = false
    @Published var status: String?
    var onPageReady: (() -> Void)?
    /// Đường dẫn + đoạn đầu chữ của trang lúc quét — hiện khi không thấy voucher nào để biết trang đang
    /// ở đâu (chưa đăng nhập, Shopee đẩy sang trang khác…).
    private(set) var pageInfo = ""

    private struct ScanResult: Decodable {
        let items: [ShopeeVoucher]
        let info: String
    }

    /// Chỉ đọc tối đa ngần này thẻ đầu trang.
    private static let soTheToiDa = 60

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Ví voucher chỉ có trên web desktop — web mobile chuyển sang /me bắt "Tải ứng dụng Shopee".
        // Xin bản desktop như nút "Yêu cầu trang web cho máy tính" của Safari (UA Mac Safari thật).
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://shopee.vn/user/voucher-wallet?type=0")!))
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Thẻ voucher do JS của trang vẽ sau khi tải HTML xong — đợi thêm cho kịp hiện.
            // Chỉ tự quét lần tải đầu; bấm sang trang khác trong WebView thì thôi, muốn thì bấm "Quét".
            guard let ready = self.onPageReady else { return }
            self.onPageReady = nil
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            ready()
        }
    }

    /// Đọc chữ các thẻ voucher đang có trong trang. Thẻ = phần tử nhỏ nhất có "x%" kèm chữ đặc trưng
    /// của voucher (HSD/Lưu/Đơn tối thiểu…); bỏ "% đã dùng" (thanh tiến độ) khỏi phép tính.
    func scan() async -> [ShopeeVoucher]? {
        guard !scanning else { return nil }
        scanning = true
        status = nil
        defer { scanning = false }
        let script = """
        const usedRe = /\\d{1,3}\\s*%\\s*(đã dùng|đã sử dụng|đã lưu|used|claimed)|(đã dùng|đã sử dụng|đã lưu|used|claimed)\\s*:?\\s*\\d{1,3}\\s*%/gi;
        const keyRe = /(HSD|Hiệu lực|Hết hạn|Sắp hết hạn|Đơn tối thiểu|Dùng ngay|Dùng sau|Lưu|Valid|Min\\. Spend|Claim|\\bUse\\b)/i;
        // Thẻ sản phẩm gợi ý cuối trang cũng có "-2%" — loại bằng chữ "Đã bán"/"sold" và giá dạng 225.400₫.
        const productRe = /(đã bán|\\bsold\\b|\\d{1,3}(\\.\\d{3})+\\s*₫)/i;
        const norm = e => (e.textContent || '').replace(/\\s+/g, ' ').trim();
        const isCard = t => t.length > 0 && t.length < 260 && keyRe.test(t) && !productRe.test(t) && /\\d\\s*%/.test(t.replace(usedRe, ''));
        const out = []; const seen = new Set();
        for (const e of document.querySelectorAll('div,li,a,section,article')) {
          const t = norm(e);
          if (!isCard(t)) continue;
          if ([...e.children].some(c => isCard(norm(c)))) continue;
          if (seen.has(t)) continue;
          seen.add(t);
          const nums = [...t.replace(usedRe, '').matchAll(/(\\d{1,3})\\s*%/g)].map(m => +m[1]).filter(n => n > 0 && n <= 100);
          if (!nums.length) continue;
          e.setAttribute('data-dc-voucher', out.length);
          out.push({ id: out.length, pct: Math.max(...nums), text: t });
          if (out.length >= max) break;
        }
        const body = (document.body && document.body.innerText || '').replace(/\\s+/g, ' ').trim();
        return JSON.stringify({ items: out, info: location.pathname + ' · ' + body.length + ' ký tự · ' + body.slice(0, 100) });
        """
        do {
            let value = try await webView.callAsyncJavaScript(script, arguments: ["max": Self.soTheToiDa], contentWorld: .page)
            guard let text = value as? String, let data = text.data(using: .utf8) else {
                pageInfo = "trang không trả kết quả"
                return []
            }
            let result = try JSONDecoder().decode(ScanResult.self, from: data)
            pageInfo = result.info
            return result.items
        } catch {
            status = "Không đọc được trang Shopee: \(error.localizedDescription)"
            return nil
        }
    }

    /// Cuộn tới thẻ voucher (để người dùng tự bấm Lưu) và nháy viền cam cho dễ thấy.
    func reveal(_ v: ShopeeVoucher) {
        let js = """
        (() => { const e = document.querySelector('[data-dc-voucher="\(v.id)"]'); if (!e) return;
          e.scrollIntoView({ block: 'center', behavior: 'smooth' });
          const old = e.style.outline; e.style.outline = '3px solid #ff6a00';
          setTimeout(() => { e.style.outline = old; }, 2500); })();
        """
        webView.evaluateJavaScript(js)
    }
}

private struct ShopeeVoucherWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
