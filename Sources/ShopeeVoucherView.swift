import SwiftUI
import WebKit

/// Menu → "Voucher Shopee ≥20%". Mở Ví voucher của tài khoản Shopee trong WebView (dùng chung cookie đăng
/// nhập với "Nhập từ Shopee"), đợi trang tự tải xong rồi đọc chữ trên các thẻ voucher ĐANG HIỆN SẴN —
/// không gọi API, không cuộn để tải thêm, không bấm gì. Ví có hơn 2000 voucher nhưng Shopee xếp voucher
/// ngon lên đầu nên lần tải đầu (~50 thẻ) là đủ. Có mã từ 20% trở lên thì bật popup, vẽ thẻ giống Shopee.
/// Bấm thẻ → ẩn voucher đó / ẩn cả nhóm (Shopee Mart, Bách hoá chính hãng ẩn sẵn) / xem trên trang.
/// Đọc theo chữ ("25%", "HSD", "Lưu"…) chứ không theo class CSS — Shopee đổi giao diện vẫn chạy được,
/// chỉ hỏng nếu thẻ voucher thành ảnh.
struct ShopeeVoucherView: View {
    @StateObject private var web = ShopeeVoucherWebModel()
    @State private var all: [ShopeeVoucher] = []
    @State private var showPopup = false
    @State private var chon: ShopeeVoucher?
    /// Nhóm đang ẩn (tên nhóm đã bỏ dấu, viết thường), mỗi dòng 1 nhóm. Chỉ là tuỳ chọn hiển thị trên
    /// máy này nên để UserDefaults.
    @AppStorage("shopeeVoucher.anNhom") private var anNhomRaw = "shopee mart\nbach hoa chinh hang"
    /// Voucher đang ẩn lẻ (ShopeeVoucher.key), mỗi dòng 1 mã.
    @AppStorage("shopeeVoucher.anMa") private var anMaRaw = ""

    private static let nguong = 20

    private var anNhom: [String] { anNhomRaw.split(separator: "\n").map(String.init) }
    private var anMa: Set<String> { Set(anMaRaw.split(separator: "\n").map(String.init)) }

    /// Nhóm ẩn "bach hoa chinh hang" khớp cả nhãn "Mall BÁCH HÓA CHÍNH HÃNG", nhưng ẩn "shopee" thì
    /// không kéo theo "shopee video".
    private func biAn(_ v: ShopeeVoucher) -> Bool {
        if anMa.contains(v.key) { return true }
        let g = v.nhomKey
        return anNhom.contains { g == $0 || g.hasSuffix(" " + $0) }
    }

