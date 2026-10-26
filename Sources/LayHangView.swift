import SwiftUI
import UIKit

// MARK: - Mô hình dữ liệu (GET /api/TroLy/lay-hang/...)

struct LayHangDaiLy: Codable, Identifiable, Equatable {
    let id: String
    let ten: String
    /// Số lượng tối thiểu (tổng đơn vị nhập: thùng/lốc…) của 1 đơn ở đại lý này, mặc định 4.
    let soLuongToiThieu: Int
    let soMatHang: Int
}

/// Mặt hàng TÍNH BẰNG CÔNG THỨC (tồn kho + lượng bán): lấy `soLuong` đơn vị nhập (thùng/lốc…), tồn đo bằng đơn vị bán.
struct LayHangDong: Codable, Identifiable, Equatable {
    let nguyenLieuId: String
    let ten: String
    let donViTinh: String?
    let soLuong: Int
    let donGia: Double
    let thanhTien: Double
    let donViBan: String?
    let tonHienTai: Double
    let tonSau: Double
    let ngayConTruoc: Double?
    let ngayConSau: Double?
    var id: String { nguyenLieuId }
}

/// Mặt hàng KHÔNG có công thức — AI ước theo lịch sử mua (hiện nhãn "AI ước").
struct LayHangAiDong: Codable, Identifiable, Equatable {
    let nguyenLieuId: String
    let ten: String
    let donViTinh: String?
    let soLuong: Int
    let donGia: Double
    let thanhTien: Double
    let lyDo: String
    var id: String { nguyenLieuId }
}

struct LayHang: Codable, Equatable {
    let nhaCungCapId: String
    let tenDaiLy: String
    let soLuongToiThieu: Int
    let tongSoLuong: Int
    let tongTien: Double
    let datToiThieu: Bool
    let dong: [LayHangDong]
    let uocLuongAi: [LayHangAiDong]
    let boQua: [String]
}

struct LayHangMatHang: Codable, Identifiable, Equatable {
    let nguyenLieuId: String
    let ten: String
    let donViTinh: String?
    let giaNhap: Double
    var daChon: Bool
    var id: String { nguyenLieuId }
}

// MARK: - Logic hiển thị (tách riêng để test)

enum LayHangFormat {
    /// "4" / " 12 " → chỉ lấy chữ số. Rỗng → nil.
    static func doiSo(_ s: String) -> Int? {
        let so = s.filter(\.isNumber)
        return so.isEmpty ? nil : Int(so)
    }

    static func soNguyen(_ v: Double) -> String {
        HoaDonFormatting.moneyFormatter.string(from: NSNumber(value: v.rounded())) ?? "\(Int(v))"
    }

    /// "<1 ngày" / "~15 ngày" / "?" (không có số liệu bán).
    static func ngay(_ d: Double?) -> String {
        guard let d else { return "?" }
        return d < 1 ? "<1 ngày" : "~\(Int(d.rounded())) ngày"
    }

    /// Dòng phụ của món tính bằng công thức: "Tồn 4 chai · <1 ngày → ~22 ngày".
    static func dongPhu(_ d: LayHangDong) -> String {
        let donVi = d.donViBan.map { " \($0.lowercased())" } ?? ""
        return "Tồn \(soNguyen(d.tonHienTai))\(donVi) · \(ngay(d.ngayConTruoc)) → \(ngay(d.ngayConSau))"
    }

    /// Nội dung đơn để dán gửi đại lý (Zalo/tin nhắn).
    static func vanBanDon(_ kq: LayHang) -> String {
        var dong = kq.dong.map { "- \($0.ten) x\($0.soLuong)" }
        dong += kq.uocLuongAi.map { "- \($0.ten) x\($0.soLuong)" }
        return (["Đơn lấy hàng — \(kq.tenDaiLy)"] + dong + ["Tổng: \(kq.tongSoLuong) — \(HoaDonFormatting.money(kq.tongTien))"]).joined(separator: "\n")
    }
}

// MARK: - Model màn "Lên đơn lấy hàng"

@MainActor
final class LayHangModel: ObservableObject {
    @Published var daiLy: [LayHangDaiLy] = []
    @Published var chon: String?
    @Published var soLuongToiThieuText = ""
    @Published var ketQua: LayHang?
    @Published var dangTai = false
    @Published var loi: String?
    @Published var daTaiDanhSach = false

