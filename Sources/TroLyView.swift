import Charts
import SwiftUI
import UIKit

/// 1 câu hỏi bấm sẵn của trợ lý — server trả danh sách (GET /api/TroLy/cau-hoi).
struct TroLyCauHoi: Codable, Identifiable, Equatable {
    let ma: String
    let noiDung: String
    /// Tên card nhóm ("Hàng Hoá" | "Bán Hàng" | "App Đặt Hàng") — server cũ không gửi thì gom 1 card không tiêu đề.
    var nhom: String?
    var id: String { ma }
}

/// Câu trả lời có cấu trúc (GET /api/TroLy/tong-quan, /chi-tiet/{ma}) — trường nào nil thì không hiện.
struct TroLyTraLoi: Codable, Equatable {
    struct Dong: Codable, Equatable, Identifiable {
        let ten: String
        let giaTri: String
        let phu: String?
        /// "het" | "thap" | "sapHet" | nil
        let mucDo: String?
        let hang: Int?
        /// Chỉ dòng TỒN KHO mới có 3 trường này — bấm vào dòng để sửa nhanh tồn kho (SuaTonNhanhSheet).
        let nguyenLieuBanHangId: String?
        let ton: Double?
        let donVi: String?
        /// Chi tiết của dòng (vd từng máy của "Bản cũ") — chỉ hiện khi bấm vào dòng trong báo cáo chia cột.
        var con: [Dong]? = nil
        var id: String { ten }
    }

    struct Diem: Codable, Equatable, Identifiable {
        let nhan: String
        let giaTri: Double
        let nhom: String?
        var id: String { "\(nhom ?? "")|\(nhan)" }
    }

    struct BieuDo: Codable, Equatable {
        /// "duong" (cộng dồn theo giờ, nhan = giờ) | "cot" (cột ngang, nhan = tên)
        let loai: String
        let diem: [Diem]
        let donVi: String?
    }

    let tieuDe: String?
    let moTa: String?
    let soSanh: String?
    let soSanhTang: Bool?
    let thongDiep: String?
    /// "ok" | "canhBao" | nil
    let trangThai: String?
    let dong: [Dong]
    let bieuDo: BieuDo?
    /// Báo cáo chia cột cạnh nhau (vd iPhone | Android): mỗi cột tieuDe = tên cột, moTa = số chính. Có thì vẽ
    /// cột thay cho dong/bieuDo (server vẫn gửi dong/bieuDo cho bản app cũ).
    let cot: [TroLyTraLoi]?
}

/// Việc "Cần xử lý" (GET /api/TroLy/canh-bao) — lỗi API/crash, VPS (RAM/disk/SQL), lệch ví, backup. Thay Discord
/// từ 18/10/2026. Cùng 1 lỗi lặp lại thì server gộp (soLan), tick xong mà tái diễn thì thành việc mới.
struct CanhBaoHeThong: Codable, Identifiable, Equatable {
    let id: String
    /// "Loi" | "HeThong" | "Vi" | "Backup"
    let loai: String
    let tieuDe: String
    let noiDung: String?
    let chiTiet: String?
    let soLan: Int
    let taoLuc: String
    let lanCuoiLuc: String
    var daXuLy: Bool
    let xuLyLuc: String?
}

/// Số việc cần xử lý trên nút ✨ (0 với tài khoản không phải Admin).
final class CanhBaoBadge: ObservableObject {
    static let shared = CanhBaoBadge()
    @Published var soViec = 0

    func refresh() async {
        guard let ds = await APIClient.shared.getCanhBao() else { return }
        await MainActor.run { soViec = ds.count }
    }
}

/// Trợ lý ảo (Menu > Trợ lý ảo) — KHÔNG dùng AI. Đầu màn là thẻ tình trạng tồn kho, bên dưới các câu hỏi bấm
/// sẵn THU GỌN — chạm câu nào mới mở + tải câu trả lời câu đó (server tính thẳng từ DB, kèm biểu đồ); user
/// không muốn phải đọc hết mọi câu. Kéo xuống để làm mới. Thứ tự CỐ ĐỊNH theo server (xếp theo nhóm liên quan) —
/// 01/11/2026 user khoá, bỏ kéo thả đổi thứ tự tự do (trước đó lưu AppStorage "troLy.thuTu.v4").
/// Các màn chỉ để xem trong Menu (Giờ vắng khách, Bão hoà, Bản đồ, Phiên bản app khách, Tính lương, Số dư AI) đã dời
/// vào đây (28/10/2026) — xem `mucTrenMay`; Menu chỉ còn việc sửa. Từ 29/10/2026 Duyệt công thức + card Chi Phí nằm
/// trên cùng (trên cả Cần xử lý).
/// Ảnh chụp lần tải gần nhất của TroLyView — BoNhoTam giữ để mở lại màn hiện ngay (09/11/2026).
private struct TroLySnap {
    let cauHoiGoc: [TroLyCauHoi]
    let canhBao: [CanhBaoHeThong]?
    let capNhatLuc: Date?
}

