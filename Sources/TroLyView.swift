import Charts
import SwiftUI
import UIKit

/// 1 câu hỏi bấm sẵn của trợ lý — server trả danh sách (GET /api/TroLy/cau-hoi).
struct TroLyCauHoi: Codable, Identifiable, Equatable {
    let ma: String
    let noiDung: String
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
/// không muốn phải đọc hết mọi câu. Kéo xuống để làm mới; nhấn giữ rồi kéo 1 câu để đổi thứ tự — lưu trên máy
/// (AppStorage), câu hỏi mới server thêm sẽ nằm cuối. Thứ tự mặc định do server xếp theo nhóm liên quan (hàng hoá →
/// bán hàng → Xu); khoá lưu đổi sang ".v2" (25/10/2026) để mọi máy về đúng thứ tự nhóm mới, kéo lại thì lưu lại bình thường.
struct TroLyView: View {
    @AppStorage("troLy.thuTu.v2") private var thuTuRaw = ""
    @State private var tongQuan: TroLyTraLoi?
    @State private var cauHoi: [TroLyCauHoi] = []
    @State private var traLoi: [String: TroLyTraLoi] = [:]
    @State private var moRa: Set<String> = []
    @State private var dangHoi: Set<String> = []
    @State private var dangTai = true
    @State private var capNhatLuc: Date?
    /// nil = không phải Admin / lỗi → ẩn mục Cần xử lý.
    @State private var canhBao: [CanhBaoHeThong]?
    @State private var daXuLy: [CanhBaoHeThong] = []
    @State private var xemDaXuLy = false
    @State private var moCanhBao: Set<String> = []
    @StateObject private var duyetCongThuc = DuyetCongThucSizeModel()
    /// Dòng tồn kho đang được sửa nhanh (bấm vào dòng trong thẻ tình trạng hoặc câu trả lời).
    @State private var suaTon: TroLyTraLoi.Dong?

