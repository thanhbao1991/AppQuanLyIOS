import SwiftUI
import WebKit

/// Nút "Nhập từ Shopee" cạnh nút ảnh/camera ở tab Chi tiêu. Mở trang Shopee trong WebView (người dùng
/// TỰ đăng nhập — app không bao giờ đụng mật khẩu; cookie lưu ở WKWebsiteDataStore mặc định nên chỉ
/// đăng nhập lần đầu), bấm "Lấy đơn" thì app chạy JS ngay trong trang gọi API danh sách đơn "Giao thành
/// công" của chính Shopee — CHỈ ĐỌC, không bấm/đổi gì trên tài khoản. Chọn đơn của quán → khớp nguyên
/// liệu (POST /api/ChiTieuHangNgay/match-lines, cùng thuật toán + alias đã học như ảnh hoá đơn) → form
/// duyệt dùng chung ReceiptReviewSheet. Mỗi dòng lưu mã đơn vào cột NguonShopeeOrderId để lần sau biết
/// đơn nào đã nhập (kể cả nhập từ máy khác), hiện nhãn "Shopee" ở danh sách chi tiêu.
/// Phụ thuộc API nội bộ của web Shopee (/api/v4/order/get_order_list) — Shopee đổi là hỏng, lúc đó báo
/// lỗi rõ ràng chứ không lưu sai.
struct ShopeeImportButton: View {
    let onSaved: () -> Void
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "bag").font(.system(size: 22))
        }
        .foregroundColor(.brandPrimary)
        .fullScreenCover(isPresented: $showSheet) {
            ShopeeImportSheet(onSaved: onSaved)
        }
    }
}

struct ShopeeOrder: Decodable, Identifiable {
    let id: String
    let time: Double
    let shop: String
    let total: Double
    let items: [Item]

    struct Item: Decodable {
        let name: String
        let model: String
        let amount: Double
        let price: Double
    }

    var date: Date { Date(timeIntervalSince1970: time) }
    var paidItems: [Item] { items.filter { $0.price > 0 } }
}

private struct ShopeeFetchResult: Decodable {
    let orders: [ShopeeOrder]?
    let error: Int?
    let message: String?
}

/// Giữ 1 WKWebView sống suốt sheet (SwiftUI dựng lại view thì trang không bị tải lại từ đầu).
@MainActor
private final class ShopeeWebModel: ObservableObject {
    let webView: WKWebView

    init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // UA giống Safari iPhone — tránh Shopee coi là WebView lạ, ép mở app Shopee.
        config.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://shopee.vn/user/purchase/?type=3")!))
    }

    /// Đọc đơn "Giao thành công" (list_type=3) từ mới về cũ, 20 đơn/lần gọi Shopee. Dừng ngay khi gặp
    /// 1 đơn trong `stopIds` (đơn đã nhập gần đây — mốc chính xác, không tính theo ngày), hoặc khi gặp
    /// 3 đơn giao trước `since` (chặn dưới: 30 ngày khi chưa nhập đơn nào). Gọi Shopee càng ít càng tốt
    /// để không giống bot.
    func fetchOrders(since: TimeInterval, stopIds: [String]) async throws -> ShopeeFetchResult {
        let script = """
        const stop = new Set(stopIds);
        const out = []; let older = 0; let done = false;
        for (let offset = 0; !done && offset < 400 && older < 3; offset += 20) {
          const r = await fetch('/api/v4/order/get_order_list?list_type=3&offset=' + offset + '&limit=20', { credentials: 'include' });
          const j = await r.json();
          if (j.error) return JSON.stringify({ error: j.error, message: j.error_msg || '' });
          const list = (j.data && j.data.details_list) || [];
          if (!list.length) break;
          for (const o of list) {
            if (stop.has(String(o.info_card.order_id))) { done = true; break; }
            const t = (o.shipping && o.shipping.tracking_info && o.shipping.tracking_info.ctime) || 0;
            if (t < since) { older++; continue; }
            const cards = (o.info_card && o.info_card.order_list_cards) || [];
            const items = [];
            for (const c of cards) for (const g of ((c.product_info && c.product_info.item_groups) || [])) for (const it of (g.items || []))
              items.push({ name: it.name || '', model: it.model_name || '', amount: it.amount || 1, price: (it.order_price || 0) / 100000 });
            out.push({ id: String(o.info_card.order_id), time: t, shop: (cards[0] && cards[0].shop_info && cards[0].shop_info.shop_name || '').trim(),
                       total: (o.info_card.final_total || 0) / 100000, items });
          }
        }
        return JSON.stringify({ orders: out });
        """
        let value = try await webView.goiJS(script, arguments: ["since": since, "stopIds": stopIds])
        guard let text = value as? String, let data = text.data(using: .utf8) else {
            throw NSError(domain: "Shopee", code: 0, userInfo: [NSLocalizedDescriptionKey: "Trang Shopee không trả dữ liệu."])
        }
        return try JSONDecoder().decode(ShopeeFetchResult.self, from: data)
    }
}