struct TroLyView: View {
    // 09/11/2026: mở lại màn hiện ngay số liệu lần trước (BoNhoTam), .task vẫn tải lại rồi thay vào.
    @State private var cauHoi: [TroLyCauHoi] = (BoNhoTam.lay("troLy") as TroLySnap?)?.cauHoiGoc ?? []
    @State private var cauHoiGoc: [TroLyCauHoi] = (BoNhoTam.lay("troLy") as TroLySnap?)?.cauHoiGoc ?? []
    @State private var traLoi: [String: TroLyTraLoi] = [:]
    /// "Cần nhập hàng gì?" luôn mở sẵn khi vào màn (user 12/11/2026 — thay thẻ tình trạng tồn kho đã bỏ).
    @State private var moRa: Set<String> = ["can-nhap"]
    @State private var dangHoi: Set<String> = []
    @State private var dangTai = true
    @State private var daTaiLanMo = false
    @State private var capNhatLuc: Date? = (BoNhoTam.lay("troLy") as TroLySnap?)?.capNhatLuc
    /// nil = không phải Admin / lỗi → ẩn mục Cần xử lý.
    @State private var canhBao: [CanhBaoHeThong]? = (BoNhoTam.lay("troLy") as TroLySnap?)?.canhBao
    @State private var daXuLy: [CanhBaoHeThong] = []
    @State private var xemDaXuLy = false
    @State private var moCanhBao: Set<String> = []
    /// Dòng tồn kho đang được sửa nhanh (bấm vào dòng trong thẻ tình trạng hoặc câu trả lời).
    @State private var suaTon: TroLyTraLoi.Dong?
    @State private var soDuAi: AiBalanceDto?
    @State private var daTaiSoDuAi = false