    var body: some View {
        List {
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

            DuyetCongThucSizeSection(model: duyetCongThuc)

            Section {
                theTinhTrang
            }

            Section {
                ForEach(cauHoi) { c in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { bamCauHoi(c.ma) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: Self.icon[c.ma] ?? "questionmark.circle")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.brandPrimary)
                                    .frame(width: 24)
                                Text(c.noiDung).font(.body.weight(.medium)).foregroundColor(.primary)
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

                        if moRa.contains(c.ma) {
                            if c.ma == Self.maLayHang {
                                // Có màn tương tác riêng (chọn đại lý, sửa đơn tối thiểu) — không qua chi-tiet.
                                LayHangView()
                            } else if let tl = traLoi[c.ma] {
                                TroLyTraLoiView(traLoi: tl, onSua: { suaTon = $0 })
                            } else if !dangHoi.contains(c.ma) {
                                Text("Không tải được, chạm lại để thử.").font(.subheadline).foregroundColor(.textMuted)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onMove { tu, den in
                    cauHoi.move(fromOffsets: tu, toOffset: den)
                    thuTuRaw = cauHoi.map(\.ma).joined(separator: ",")
                }
            } footer: {
                if !cauHoi.isEmpty { Text("Kéo xuống để làm mới · nhấn giữ rồi kéo để đổi thứ tự.") }
            }
        }
        .navigationTitle("Trợ lý ảo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await taiLai() }
        .duyetCongThucSheet(duyetCongThuc)
        .sheet(item: $suaTon) { d in
            SuaTonNhanhSheet(dong: d) { Task { await taiLai() } }
        }
        .task { if cauHoi.isEmpty { await taiLai() } }
    }

    @ViewBuilder private var theTinhTrang: some View {
        let ok = tongQuan?.trangThai == "ok"
        let capNhat = capNhatLuc.map { "Cập nhật \($0.formatted(date: .omitted, time: .shortened))" }
        VStack(alignment: .leading, spacing: 12) {
            if let tq = tongQuan {
                TheKetLuan(mucDo: ok ? .tot : .canhBao,
                           tieuDe: ok ? "Tồn kho ổn" : (tq.thongDiep ?? ""),
                           moTa: ok ? tq.thongDiep : capNhat)
            } else if dangTai {
                HStack { ProgressView(); Text("Đang xem tồn kho…").foregroundColor(.textMuted) }
            } else {
                Text("Không tải được tồn kho.").foregroundColor(.textMuted)
            }
            if let tq = tongQuan, !tq.dong.isEmpty {
                TroLyDongList(dong: tq.dong, onSua: { suaTon = $0 })
            }
        }
        .padding(.vertical, 6)
    }

    private func taiLai() async {
        dangTai = true
        async let tq = APIClient.shared.getTroLyTongQuan()
        async let ds = APIClient.shared.getTroLyCauHoi()
        async let cbs = APIClient.shared.getCanhBao()
        async let duyet: Void = duyetCongThuc.load()
        let (t, d, c, _) = await (tq, ds, cbs, duyet)
        tongQuan = t
        if let c {
            canhBao = c
            CanhBaoBadge.shared.soViec = c.count
        }
        if xemDaXuLy { await taiDaXuLy() }
        if !d.isEmpty { cauHoi = sapTheoThuTu(d) }
        capNhatLuc = Date()
        dangTai = false
        // Câu nào đang mở thì làm mới luôn; câu đã tải mà đang đóng thì bỏ để lần mở sau tải số mới.
        traLoi = traLoi.filter { moRa.contains($0.key) }
        for ma in moRa where ma != Self.maLayHang { Task { await hoi(ma) } }
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
        default: return "server.rack"
        }
    }

    private static func mauLoai(_ loai: String) -> Color {
        loai == "Loi" || loai == "Backup" ? .red : .orange
    }

    private static func dongPhu(_ cb: CanhBaoHeThong) -> String {
        let ten: String
        switch cb.loai {
        case "Loi": ten = "Lỗi"
        case "Vi": ten = "Ví khách"
        case "Backup": ten = "Backup"
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

    private static let icon: [String: String] = [
        "can-nhap": "cart",
        "lay-hang": "list.clipboard",
        "ton-kho": "shippingbox",
        "doanh-thu": "chart.line.uptrend.xyaxis",
        "ban-chay": "trophy",
        "ban-chay-30-ngay": "calendar",
        "nap-xu": "banknote",
    ]

    private func bamCauHoi(_ ma: String) {
        // Mở/đóng câu hỏi hiện ngay, không hiệu ứng (user 18/10: hiệu ứng làm chữ đè lên nhau lúc bung).
        khongHieuUng {
            if moRa.contains(ma) {
                _ = moRa.remove(ma)
            } else {
                _ = moRa.insert(ma)
                if traLoi[ma] == nil && ma != Self.maLayHang { Task { await hoi(ma) } }
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

    private func sapTheoThuTu(_ ds: [TroLyCauHoi]) -> [TroLyCauHoi] {
        let thuTu = thuTuRaw.split(separator: ",").map(String.init)
        let viTri = { (i: Int, c: TroLyCauHoi) in (thuTu.firstIndex(of: c.ma) ?? thuTu.count, i) }
        return ds.enumerated().sorted { viTri($0.offset, $0.element) < viTri($1.offset, $1.element) }.map(\.element)
    }
}

/// Nội dung 1 câu trả lời: số lớn + so sánh, biểu đồ, các dòng.
struct TroLyTraLoiView: View {
    let traLoi: TroLyTraLoi
    /// Có thì dòng tồn kho bấm vào được để sửa nhanh.
    var onSua: ((TroLyTraLoi.Dong) -> Void)? = nil

    /// Món bán chạy: biểu đồ cột đã ghi số trên cột, khỏi lặp lại danh sách.
    private var anDong: Bool {
        traLoi.bieuDo?.loai == "cot" && !traLoi.dong.isEmpty && traLoi.dong.allSatisfy { $0.hang != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let td = traLoi.tieuDe {
                SoLon(giaTri: td, moTa: traLoi.moTa, soSanh: traLoi.soSanh, tang: traLoi.soSanhTang)
            }

            if let bd = traLoi.bieuDo, !bd.diem.isEmpty {
                switch bd.loai {
                case "duong":
                    BieuDoCongDon(diem: bd.diem.map {
                        DiemCongDon(x: Int($0.nhan) ?? 0, giaTri: $0.giaTri, laKyNay: $0.nhom == "Hôm nay")
                    })
                default: TroLyBieuDoCot(bieuDo: bd)
                }
            }

            if !traLoi.dong.isEmpty && !anDong {
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(dong.enumerated()), id: \.element.id) { i, d in
                if i > 0 { Divider().padding(.leading, 22) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let h = d.hang {
                        Text("\(h)").font(.caption.weight(.bold)).foregroundColor(.textMuted).frame(width: 12)
                    } else {
                        Circle().fill(d.mucDo == nil ? Color.green : TroLyMau.theoMucDo(d.mucDo))
                            .frame(width: 8, height: 8).frame(width: 12)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.ten).font(.subheadline.weight(.medium))
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
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture { if d.nguyenLieuBanHangId != nil { onSua?(d) } }
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