    var daiLyDangChon: LayHangDaiLy? { daiLy.first { $0.id == chon } }
    var mucDangNhap: Int? { LayHangFormat.doiSo(soLuongToiThieuText) }
    /// Mức đang gõ khác mức đã lưu của đại lý → hiện nút "Lưu mặc định".
    var daDoiMuc: Bool {
        guard let d = daiLyDangChon, let m = mucDangNhap else { return false }
        return m != d.soLuongToiThieu
    }

    func taiDanhSach() async {
        guard let ds = await APIClient.shared.getLayHangDaiLy() else {
            loi = "Không tải được danh sách đại lý."
            daTaiDanhSach = true
            return
        }
        daiLy = ds
        daTaiDanhSach = true
        loi = nil
        if chon == nil || !ds.contains(where: { $0.id == chon }) { chon = ds.first?.id }
        if let d = daiLyDangChon { soLuongToiThieuText = String(d.soLuongToiThieu) }
        await tinh(dungMucDaLuu: true)
    }

    private var tinhTreo: Task<Void, Never>?

    /// Bấm +/− số lượng tối thiểu: tự tính lại sau 0,5 giây (bấm liền nhiều lần chỉ gọi server 1 lần).
    func doiMuc(_ v: Int) {
        soLuongToiThieuText = String(v)
        tinhTreo?.cancel()
        tinhTreo = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await tinh()
        }
    }

    func chonDaiLy(_ id: String) async {
        chon = id
        if let d = daiLyDangChon { soLuongToiThieuText = String(d.soLuongToiThieu) }
        await tinh(dungMucDaLuu: true)
    }

    /// dungMucDaLuu = true: để server dùng mức đã lưu của đại lý; false: dùng mức đang gõ (chưa lưu).
    func tinh(dungMucDaLuu: Bool = false) async {
        guard let id = chon else { ketQua = nil; return }
        dangTai = true
        loi = nil
        let (kq, err) = await APIClient.shared.getLayHang(daiLyId: id, soLuongToiThieu: dungMucDaLuu ? nil : mucDangNhap)
        dangTai = false
        if let kq { ketQua = kq } else { ketQua = nil; loi = err }
    }

    /// Lưu số lượng đang gõ làm mặc định của đại lý. Trả thông báo lỗi (nil = thành công).
    func luuMuc() async -> String? {
        guard let id = chon, let muc = mucDangNhap else { return "Nhập số lượng hợp lệ." }
        let kq = await APIClient.shared.datSoLuongToiThieu(daiLyId: id, soLuongToiThieu: muc)
        guard kq.success else { return kq.message ?? "Không lưu được." }
        if let ds = await APIClient.shared.getLayHangDaiLy() { daiLy = ds }
        return nil
    }

    /// Thêm đại lý rồi chọn luôn. Trả thông báo lỗi (nil = thành công).
    func taoDaiLy(ten: String) async -> String? {
        let kq = await APIClient.shared.taoDaiLyLayHang(ten: ten)
        guard kq.success else { return kq.message ?? "Không thêm được đại lý." }
        guard let ds = await APIClient.shared.getLayHangDaiLy() else { return "Đã thêm nhưng không tải lại được danh sách." }
        daiLy = ds
        if let moi = ds.first(where: { $0.ten == ten.trimmingCharacters(in: .whitespacesAndNewlines) }) { await chonDaiLy(moi.id) }
        return nil
    }
}

// MARK: - Màn "Lên đơn lấy hàng" (mở ngay trong Trợ lý ảo)