    var body: some View {
        List {
            // Chi Phí lên đầu, trên cả Cần xử lý (user 29/10/2026). Duyệt công thức L/XL đã chuyển ra cổng
            // vào tab (MainTabView.chonTab, user 01/11/2026).
            if nhomCauHoi.contains(Self.nhomChiPhi) { cardNhom(Self.nhomChiPhi) }

            if let canhBao {
                Section {
                    if canhBao.isEmpty {
                        Label("Không có việc cần xử lý", systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundColor(.green)
                    }
                    ForEach(canhBao) { cb in canhBaoRow(cb) }
                } header: {
                    Text(canhBao.isEmpty ? "Cần xử lý" : "Cần xử lý (\(canhBao.count))")
                } footer: {
                    Button(xemDaXuLy ? "Ẩn việc đã xử lý" : "Xem việc đã xử lý") {
                        khongHieuUng { xemDaXuLy.toggle() }
                        if xemDaXuLy { Task { await taiDaXuLy() } }
                    }
                    .font(.footnote)
                }

                if xemDaXuLy {
                    Section("Đã xử lý") {
                        if daXuLy.isEmpty {
                            Text("Chưa có.").font(.subheadline).foregroundColor(.textMuted)
                        }
                        ForEach(daXuLy) { cb in canhBaoRow(cb) }
                    }
                }
            }

            // 12/11/2026 (user): bỏ thẻ tình trạng tồn kho trên cùng — trùng "Cần nhập hàng gì?" (thẻ đó luôn mở sẵn).

            // 3 card theo nhóm (user 28/10/2026): Hàng Hoá · Bán Hàng · App Đặt Hàng. Kéo thả đổi thứ tự trong 1 nhóm.
            ForEach(nhomDuoi, id: \.self) { nhom in cardNhom(nhom) }
        }
        .navigationTitle("Trợ lý ảo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await taiLai() }
        .sheet(item: $suaTon) { d in
            SuaTonNhanhSheet(dong: d) { Task { await taiLai() } }
        }
        // Mở màn thì tải lại 1 lần (kể cả đang hiện bản nhớ BoNhoTam); quay về từ màn con push vào thì không tải lại
        // (.task chạy lại mỗi lần view xuất hiện — trước đây chặn bằng cauHoi.isEmpty).
        .task {
            guard !daTaiLanMo else { return }
            daTaiLanMo = true
            await taiLai()
        }
    }

    private func taiLai() async {
        dangTai = true
        async let ds = APIClient.shared.getTroLyCauHoi()
        async let cbs = APIClient.shared.getCanhBao()
        let (d, c) = await (ds, cbs)
        capNhatLuc = Date()
        if let c {
            canhBao = c
            CanhBaoBadge.shared.soViec = c.count
        }
        if xemDaXuLy { await taiDaXuLy() }
        if !d.isEmpty { cauHoiGoc = d + Self.mucTrenMay; cauHoi = cauHoiGoc }
        dangTai = false
        BoNhoTam.luu("troLy", TroLySnap(cauHoiGoc: cauHoiGoc, canhBao: canhBao, capNhatLuc: capNhatLuc))
        // Câu nào đang mở thì làm mới luôn; câu đã tải mà đang đóng thì bỏ để lần mở sau tải số mới.
        traLoi = traLoi.filter { moRa.contains($0.key) }
        for ma in moRa where !Self.khongQuaChiTiet.contains(ma) { Task { await hoi(ma) } }
        if daTaiSoDuAi { Task { await taiSoDuAi() } }
    }

    /// Gọi sang OpenRouter nên chỉ tải khi dòng Số dư AI hiện ra, không tải cùng các câu khác.
    private func taiSoDuAi() async {
        soDuAi = await APIClient.shared.getAiBalance()
        daTaiSoDuAi = true
    }

    /// Tải lại riêng mục Cần xử lý (sau khi duyệt tên gửi Zalo — số khách ở tiêu đề đổi, hết thì việc tự xong).
    private func taiCanhBao() async {
        if let c = await APIClient.shared.getCanhBao() {
            canhBao = c
            CanhBaoBadge.shared.soViec = c.count
        }
    }

    private func taiDaXuLy() async {
        if let ds = await APIClient.shared.getCanhBao(daXuLy: true) { daXuLy = ds }
    }

    /// 1 việc: vòng tròn tick bên trái · tiêu đề, nội dung, "Lỗi · 3 lần · 14:05 18/10". Chạm chữ để mở chi tiết
    /// (stack trace/log, sao chép được để gửi Claude).
    @ViewBuilder private func canhBaoRow(_ cb: CanhBaoHeThong) -> some View {
        let mo = moCanhBao.contains(cb.id)
        HStack(alignment: .top, spacing: 12) {
            Button { Task { await tick(cb) } } label: {
                Image(systemName: cb.daXuLy ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(cb.daXuLy ? .green : Self.mauLoai(cb.loai))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(cb.daXuLy ? "Bỏ đánh dấu đã xử lý" : "Đánh dấu đã xử lý")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: Self.iconLoai(cb.loai)).font(.caption).foregroundColor(Self.mauLoai(cb.loai))
                    Text(cb.tieuDe)
                        .font(.subheadline.weight(.semibold))
                        .strikethrough(cb.daXuLy)
                        .foregroundColor(cb.daXuLy ? .textMuted : .primary)
                }
                if let nd = cb.noiDung, !nd.isEmpty {
                    Text(nd).font(.caption).foregroundColor(.textMuted).lineLimit(mo ? nil : 2)
                }
                Text(Self.dongPhu(cb)).font(.caption2).foregroundColor(.textMuted)

                // Việc gom "Duyệt tên gửi Zalo" (30/10/2026): mở ra là danh sách khách, mỗi khách 2 nút.
                if mo, cb.loai == "TenZalo", !cb.daXuLy {
                    TenZaloDuyetList { Task { await taiCanhBao() } }
                }

                if mo, let ct = cb.chiTiet, !ct.isEmpty {
                    ScrollView(.horizontal) {
                        Text(ct)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                    }
                    .frame(maxHeight: 240)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        UIPasteboard.general.string = "\(cb.tieuDe)\n\(cb.noiDung ?? "")\n\n\(ct)"
                    } label: {
                        Label("Sao chép chi tiết", systemImage: "doc.on.doc").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                khongHieuUng {
                    if mo { moCanhBao.remove(cb.id) } else { moCanhBao.insert(cb.id) }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Tick/bỏ tick — đổi trên màn ngay, lỗi mạng thì trả lại như cũ.
    private func tick(_ cb: CanhBaoHeThong) async {
        let moi = !cb.daXuLy
        let truocCanhBao = canhBao, truocDaXuLy = daXuLy
        var doi = cb
        doi.daXuLy = moi
        khongHieuUng {
            if moi {
                canhBao?.removeAll { $0.id == cb.id }
                daXuLy.insert(doi, at: 0)
            } else {
                daXuLy.removeAll { $0.id == cb.id }
                canhBao?.insert(doi, at: 0)
            }
        }
        CanhBaoBadge.shared.soViec = canhBao?.count ?? 0
        let kq = await APIClient.shared.danhDauCanhBao(id: cb.id, daXuLy: moi)
        if !kq.success {
            khongHieuUng {
                canhBao = truocCanhBao
                daXuLy = truocDaXuLy
            }
            CanhBaoBadge.shared.soViec = canhBao?.count ?? 0
        }
    }

    private static func iconLoai(_ loai: String) -> String {
        switch loai {
        case "Loi": return "ladybug.fill"
        case "Vi": return "wallet.pass.fill"
        case "Backup": return "externaldrive.fill.badge.exclamationmark"
        case "TenZalo": return "person.text.rectangle"
        default: return "server.rack"
        }
    }

    private static func mauLoai(_ loai: String) -> Color {
        loai == "Loi" || loai == "Backup" ? .red : loai == "TenZalo" ? .blue : .orange
    }

    private static func dongPhu(_ cb: CanhBaoHeThong) -> String {
        let ten: String
        switch cb.loai {
        case "Loi": ten = "Lỗi"
        case "Vi": ten = "Ví khách"
        case "Backup": ten = "Backup"
        case "TenZalo": ten = "Tin Zalo"
        default: ten = "Máy chủ"
        }
        var parts = [ten]
        if cb.soLan > 1 { parts.append("\(cb.soLan) lần") }
        if cb.daXuLy, let x = cb.xuLyLuc {
            parts.append("xử lý \(ThongBaoNoiBoFormatting.thoiGian(x))")
        } else {
            parts.append(ThongBaoNoiBoFormatting.thoiGian(cb.lanCuoiLuc))
        }
        return parts.joined(separator: " · ")
    }

    private static let maLayHang = "lay-hang"
    /// Giờ vắng khách bung tại chỗ (29/10/2026 user: không cần màn riêng) — giữ mã "man-…" cho khỏi lệch thứ tự đã kéo.
    private static let maGioVang = "man-gio-vang-khach"
    /// Bão hoà bung tại chỗ bản gọn (01/11/2026, user: xổ ra xem luôn, không mở màn mới).
    private static let maBaoHoa = "man-bao-hoa"
    /// Tính lương cũng bung tại chỗ bản gọn (01/11/2026) — mã → tên shipper.
    private static let maTinhLuong: [String: String] = ["man-luong-khanh": "Khánh", "man-luong-nha": "Nhã"]
    /// Câu bung tại chỗ nhưng app tự tải, không gọi /chi-tiet.
    private static let khongQuaChiTiet: Set<String> = Set([maLayHang, maGioVang, maBaoHoa]).union(maTinhLuong.keys)

    private static let icon: [String: String] = [
        "can-nhap": "cart",
        "lay-hang": "list.clipboard",
        "ton-kho": "shippingbox",
        "doanh-thu": "chart.line.uptrend.xyaxis",
        "ban-chay": "trophy",
        "ban-chay-30-ngay": "calendar",
        "nap-xu": "banknote",
        "thong-ke-xu": "dollarsign.circle",
        "xu-khach-dang-giu": "wallet.pass",
        "zalo-zns": "message",
        "khach-moi-cai-app": "person.badge.plus",
        "sap-len-hang": "arrow.up.circle",
        "thuong-thang-toi": "gift",
        "phien-ban-app": "iphone",
        "thong-ke-may": "iphone.gen3",
        "luot-tai-store": "arrow.down.app",
        "app-phan-tich": "chart.xyaxis.line",
        "app-thong-ke-ngay": "sun.max",
        "app-thong-ke-thang": "calendar.circle",
        "man-gio-vang-khach": "clock",
        "man-bao-hoa": "chart.bar",
        "man-ban-do-khach": "map",
        "man-luong-khanh": "fuelpump",
        "man-luong-nha": "fuelpump",
        "so-du-ai": "cpu",
    ]

    private static let maSoDuAi = "so-du-ai"

    /// Mục dời từ Menu sang (user 28/10/2026: trợ lý để đọc/xem, Menu chỉ giữ việc sửa) — app tự chèn vào cuối nhóm
    /// liên quan, kéo thả như câu hỏi; server không biết các mã này. Màn xem chạm là mở màn riêng, không bung tại chỗ
    /// (bản đồ, nhiều biểu đồ không vừa 1 dòng). Tên nhóm phải trùng nhóm server (TroLyService) — lệch thì thành card
    /// riêng. Số dư Zalo OTP vẫn ở Menu vì phải nhập tay số dư.
    private static let mucTrenMay: [TroLyCauHoi] = [
        TroLyCauHoi(ma: "man-gio-vang-khach", noiDung: "Giờ vắng khách", nhom: "Bán Hàng"),
        TroLyCauHoi(ma: "man-bao-hoa", noiDung: "Phân tích bão hoà", nhom: "Bán Hàng"),
        TroLyCauHoi(ma: "man-ban-do-khach", noiDung: "Bản đồ khách hàng", nhom: "Bán Hàng"),
        // "Phiên bản app khách" bỏ màn riêng (29/10/2026) — bấm dòng Mới nhất/Bản cũ/Phải cập nhật trong "Máy mới cài App".
        TroLyCauHoi(ma: "man-luong-khanh", noiDung: "Tính lương Khánh", nhom: "Chi Phí"),
        TroLyCauHoi(ma: "man-luong-nha", noiDung: "Tính lương Nhã", nhom: "Chi Phí"),
        TroLyCauHoi(ma: maSoDuAi, noiDung: "Số dư AI (OpenRouter)", nhom: "Chi Phí"),
    ]

    @ViewBuilder private static func manXem(_ ma: String) -> some View {
        switch ma {
        case "man-bao-hoa": BaoHoaView()
        // Bản đồ offline (12/11/2026); bản Apple Maps cũ mở bằng nút quả táo trên thanh tiêu đề của màn này.
        case "man-ban-do-khach": BanDoOfflineView()
        default: EmptyView()
        }
    }

    private func bamCauHoi(_ ma: String) {
        // Mở/đóng câu hỏi hiện ngay, không hiệu ứng (user 18/10: hiệu ứng làm chữ đè lên nhau lúc bung).
        khongHieuUng {
            if moRa.contains(ma) {
                _ = moRa.remove(ma)
            } else {
                _ = moRa.insert(ma)
                if traLoi[ma] == nil && !Self.khongQuaChiTiet.contains(ma) { Task { await hoi(ma) } }
            }
        }
    }

    private func hoi(_ ma: String) async {
        guard !dangHoi.contains(ma) else { return }
        dangHoi.insert(ma)
        let tl = await APIClient.shared.getTroLyChiTiet(ma)
        dangHoi.remove(ma)
        khongHieuUng { traLoi[ma] = tl }
    }

    /// Nhóm theo thứ tự server trả (thứ tự card cố định, chỉ kéo thả trong nhóm).
    private var nhomCauHoi: [String] {
        var kq: [String] = []
        for c in cauHoiGoc where !kq.contains(c.nhom ?? "") { kq.append(c.nhom ?? "") }
        return kq
    }

    /// Card Chi Phí nằm trên đầu màn (cạnh Duyệt công thức), các card còn lại nằm dưới thẻ tồn kho.
    private static let nhomChiPhi = "Chi Phí"

    private var nhomDuoi: [String] { nhomCauHoi.filter { $0 != Self.nhomChiPhi } }

    @ViewBuilder
    private func cardNhom(_ nhom: String) -> some View {
        Section {
            ForEach(cauHoi.filter { ($0.nhom ?? "") == nhom }) { c in cauHoiRow(c) }
        } header: {
            if !nhom.isEmpty { Text(nhom) }
        } footer: {
            if nhom == nhomDuoi.last { Text("Kéo xuống để làm mới.") }
        }
    }

    @ViewBuilder
    private func nhanCauHoi(_ c: TroLyCauHoi) -> some View {
        Image(systemName: Self.icon[c.ma] ?? "text.bubble")
            .font(.body.weight(.semibold))
            .foregroundColor(.brandPrimary)
            .frame(width: 24)
        Text(c.noiDung).font(.body.weight(.medium)).foregroundColor(.primary)
    }

    @ViewBuilder
    private func cauHoiRow(_ c: TroLyCauHoi) -> some View {
        if c.ma == Self.maSoDuAi {
            HStack(spacing: 12) {
                nhanCauHoi(c)
                Spacer()
                if let s = soDuAi {
                    Text("$\(s.remaining, specifier: "%.2f")")
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(s.remaining < 1 ? .red : .primary)
                } else if daTaiSoDuAi {
                    Text("Không lấy được").font(.subheadline).foregroundColor(.textMuted)
                } else {
                    ProgressView()
                }
            }
            .padding(.vertical, 4)
            .task { if !daTaiSoDuAi { await taiSoDuAi() } }
        } else if !Self.khongQuaChiTiet.contains(c.ma), Self.mucTrenMay.contains(where: { $0.ma == c.ma }) {
            NavigationLink { Self.manXem(c.ma) } label: {
                HStack(spacing: 12) { nhanCauHoi(c) }
            }
            .padding(.vertical, 4)
        } else {
            cauHoiBungRow(c)
        }
    }

    /// Câu đang mở: chữ câu hỏi đậm màu chính, câu trả lời nằm trong khung nền nhạt có vạch màu bên trái — mở nhiều câu
    /// cùng lúc vẫn phân biệt được câu nào của câu trả lời nào (user 01/11/2026).
    @ViewBuilder
    private func cauHoiBungRow(_ c: TroLyCauHoi) -> some View {
        let mo = moRa.contains(c.ma)
        VStack(alignment: .leading, spacing: 10) {
            Button { bamCauHoi(c.ma) } label: {
                HStack(spacing: 12) {
                    Image(systemName: Self.icon[c.ma] ?? "text.bubble")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.brandPrimary)
                        .frame(width: 24)
                    Text(c.noiDung)
                        .font(mo ? .body.weight(.bold) : .body.weight(.medium))
                        .foregroundColor(mo ? .brandPrimary : .primary)
                    Spacer()
                    if dangHoi.contains(c.ma) {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.textMuted)
                            .rotationEffect(.degrees(moRa.contains(c.ma) ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if mo {
                Group {
                    if c.ma == Self.maLayHang {
                        // Có màn tương tác riêng (chọn đại lý, sửa đơn tối thiểu) — không qua chi-tiet.
                        LayHangView()
                    } else if c.ma == Self.maGioVang {
                        GioVangKhachTomTat()
                    } else if c.ma == Self.maBaoHoa {
                        BaoHoaView(tomTat: true)
                    } else if let shipper = Self.maTinhLuong[c.ma] {
                        TinhLuongView(shipperTen: shipper)
                    } else if let tl = traLoi[c.ma] {
                        TroLyTraLoiView(traLoi: tl, onSua: { suaTon = $0 })
                    } else if !dangHoi.contains(c.ma) {
                        Text("Không tải được, chạm lại để thử.").font(.subheadline).foregroundColor(.textMuted)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandPrimary.opacity(0.06))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.brandPrimary).frame(width: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 4)
    }
}

/// Nội dung 1 câu trả lời: số lớn + so sánh, biểu đồ, các dòng.
struct TroLyTraLoiView: View {
    let traLoi: TroLyTraLoi
    /// Có thì dòng tồn kho bấm vào được để sửa nhanh.
    var onSua: ((TroLyTraLoi.Dong) -> Void)? = nil
    /// Dòng đang chọn trong báo cáo chia cột ("cột|tên dòng") — chỉ hiện chi tiết dòng đó, không hiện tất cả.
    @State private var chonCot: String?

    private var conDangChon: (tieuDe: String, dong: [TroLyTraLoi.Dong])? {
        guard let chonCot, let cot = traLoi.cot else { return nil }
        for (i, c) in cot.enumerated() {
            if let d = c.dong.first(where: { "\(i)|\($0.ten)" == chonCot }), let con = d.con {
                return ("\(c.tieuDe ?? "") · \(d.ten)", con)
            }
        }
        return nil
    }

    /// Món bán chạy: biểu đồ cột đã ghi số trên cột, khỏi lặp lại danh sách.
    private var anDong: Bool {
        traLoi.bieuDo?.loai == "cot" && !traLoi.dong.isEmpty && traLoi.dong.allSatisfy { $0.hang != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let td = traLoi.tieuDe {
                SoLon(giaTri: td, moTa: traLoi.moTa, soSanh: traLoi.soSanh, tang: traLoi.soSanhTang)
            }

            if let cot = traLoi.cot, !cot.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(cot.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Divider() }
                        TroLyCotView(cot: c, chon: chonCot.flatMap { $0.hasPrefix("\(i)|") ? String($0.dropFirst("\(i)|".count)) : nil }) { ten in
                            khongHieuUng { chonCot = chonCot == "\(i)|\(ten)" ? nil : "\(i)|\(ten)" }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let c = conDangChon {
                    TroLyConList(tieuDe: c.tieuDe, dong: c.dong)
                }
            } else if let bd = traLoi.bieuDo, !bd.diem.isEmpty {
                switch bd.loai {
                case "duong" where bd.donVi == "ngay":
                    // Trục ngày trong tháng — "Tình hình khách dùng app" (08/11/2026): tháng này vs tháng trước.
                    BieuDoCongDon(diem: bd.diem.map {
                        DiemCongDon(x: Int($0.nhan) ?? 0, giaTri: $0.giaTri, laKyNay: $0.nhom == "Tháng này")
                    }, nhanNay: "Tháng này", nhanTruoc: "Tháng trước", nhanX: { "\($0)" }, buocX: 5)
                case "duong":
                    BieuDoCongDon(diem: bd.diem.map {
                        DiemCongDon(x: Int($0.nhan) ?? 0, giaTri: $0.giaTri, laKyNay: $0.nhom == "Hôm nay")
                    })
                default: TroLyBieuDoCot(bieuDo: bd)
                }
            }

            if traLoi.cot?.isEmpty == false {
                EmptyView()
            } else if !traLoi.dong.isEmpty && !anDong {
                TroLyDongList(dong: traLoi.dong, onSua: onSua)
            } else if traLoi.dong.isEmpty, let tdiep = traLoi.thongDiep {
                Label(tdiep, systemImage: traLoi.trangThai == "ok" ? "checkmark.circle.fill" : "info.circle")
                    .font(.subheadline)
                    .foregroundColor(traLoi.trangThai == "ok" ? .green : .textMuted)
            }
        }
    }
}

enum TroLyMau {
    static func theoMucDo(_ mucDo: String?) -> Color {
        switch mucDo {
        case "het": return .red
        case "thap": return .orange
        case "sapHet": return .yellow
        case "ok": return .green
        default: return .brandPrimary
        }
    }
}

/// Danh sách dòng: chấm màu mức độ (hoặc thứ hạng) · tên + dòng phụ · giá trị canh phải.
struct TroLyDongList: View {
    let dong: [TroLyTraLoi.Dong]
    /// Có thì dòng tồn kho (có nguyenLieuBanHangId) bấm vào được, hiện bút chì nhỏ bên phải.
    var onSua: ((TroLyTraLoi.Dong) -> Void)? = nil

    /// Dòng có `con` đang bung (Thống kê ngày/tháng nhóm App, 01/11/2026: mỗi dòng là 1 câu cũ, bấm xem chi tiết).
    @State private var moCon: Set<String> = []

    /// Cột thứ hạng rộng thêm khi có hạng 2 chữ số — 12pt làm "10" rớt xuống 2 dòng (30/10/2026).
    private var rongCot: CGFloat { dong.contains { ($0.hang ?? 0) >= 10 } ? 20 : 12 }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(dong.enumerated()), id: \.element.id) { i, d in
                if i > 0 { Divider().padding(.leading, rongCot + 10) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let h = d.hang {
                        Text("\(h)").font(.caption.weight(.bold).monospacedDigit()).foregroundColor(.textMuted)
                            .lineLimit(1).fixedSize().frame(width: rongCot, alignment: .leading)
                    } else {
                        Circle().fill(d.mucDo == nil ? Color.green : TroLyMau.theoMucDo(d.mucDo))
                            .frame(width: 8, height: 8).frame(width: rongCot)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.ten).font(.subheadline.weight(moCon.contains(d.ten) ? .bold : .medium))
                            .foregroundColor(moCon.contains(d.ten) ? .brandPrimary : .primary)
                        if let phu = d.phu {
                            Text(phu).font(.caption).foregroundColor(.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(d.giaTri)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(d.mucDo == "het" || d.mucDo == "thap" ? TroLyMau.theoMucDo(d.mucDo) : .primary)
                    if d.nguyenLieuBanHangId != nil, onSua != nil {
                        Image(systemName: "pencil").font(.caption).foregroundColor(.textMuted)
                    }
                    if d.con?.isEmpty == false {
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.textMuted)
                            .rotationEffect(.degrees(moCon.contains(d.ten) ? 180 : 0))
                    }
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    if d.con?.isEmpty == false {
                        khongHieuUng { if moCon.contains(d.ten) { moCon.remove(d.ten) } else { moCon.insert(d.ten) } }
                    } else if d.nguyenLieuBanHangId != nil {
                        onSua?(d)
                    }
                }
                // Danh sách con nằm trong thẻ nền trắng riêng — mở nhiều dòng cùng lúc không dính vào dòng kế (user 01/11/2026).
                if let con = d.con, !con.isEmpty, moCon.contains(d.ten) {
                    TroLyConList(tieuDe: nil, dong: con)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

/// 1 cột của báo cáo chia cột: tên cột + số chính, các dòng gọn (tên trái, giá trị phải), rồi biểu đồ cột ngang.
struct TroLyCotView: View {
    let cot: TroLyTraLoi
    /// Tên dòng đang chọn trong cột này (dòng có `con`), nil = chưa chọn.
    var chon: String? = nil
    var onChon: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                if let td = cot.tieuDe { Text(td).font(.subheadline).foregroundColor(.textMuted) }
                if let mt = cot.moTa { Text(mt).font(.title3.weight(.bold)).monospacedDigit() }
            }
            VStack(spacing: 0) {
                ForEach(Array(cot.dong.enumerated()), id: \.element.id) { i, d in
                    if i > 0 { Divider() }
                    let bamDuoc = d.con?.isEmpty == false && onChon != nil
                    let dangChon = bamDuoc && chon == d.ten
                    HStack(spacing: 6) {
                        Circle().fill(d.mucDo == nil ? Color.green : TroLyMau.theoMucDo(d.mucDo)).frame(width: 7, height: 7)
                        // Không dùng minimumScaleFactor: SwiftUI co chữ mọi dòng trừ dòng cuối (user 12/11/2026: "dòng
                        // cuối có vẻ to hơn") dù tên đủ chỗ. Tên dòng ngắn, thiếu chỗ thì cắt "…".
                        Text(d.ten).font(.caption).lineLimit(1).layoutPriority(1)
                            .foregroundColor(dangChon ? .brandPrimary : .primary)
                            .fontWeight(dangChon ? .semibold : .regular)
                        Spacer(minLength: 4)
                        Text(d.giaTri)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundColor(d.mucDo == "thap" ? TroLyMau.theoMucDo(d.mucDo) : .primary)
                        if bamDuoc {
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(dangChon ? .brandPrimary : .textMuted)
                                .rotationEffect(.degrees(dangChon ? 180 : 0))
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { if bamDuoc { onChon?(d.ten) } }
                }
            }
            if let bd = cot.bieuDo, !bd.diem.isEmpty {
                TroLyBieuDoCot(bieuDo: bd)
            }
        }
    }
}

/// Chi tiết dòng đang chọn của báo cáo chia cột (29/10/2026, thay màn "Phiên bản app khách"): từng máy — tên khách,
/// SĐT · máy · lần mở gần nhất, bản app canh phải. Id theo vị trí vì 1 khách có thể có 2 máy (trùng tên).
struct TroLyConList: View {
    /// nil khi bung ngay dưới dòng cha (tên dòng cha đã nằm trên).
    let tieuDe: String?
    let dong: [TroLyTraLoi.Dong]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let tieuDe {
                Text(tieuDe).font(.caption.weight(.semibold)).foregroundColor(.textMuted).padding(.bottom, 2)
            }
            ForEach(Array(dong.enumerated()), id: \.offset) { i, d in
                if i > 0 { Divider() }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.ten).font(.subheadline.weight(.medium))
                        if let phu = d.phu {
                            Text(phu).font(.caption).foregroundColor(.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(d.giaTri)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                .padding(.vertical, 7)
            }
        }
    }
}

/// Cột ngang: món bán chạy (màu chính) / số ngày còn của tồn kho (màu theo mức độ).
struct TroLyBieuDoCot: View {
    let bieuDo: TroLyTraLoi.BieuDo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if bieuDo.donVi == "ngày" {
                Text("Còn bán được (ngày)").font(.caption).foregroundColor(.textMuted)
            }
            Chart(bieuDo.diem) { d in
                BarMark(x: .value("Giá trị", d.giaTri), y: .value("Tên", d.nhan))
                    .foregroundStyle(TroLyMau.theoMucDo(d.nhom).gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text(d.giaTri.formatted(.number.precision(.fractionLength(0...0))))
                            .font(.caption2.weight(.semibold)).foregroundColor(.textMuted)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(bieuDo.diem.count) * 30 + 8)
        }
    }
}

/// Khách chờ duyệt tên gửi trong tin Zalo ZNS (GET /api/TroLy/ten-zalo, 30/10/2026). Mỗi tên là 1 nút (10/11/2026): tên quán
/// đặt (đã bỏ đuôi " App"/ghi chú trong ngoặc), tên khách tự đặt trong app (nếu có, khác tên quán đặt), và "SĐT" = tin chào
/// bằng số điện thoại — chọn xong không hỏi lại khách đó.
struct TenZaloDuyetList: View {
    var onXong: () -> Void
    @State private var ds: [TenZaloChoDuyet]?
    @State private var dangLuu: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ds {
                if ds.isEmpty { Text("Đã duyệt hết.").font(.caption).foregroundColor(.textMuted) }
                ForEach(ds) { k in
                    VStack(alignment: .leading, spacing: 6) {
                        Text([k.ten, k.sdt].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundColor(.textMuted)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { nutChon(k) }
                            VStack(alignment: .leading, spacing: 6) { nutChon(k) }
                        }
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            } else {
                ProgressView().padding(.vertical, 6)
            }
        }
        .task { ds = await APIClient.shared.getTenZaloChoDuyet() ?? [] }
    }

    @ViewBuilder private func nutChon(_ k: TenZaloChoDuyet) -> some View {
        let khoa = dangLuu.contains(k.id)
        if !k.goiY.isEmpty {
            Button(k.goiY) { Task { await duyet(k, dungTen: true, ten: k.goiY) } }
                .buttonStyle(.borderedProminent).controlSize(.small).lineLimit(1).disabled(khoa)
        }
        if let tuDat = k.goiYTuDat, !tuDat.isEmpty {
            Button(tuDat) { Task { await duyet(k, dungTen: true, ten: tuDat) } }
                .buttonStyle(.borderedProminent).controlSize(.small).lineLimit(1).disabled(khoa)
        }
        Button("SĐT") { Task { await duyet(k, dungTen: false, ten: nil) } }
            .buttonStyle(.bordered).controlSize(.small).disabled(khoa)
    }

    private func duyet(_ k: TenZaloChoDuyet, dungTen: Bool, ten: String?) async {
        dangLuu.insert(k.id)
        let ok = await APIClient.shared.duyetTenZalo(khachHangId: k.id, dungTen: dungTen, ten: ten)
        dangLuu.remove(k.id)
        guard ok else { return }
        ds?.removeAll { $0.id == k.id }
        onXong()
    }
}

struct TenZaloChoDuyet: Decodable, Identifiable {
    let khachHangId: String
    let ten: String
    let goiY: String
    let sdt: String?
    let goiYTuDat: String?   // tên khách tự đặt trong app (10/11/2026), null nếu không có / trùng goiY
    var id: String { khachHangId }
}