private struct ShopeeWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

private struct ShopeeImportSheet: View {
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var web = ShopeeWebModel()
    @State private var orders: [ShopeeOrder]?
    @State private var imported: Set<String> = []
    @State private var selected: Set<String> = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var reviewLines: ReviewPayload?
    /// true = đọc tới đơn đã nhập gần nhất thì dừng; false = đọc đủ `soNgay` ngày.
    @State private var dungODonDaNhap = false

    private static let soNgay = 30

    struct ReviewPayload: Identifiable {
        let id = UUID()
        let lines: [ReceiptDraftLine]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ShopeeWebView(webView: web.webView)
                if let orders {
                    orderList(orders)
                        .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle(orders == nil ? "Shopee" : "Chọn đơn của quán")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if orders == nil {
                        Button("Đóng") { dismiss() }
                    } else {
                        Button("Trang Shopee") { orders = nil }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if loading {
                        ProgressView().tint(.white)
                    } else if orders == nil {
                        Button("Lấy đơn") { Task { await fetch() } }.fontWeight(.bold)
                    } else {
                        Button("Tiếp (\(selected.count))") { Task { await next() } }
                            .fontWeight(.bold)
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .popupHost { host in
                host.alert("Shopee", isPresented: Binding(
                    get: { errorText != nil },
                    set: { if !$0 { errorText = nil } }
                )) {
                    Button("OK") {}
                } message: {
                    Text(errorText ?? "")
                }
            }
            .sheet(item: $reviewLines) { payload in
                ReceiptReviewSheet(title: "Duyệt đơn Shopee", lines: payload.lines) {
                    onSaved()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func orderList(_ orders: [ShopeeOrder]) -> some View {
        List {
            Section {
                if orders.isEmpty {
                    Text("Không có đơn giao thành công nào mới.")
                        .foregroundColor(.textMuted)
                }
                ForEach(orders) { order in
                    orderRow(order)
                }
            } footer: {
                Text("\(dungODonDaNhap ? "Đơn giao thành công mới hơn đơn Shopee nhập gần nhất" : "Đơn giao thành công \(Self.soNgay) ngày gần nhất"). Chỉ tick đơn mua cho quán — đơn cá nhân bỏ qua. Số tiền là tiền thực trả (đã trừ voucher).")
            }
            if dungODonDaNhap {
                Section {
                    Button("Xem lại \(Self.soNgay) ngày gần nhất") { Task { await fetch(full: true) } }
                        .disabled(loading)
                }
            }
        }
    }

    @ViewBuilder
    private func orderRow(_ order: ShopeeOrder) -> some View {
        let daNhap = imported.contains(order.id)
        let isOn = selected.contains(order.id)
        Button {
            if isOn { selected.remove(order.id) } else { selected.insert(order.id) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: daNhap ? "checkmark.seal" : (isOn ? "checkmark.circle.fill" : "circle"))
                    .foregroundColor(daNhap ? .textMuted : (isOn ? .brandPrimary : .textMuted))
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(Self.dayFormatter.string(from: order.date)).font(.caption.bold())
                        Text(order.shop).font(.caption).foregroundColor(.textMuted).lineLimit(1)
                        Spacer()
                        Text(HoaDonFormatting.money(order.total)).font(.subheadline.bold())
                    }
                    ForEach(Array(order.paidItems.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.footnote).lineLimit(1)
                            // Phân loại tách dòng riêng — tên sản phẩm Shopee dài, ghép chung thì phân
                            // loại (món thật sự mua) bị cắt mất.
                            Text("\(item.model.isEmpty ? "" : "\(item.model) ")×\(item.amount.formatted())")
                                .font(.footnote.bold())
                                .foregroundColor(.brandPrimary)
                        }
                    }
                    if daNhap {
                        Text("Đã nhập chi tiêu").font(.caption).foregroundColor(.successColor)
                    }
                }
            }
            .foregroundColor(.primary)
            .opacity(daNhap ? 0.5 : 1)
        }
        .disabled(daNhap)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM"
        return f
    }()

    /// Đã có đơn Shopee trong chi tiêu: chỉ đọc các đơn mới hơn đơn nhập gần nhất (gặp là dừng).
    /// Chưa có đơn nào (hoặc `full`): đọc tối đa 30 ngày. Khi có mốc thì chặn dưới nới ra 90 ngày phòng
    /// đơn mốc bị Shopee ẩn khỏi danh sách, khỏi đọc vô hạn.
    private func fetch(full: Bool = false) async {
        loading = true
        defer { loading = false }
        let stopIds = full ? [] : await APIClient.shared.shopeeDonGanDay()
        let soNgay = stopIds.isEmpty ? Self.soNgay : 90
        let since = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -soNgay, to: Date()) ?? Date())
        do {
            let result = try await web.fetchOrders(since: since.timeIntervalSince1970, stopIds: stopIds)
            if let list = result.orders {
                imported = await APIClient.shared.shopeeDaNhap(list.map(\.id))
                selected = []
                dungODonDaNhap = !stopIds.isEmpty
                orders = list.sorted { $0.time > $1.time }
            } else {
                errorText = "Chưa đăng nhập Shopee (hoặc Shopee từ chối, mã \(result.error ?? 0)). Đăng nhập ngay trên trang này rồi bấm \"Lấy đơn\" lại."
            }
        } catch {
            errorText = "Không đọc được đơn từ trang Shopee: \(error.localizedDescription). Đợi trang tải xong (và đã đăng nhập) rồi thử lại."
        }
    }