    private var hien: [ShopeeVoucher] { all.filter { !biAn($0) } }
    private var found: [ShopeeVoucher] { hien.filter { $0.pct >= Self.nguong }.sorted { $0.pct > $1.pct } }
    private var soAn: Int { all.count - hien.count }

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
            ScrollView {
                LazyVStack(spacing: 10) {
                    if found.isEmpty {
                        Text(all.isEmpty ? (web.status ?? "Chưa đọc được voucher nào.") : "Không có mã từ \(Self.nguong)% trở lên trong \(hien.count) voucher đầu.")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 4))
                        // Không có mã đạt ngưỡng thì vẫn cho xem mấy mã % cao nhất đã đọc được — biết là app
                        // có đọc trang chứ không phải bấm không ăn.
                        if !hien.isEmpty {
                            Text("Mã % cao nhất")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                            ForEach(hien.sorted { $0.pct > $1.pct }.prefix(8)) { voucherCard($0).opacity(0.6) }
                        }
                    } else {
                        ForEach(found) { voucherCard($0) }
                    }
                    if soAn > 0 || !anNhom.isEmpty || !anMa.isEmpty {
                        boLoc
                    }
                }
                .padding(12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(found.isEmpty ? "Không có mã ≥\(Self.nguong)%" : "Có \(found.count) mã ≥\(Self.nguong)%")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { showPopup = false }
                }
            }
            .confirmationDialog(chon?.title ?? "Voucher", isPresented: Binding(
                get: { chon != nil },
                set: { if !$0 { chon = nil } }
            ), titleVisibility: .visible, presenting: chon) { v in
                Button("Ẩn voucher này", role: .destructive) { anMaRaw = (anMa.union([v.key])).sorted().joined(separator: "\n") }
                if !v.nhomKey.isEmpty {
                    Button("Ẩn cả nhóm \"\(v.group ?? "")\"", role: .destructive) {
                        anNhomRaw = (anNhom + [v.nhomKey]).joined(separator: "\n")
                    }
                }
                Button("Xem trên trang Shopee") {
                    showPopup = false
                    web.reveal(v)
                }
                Button("Huỷ", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Khối cuối popup: đang ẩn gì, bấm để hiện lại.
    private var boLoc: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Đang ẩn \(soAn) voucher trong lần quét này")
                .font(.footnote.weight(.semibold))
            ForEach(anNhom, id: \.self) { g in
                HStack {
                    Text("Nhóm: \(g)").font(.footnote)
                    Spacer()
                    Button("Hiện lại") {
                        anNhomRaw = anNhom.filter { $0 != g }.joined(separator: "\n")
                    }
                    .font(.footnote)
                }
            }
            if !anMa.isEmpty {
                HStack {
                    Text("\(anMa.count) voucher ẩn lẻ").font(.footnote)
                    Spacer()
                    Button("Hiện lại hết") { anMaRaw = "" }.font(.footnote)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 4))
        .padding(.top, 8)
    }

    /// Thẻ voucher vẽ giống ví Shopee: cột trái màu nhóm + logo + tên nhóm, bên phải tiêu đề / đơn tối
    /// thiểu / nhãn / thanh đã dùng / hạn dùng, góc phải số lượng "x15".
    private func voucherCard(_ v: ShopeeVoucher) -> some View {
        Button {
            chon = v
        } label: {
            HStack(spacing: 0) {
                VStack(spacing: 6) {
                    if let logo = v.logo, let url = URL(string: logo) {
                        AsyncImage(url: url) { img in
                            img.resizable().scaledToFit()
                        } placeholder: {
                            Image(systemName: "bag").font(.system(size: 26)).foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "bag").font(.system(size: 30)).foregroundColor(.white)
                    }
                    if let group = v.group, !group.isEmpty {
                        Text(group)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                }
                .padding(6)
                .frame(width: 92)
                .frame(maxHeight: .infinity)
                .background(v.mau)

                VStack(alignment: .leading, spacing: 4) {
                    if v.limited == true {
                        Text("⚡ Số lượng có hạn")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.shopeeCam, in: RoundedRectangle(cornerRadius: 2))
                    }
                    Text(v.title ?? "\(v.pct)%")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    if let toiThieu = v.min {
                        Text(toiThieu).font(.system(size: 13)).foregroundColor(.primary)
                    }
                    ForEach(v.tags ?? [], id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 10))
                            .foregroundColor(.shopeeCam)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.shopeeCam, lineWidth: 0.5))
                    }
                    if let used = v.used {
                        ProgressView(value: Double(Swift.min(used, 100)), total: 100)
                            .tint(.shopeeCam)
                    }
                    HStack(spacing: 4) {
                        if v.runningOut == true {
                            Text("Đang hết nhanh").foregroundColor(.shopeeCam)
                        } else if let used = v.used {
                            Text("Đã dùng \(used)%").foregroundColor(.secondary)
                        }
                        if let exp = v.expiry {
                            Text(exp).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                    .font(.system(size: 11))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(.systemBackground))
            .overlay(alignment: .topTrailing) {
                if let qty = v.qty {
                    Text(qty)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.shopeeCam)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.shopeeCam.opacity(0.1), in: Capsule())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    /// Lần quét nào cũng bật popup (kể cả không có mã / lỗi) — từng chỉ bật khi có mã đạt ngưỡng, còn lại
    /// chỉ hiện dòng chữ nhỏ dưới đáy nên bấm "Quét" tưởng như không có gì xảy ra.
    private func scan() async {
        let result = await web.scan()
        // nil mà không có lý do = đang có lượt quét khác chạy, để lượt đó bật popup.
        if result == nil && web.status == nil { return }
        all = result ?? []
        if result == nil {
            // web.status đã ghi lý do lỗi.
        } else if all.isEmpty {
            web.status = "Chưa thấy thẻ voucher nào trên trang (\(web.pageInfo)). Đợi trang tải xong / đăng nhập Shopee ngay trên trang rồi bấm \"Quét\" lại."
        } else if found.isEmpty {
            web.status = "Đã xem \(hien.count) voucher đầu, không có mã từ \(Self.nguong)% trở lên."
        } else {
            web.status = "Có \(found.count) mã ≥\(Self.nguong)% trong \(hien.count) voucher đầu."
        }
        showPopup = true
    }
}

struct ShopeeVoucher: Decodable, Identifiable {
    /// Thứ tự thẻ trên trang (0-based) — dùng để cuộn tới.
    let id: Int
    let pct: Int
    let text: String
    // Tách từ chữ trên thẻ để vẽ giống Shopee — thiếu cái nào thì bỏ dòng đó.
    let group: String?
    let title: String?
    let min: String?
    let expiry: String?
    let tags: [String]?
    let used: Int?
    let limited: Bool?
    let runningOut: Bool?
    let qty: String?
    let logo: String?
    /// Màu cột trái của thẻ trên trang, "r,g,b".
    let color: String?

    /// Nhận diện 1 voucher qua các lần quét (id đổi theo vị trí nên không dùng được).
    var key: String { [group ?? "", title ?? "", min ?? ""].joined(separator: "|") }
    var nhomKey: String { Self.fold(group ?? "") }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var mau: Color {
        let c = (color ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard c.count == 3 else { return .shopeeCam }
        return Color(red: c[0] / 255, green: c[1] / 255, blue: c[2] / 255)
    }
}

extension Color {
    static let shopeeCam = Color(red: 238 / 255, green: 77 / 255, blue: 45 / 255)
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
    /// của voucher (HSD/Lưu/Đơn tối thiểu…); bỏ "% đã dùng" (thanh tiến độ) khỏi phép tính. Lọc ẩn nhóm
    /// làm bên Swift để bật/tắt không phải quét lại.
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
        const pctCount = t => (t.replace(usedRe, '').match(/\\d{1,3}\\s*%/g) || []).length;
        // textContent gồm cả chữ của phần tử đang ẨN — chỉ lấy thẻ đang thật sự hiển thị (có kích thước).
        const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.height > 0 && getComputedStyle(e).visibility !== 'hidden'; };
        // Các mẩu chữ hiển thị của thẻ theo thứ tự (textContent dính liền "100kđĐơn Tối Thiểu").
        const texts = e => { const parts = []; const w = document.createTreeWalker(e, NodeFilter.SHOW_TEXT);
          for (let n = w.nextNode(); n; n = w.nextNode()) { const x = n.textContent.replace(/\\s+/g, ' ').trim(); if (x && n.parentElement && visible(n.parentElement)) parts.push(x); }
          return parts; };
        // Tách mẩu chữ thành từng phần để app vẽ lại giống thẻ Shopee.
        const junk = /^(•|·|T&C|Điều kiện|Dùng ngay|Dùng sau|Use|Use later|Lưu|Claim|Mới!?|New!?)$/i;
        const limRe = /^(⚡\\s*)?(Số lượng có hạn|Limited)$/i;
        const runRe = /^(Đang hết nhanh|Running out)$/i;
        const minRe = /(tối thiểu|Min\\. Spend)/i;
        const expRe = /(HSD|hết hạn|Hiệu lực|Valid|Expir|Use from|Use in|Còn \\d)/i;
        const usedPartRe = /(\\d{1,3})\\s*%\\s*(đã dùng|used)|(đã dùng|used)\\s*(\\d{1,3})\\s*%/i;
        const parse = (card, parts) => {
          const r = { tags: [] }; const pre = []; let titleIdx = -1;
          parts.forEach((x, i) => {
            if (junk.test(x)) return;
            if (limRe.test(x)) { r.limited = true; return; }
            if (runRe.test(x)) { r.runningOut = true; return; }
            const u = x.match(usedPartRe);
            if (u) { r.used = +(u[1] || u[4]); const rest = x.replace(usedPartRe, '').replace(/^[,\\s]+|[,\\s]+$/g, ''); if (rest && expRe.test(rest)) r.expiry = rest; return; }
            if (/^x\\s?\\d+$/i.test(x)) { r.qty = x.replace(/\\s/g, ''); return; }
            // Số lượng "x15" có khi tách 2 mẩu: "x" + "15".
            if (/^x$/i.test(x)) return;
            if (/^\\d{1,3}$/.test(x)) { r.qty = 'x' + x; return; }
            if (titleIdx < 0 && /\\d\\s*%/.test(x)) { titleIdx = i; r.title = x; return; }
            if (titleIdx < 0) { pre.push(x); return; }
            if (!r.min && minRe.test(x)) { r.min = x; return; }
            if (!r.expiry && expRe.test(x)) { r.expiry = x; return; }
            if (titleIdx === i - 1 && /(tối đa|Capped)/i.test(x)) { r.title += ' ' + x; return; }
            if (x.length <= 40) r.tags.push(x);
          });
          r.group = pre.join(' ');
          const img = [...card.querySelectorAll('img')].find(i => i.getBoundingClientRect().width >= 30);
          if (img) r.logo = img.currentSrc || img.src;
          for (const x of [card, ...card.querySelectorAll('*')].slice(0, 30)) {
            const cs = getComputedStyle(x);
            const m = (cs.backgroundImage + ' ' + cs.backgroundColor).match(/rgb\\((\\d+),\\s*(\\d+),\\s*(\\d+)\\)/);
            if (m && !(m[1] === '255' && m[2] === '255' && m[3] === '255')) { r.color = m[1] + ',' + m[2] + ',' + m[3]; break; }
          }
          return r;
        };
        document.querySelectorAll('[data-dc-voucher]').forEach(x => x.removeAttribute('data-dc-voucher'));
        const out = []; const seen = new Set();
        for (const e of document.querySelectorAll('div,li,a,section,article')) {
          const t = norm(e);
          if (!isCard(t)) continue;
          if (!visible(e)) continue;
          if ([...e.children].some(c => isCard(norm(c)))) continue;
          // Nhãn nhóm (SHOPEE VIDEO, Shopee Mart…) nằm ở nửa trái thẻ, ngoài phần chữ % — leo lên khung
          // thẻ (cha gần nhất vẫn chỉ chứa 1 voucher).
          let card = e;
          for (let i = 0; i < 5; i++) {
            const p = card.parentElement; if (!p) break;
            const pt = norm(p); if (pt.length > 400 || pctCount(pt) > pctCount(t)) break;
            card = p;
          }
          const ct = norm(card);
          if (seen.has(ct)) continue;
          seen.add(ct);
          const nums = [...t.replace(usedRe, '').matchAll(/(\\d{1,3})\\s*%/g)].map(m => +m[1]).filter(n => n > 0 && n <= 100);
          if (!nums.length) continue;
          const parts = texts(card);
          card.setAttribute('data-dc-voucher', out.length);
          out.push(Object.assign({ id: out.length, pct: Math.max(...nums), text: parts.join(' · ') || ct }, parse(card, parts)));
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

    /// Đợi popup đóng hẳn rồi mới cuộn (cuộn lúc sheet còn đang trượt xuống thì WebView chưa nhận).
    /// Trang Shopee vẽ lại danh sách thì mất dấu thẻ — báo để bấm "Quét" lại.
    func reveal(_ v: ShopeeVoucher) {
        let js = """
        const e = document.querySelector('[data-dc-voucher="' + id + '"]');
        if (!e) return false;
        e.scrollIntoView({ block: 'center' });
        const old = e.style.outline; e.style.outline = '4px solid #ff6a00';
        setTimeout(() => { e.style.outline = old; }, 4000);
        return true;
        """
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let ok = (try? await webView.callAsyncJavaScript(js, arguments: ["id": v.id], contentWorld: .page)) as? Bool
            if ok != true {
                status = "Không tìm thấy thẻ \(v.pct)% trên trang nữa (trang đã vẽ lại) — bấm \"Quét\" lại."
            }
        }
    }
}

private struct ShopeeVoucherWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