/// Chọn đại lý → hàng nên lấy sao cho đủ SỐ LƯỢNG tối thiểu (mặc định 4, thùng/cây/bao tính như nhau, sửa được, lưu được) và các món hết đều
/// nhau. Món có công thức tính bằng code; món không có công thức do AI ước theo lịch sử mua (có nhãn "AI ước").
struct LayHangView: View {
    @StateObject private var model = LayHangModel()
    @State private var hienTaoDaiLy = false
    @State private var tenMoi = ""
    @State private var thongBao: String?
    @State private var xemBoQua = false
    @State private var daSaoChep = false
    @State private var hienMatHang = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.daTaiDanhSach {
                HStack { ProgressView(); Text("Đang tải đại lý…").foregroundColor(.textMuted) }
            } else if model.daiLy.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.loi ?? "Chưa có đại lý nào. Thêm đại lý rồi chọn mặt hàng đại lý đó bán.")
                        .font(.subheadline).foregroundColor(.textMuted)
                    themDaiLyButton
                }
            } else {
                chonDaiLyRow
                donToiThieuRow
                ketQuaView
                hanhDongRow
            }
            if let thongBao {
                Text(thongBao).font(.footnote).foregroundColor(.orange)
            }
        }
        .padding(.vertical, 2)
        .task { if !model.daTaiDanhSach { await model.taiDanhSach() } }
        .alert("Thêm đại lý", isPresented: $hienTaoDaiLy) {
            TextField("Tên đại lý", text: $tenMoi)
            Button("Huỷ", role: .cancel) { tenMoi = "" }
            Button("Thêm") {
                let ten = tenMoi
                tenMoi = ""
                Task { thongBao = await model.taoDaiLy(ten: ten) }
            }
        } message: {
            Text("Số lượng tối thiểu mặc định 4 (thùng, cây, bao… tính như nhau), sửa được sau. Thêm xong chọn mặt hàng đại lý đó bán.")
        }
        .navigationDestination(isPresented: $hienMatHang) {
            if let d = model.daiLyDangChon {
                MatHangDaiLyView(daiLy: d) {
                    Task { await model.taiDanhSach() }
                }
            }
        }
    }

    private var themDaiLyButton: some View {
        Button { hienTaoDaiLy = true } label: {
            Label("Thêm đại lý", systemImage: "plus.circle").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderless)
    }

    /// Đại lý (chỉ tên) + menu "…" gom các thao tác ít dùng.
    private var chonDaiLyRow: some View {
        HStack(spacing: 10) {
            Picker("Đại lý", selection: Binding(
                get: { model.chon ?? "" },
                set: { id in Task { await model.chonDaiLy(id) } }
            )) {
                ForEach(model.daiLy) { d in
                    Text(d.ten).tag(d.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer(minLength: 0)
            Menu {
                Button { hienMatHang = true } label: {
                    Label("Mặt hàng của đại lý (\(model.daiLyDangChon?.soMatHang ?? 0))", systemImage: "list.bullet")
                }
                Button { hienTaoDaiLy = true } label: {
                    Label("Thêm đại lý", systemImage: "plus")
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
    }

    /// Tối thiểu (thùng, cây, bao… tính như nhau): bấm +/− là tự tính lại, không cần nút "Tính lại".
    private var donToiThieuRow: some View {
        HStack(spacing: 10) {
            Text("Tối thiểu").font(.subheadline).foregroundColor(.textMuted)
            Text("\(model.mucDangNhap ?? 0) đơn vị").font(.subheadline.weight(.semibold)).monospacedDigit()
            if model.daDoiMuc {
                Button("Lưu") { Task { thongBao = await model.luuMuc() } }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
            Stepper("Tối thiểu", value: Binding(
                get: { model.mucDangNhap ?? 4 },
                set: { model.doiMuc($0) }
            ), in: 1...50)
            .labelsHidden()
        }
    }

    @ViewBuilder private var ketQuaView: some View {
        if model.dangTai {
            HStack { ProgressView(); Text("Đang tính… (món chưa có công thức sẽ hỏi AI, có thể mất vài giây)").font(.footnote).foregroundColor(.textMuted) }
        } else if let kq = model.ketQua {
            VStack(alignment: .leading, spacing: 10) {
                tongKet(kq)
                if kq.dong.isEmpty && kq.uocLuongAi.isEmpty {
                    Label("Chưa cần lấy gì ở đại lý này.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundColor(.green)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(kq.dong.enumerated()), id: \.element.id) { i, d in
                            if i > 0 { Divider() }
                            dongCongThuc(d)
                        }
                        ForEach(Array(kq.uocLuongAi.enumerated()), id: \.element.id) { i, d in
                            if i > 0 || !kq.dong.isEmpty { Divider() }
                            dongAi(d)
                        }
                    }
                }
                if !kq.boQua.isEmpty { boQuaView(kq.boQua) }
            }
        } else if let loi = model.loi {
            Text(loi).font(.subheadline).foregroundColor(.red)
        }
    }

    private func tongKet(_ kq: LayHang) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(HoaDonFormatting.money(kq.tongTien)).font(.title2.weight(.bold)).monospacedDigit()
            Spacer()
            if !(kq.dong.isEmpty && kq.uocLuongAi.isEmpty) {
                Label("\(kq.tongSoLuong)/\(kq.soLuongToiThieu)",
                      systemImage: kq.datToiThieu ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundColor(kq.datToiThieu ? .green : .orange)
            }
        }
    }

    /// "2×" đứng đầu dòng, cột cố định cho thẳng hàng.
    private func soLuongCot(_ n: Int) -> some View {
        Text("\(n)×").font(.subheadline.weight(.bold)).monospacedDigit()
            .foregroundColor(.brandPrimary)
            .frame(minWidth: 26, alignment: .leading)
    }

    private func dongCongThuc(_ d: LayHangDong) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            soLuongCot(d.soLuong)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.ten).font(.subheadline.weight(.medium))
                Text(LayHangFormat.dongPhu(d)).font(.caption).foregroundColor(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(HoaDonFormatting.money(d.thanhTien)).font(.subheadline).monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    private func dongAi(_ d: LayHangAiDong) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            soLuongCot(d.soLuong)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.ten).font(.subheadline.weight(.medium))
                    Text("AI ước")
                        .font(.caption2.weight(.bold)).foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple).clipShape(Capsule())
                }
                Text(d.lyDo).font(.caption).foregroundColor(.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(HoaDonFormatting.money(d.thanhTien)).font(.subheadline).monospacedDigit()
        }
        .padding(.vertical, 8)
    }

    private func boQuaView(_ ds: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                khongHieuUng { xemBoQua.toggle() }
            } label: {
                Label(xemBoQua ? "Ẩn món chưa lấy / chưa tính được" : "Món chưa lấy / chưa tính được (\(ds.count))",
                      systemImage: xemBoQua ? "chevron.up" : "chevron.down")
                    .font(.footnote)
            }
            .buttonStyle(.borderless)
            if xemBoQua {
                ForEach(ds, id: \.self) { s in
                    Text("• \(s)").font(.caption).foregroundColor(.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Chỉ còn 1 nút chính; "Mặt hàng của đại lý" / "Thêm đại lý" nằm trong menu "…" ở đầu.
    @ViewBuilder private var hanhDongRow: some View {
        if let kq = model.ketQua, !(kq.dong.isEmpty && kq.uocLuongAi.isEmpty) {
            Button {
                UIPasteboard.general.string = LayHangFormat.vanBanDon(kq)
                daSaoChep = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    daSaoChep = false
                }
            } label: {
                Label(daSaoChep ? "Đã sao chép" : "Sao chép đơn", systemImage: daSaoChep ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Màn "Mặt hàng của đại lý"

/// Chọn những nguyên liệu đại lý này lấy được (một nguyên liệu gắn được nhiều đại lý). Lưu = đặt lại TOÀN BỘ danh sách.
struct MatHangDaiLyView: View {
    let daiLy: LayHangDaiLy
    let onXong: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ds: [LayHangMatHang] = []
    @State private var timKiem = ""
    @State private var dangTai = true
    @State private var dangLuu = false
    @State private var loi: String?

    private var hienThi: [LayHangMatHang] {
        let q = timKiem.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !q.isEmpty else { return ds }
        return ds.filter { $0.ten.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) }
    }

    private var soDaChon: Int { ds.filter(\.daChon).count }

    var body: some View {
        List {
            if dangTai {
                HStack { ProgressView(); Text("Đang tải…").foregroundColor(.textMuted) }
            } else if let loi {
                Text(loi).foregroundColor(.red)
            }
            ForEach(hienThi) { m in
                Button {
                    if let i = ds.firstIndex(where: { $0.id == m.id }) { ds[i].daChon.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: m.daChon ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(m.daChon ? .brandPrimary : .textMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.ten).font(.body).foregroundColor(.primary)
                            Text("\(m.donViTinh ?? "—") · \(HoaDonFormatting.money(m.giaNhap))")
                                .font(.caption).foregroundColor(.textMuted)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .searchable(text: $timKiem, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm nguyên liệu")
        .navigationTitle(daiLy.ten)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(dangLuu ? "Đang lưu…" : "Lưu (\(soDaChon))") { Task { await luu() } }
                    .disabled(dangTai || dangLuu)
            }
        }
        .task { await tai() }
    }

    private func tai() async {
        dangTai = true
        if let kq = await APIClient.shared.getLayHangMatHang(daiLyId: daiLy.id) {
            ds = kq
            loi = nil
        } else {
            loi = "Không tải được danh sách nguyên liệu."
        }
        dangTai = false
    }

    private func luu() async {
        dangLuu = true
        let kq = await APIClient.shared.datLayHangMatHang(daiLyId: daiLy.id, nguyenLieuIds: ds.filter(\.daChon).map(\.nguyenLieuId))
        dangLuu = false
        if kq.success {
            onXong()
            dismiss()
        } else {
            loi = kq.message ?? "Không lưu được."
        }
    }
}