    /// Chia tiền thực trả của đơn (đã trừ voucher/phí ship) cho từng món theo tỉ lệ giá gốc, rồi gửi
    /// tên món lên Backend khớp nguyên liệu.
    private func next() async {
        guard let orders else { return }
        let chosen = orders.filter { selected.contains($0.id) }.sorted { $0.time < $1.time }

        var drafts: [ReceiptDraftLine] = []
        for order in chosen {
            let items = order.paidItems
            let weightSum = items.reduce(0) { $0 + $1.price * $1.amount }
            let nhom = "\(Self.dayFormatter.string(from: order.date)) · \(order.shop) · \(HoaDonFormatting.money(order.total))"
            for item in items {
                let share = weightSum > 0 ? order.total * item.price * item.amount / weightSum : 0
                let soLuong = max(item.amount, 1)
                var raw = item.model.isEmpty ? item.name : "\(item.name) - \(item.model)"
                // Alias lưu tối đa 200 ký tự (sau normalize) — cắt bớt tên Shopee dài.
                if raw.count > 150 { raw = String(raw.prefix(150)) }
                drafts.append(ReceiptDraftLine(
                    rawText: raw, nguyenLieuId: nil, nguyenLieuTen: nil, fromLearnedAlias: false,
                    soLuong: soLuong, donGia: (share / soLuong).rounded(),
                    ngay: order.date, shopeeOrderId: order.id, nhom: nhom,
                    phanLoai: item.model.isEmpty ? nil : item.model
                ))
            }
        }
        guard !drafts.isEmpty else { return }

        loading = true
        defer { loading = false }
        let (result, message) = await APIClient.shared.matchReceiptLines(
            drafts.map { ReceiptMatchLineRequest(ten: $0.rawText, phanLoai: $0.phanLoai, soLuong: $0.soLuong, donGia: $0.donGia) }
        )
        guard let result, result.lines.count == drafts.count else {
            errorText = message ?? "Không khớp được nguyên liệu."
            return
        }
        for i in drafts.indices {
            let m = result.lines[i]
            drafts[i].nguyenLieuId = m.suggestedNguyenLieuId
            drafts[i].nguyenLieuTen = m.suggestedNguyenLieuTen
            drafts[i].fromLearnedAlias = m.suggestedFromLearnedAlias
        }
        reviewLines = ReviewPayload(lines: drafts)
    }
}
