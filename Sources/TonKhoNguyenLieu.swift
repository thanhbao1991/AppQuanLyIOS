import SwiftUI

/// Tồn kho hiện trong màn "Nguyên liệu & giá" (thay mục menu "Tồn kho" riêng). Nguồn số duy nhất là
/// NguyenLieuBanHangs.TonKho (đơn vị BÁN, vd lon) — tự trừ khi bán theo công thức, tự cộng khi nhập Chi
/// tiêu. Nguyên liệu mua (vd thùng) chỉ quy đổi để hiển thị/kiểm kê qua HeSoQuyDoiBanHang (1 thùng = 24 lon).
/// Quy ước từ 17/10/2026: tồn ≥ 0 = đang theo dõi thật (đã kiểm kê), mọi món khác đặt −1 = chưa theo dõi
/// (số cũ ở bảng _Backup_TonKho_20261017/_20261017b). Chỉ hiện số khi tồn ≥ 0.
enum TonKhoNguyenLieu {
    static func coTheTheoDoi(_ nl: NguyenLieuDto) -> Bool { nl.nguyenLieuBanHangId != nil }

    /// Đang theo dõi thật = đã nối + tồn ≥ 0.
    static func dangTheoDoi(_ nl: NguyenLieuDto) -> Bool {
        coTheTheoDoi(nl) && (nl.tonKhoBanHang ?? -1) >= 0
    }

    /// Nhãn chính trên dòng: "5 ly" khi biết số ly size chuẩn, không thì số tồn quy đổi.
    static func nhanDong(_ nl: NguyenLieuDto) -> String? {
        guard dangTheoDoi(nl) else { return nil }
        if let ly = nl.soLyConLai { return "\(ly) ly" }
        return chinh(nl)
    }

    /// Dòng phụ: số tồn theo đơn vị bán ("= 1600 G", "= 5 Lon").
    static func phuDong(_ nl: NguyenLieuDto) -> String? {
        guard dangTheoDoi(nl), let ton = nl.tonKhoBanHang else { return nil }
        if nl.soLyConLai == nil { return phu(nl) }
        return "= \(so(ton)) \(nl.donViTinhBanHang ?? "")".trimmingCharacters(in: .whitespaces)
    }

    private static func heSo(_ nl: NguyenLieuDto) -> Double? {
        guard let h = nl.heSoQuyDoiBanHang, h > 0, h != 1 else { return nil }
        return h
    }

    /// "2 thùng" (quy đổi theo đơn vị nhập nếu có hệ số), không thì "48 lon".
    static func chinh(_ nl: NguyenLieuDto) -> String? {
        guard let ton = nl.tonKhoBanHang else { return nil }
        if let h = heSo(nl) {
            return "\(so(ton / h)) \(nl.donViTinh ?? "")".trimmingCharacters(in: .whitespaces)
        }
        return "\(so(ton)) \(nl.donViTinhBanHang ?? nl.donViTinh ?? "")".trimmingCharacters(in: .whitespaces)
    }

    /// Dòng phụ "= 48 lon" khi đang hiện theo đơn vị nhập.
    static func phu(_ nl: NguyenLieuDto) -> String? {
        guard heSo(nl) != nil, let ton = nl.tonKhoBanHang else { return nil }
        return "= \(so(ton)) \(nl.donViTinhBanHang ?? "")".trimmingCharacters(in: .whitespaces)
    }

    static func mau(_ nl: NguyenLieuDto) -> Color {
        guard let ton = nl.tonKhoBanHang else { return .textMuted }
        if ton < 0 { return .red }
        if ton == 0 || (nl.soLyConLai ?? 99) <= 2 { return .orange }
        return .primary
    }

    static func so(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r.rounded() == r ? String(Int(r)) : String(format: "%.2f", r)
    }
}

/// Kiểm kê 1 nguyên liệu: nhập số đếm thực tế theo đơn vị nhập (thùng) — tự nhân hệ số ra đơn vị bán
/// rồi ghi đè qua PUT /api/NguyenLieuBanHang/{id}/adjust. Mở tự động khi vừa bật "Quản lý số lượng".
struct KiemKeTonKhoSheet: View {
    let nguyenLieu: NguyenLieuDto
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var soLuongText = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var heSo: Double {
        guard let h = nguyenLieu.heSoQuyDoiBanHang, h > 0 else { return 1 }
        return h
    }
    private var donViNhap: String { (heSo != 1 ? nguyenLieu.donViTinh : nguyenLieu.donViTinhBanHang ?? nguyenLieu.donViTinh) ?? "đơn vị" }
    private var parsed: Double? {
        Double(soLuongText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Số lượng đếm được", text: $soLuongText)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Đếm thực tế (\(donViNhap))")
                } footer: {
                    if heSo != 1, let v = parsed {
                        Text("= \(TonKhoNguyenLieu.so(v * heSo)) \(nguyenLieu.donViTinhBanHang ?? "") (1 \(nguyenLieu.donViTinh ?? "") = \(TonKhoNguyenLieu.so(heSo)) \(nguyenLieu.donViTinhBanHang ?? ""))")
                    }
                }
                Section {
                    Text("Hiện tại: \(TonKhoNguyenLieu.dangTheoDoi(nguyenLieu) ? (TonKhoNguyenLieu.chinh(nguyenLieu) ?? "—") : "chưa theo dõi")")
                        .foregroundColor(.textMuted)
                } footer: {
                    Text("Từ giờ số tồn tự trừ khi bán theo công thức và tự cộng khi nhập Chi tiêu.")
                }
            }
            .navigationTitle("Kiểm kê · \(nguyenLieu.ten)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Để sau") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }.disabled(saving || parsed == nil)
                }
            }
            .alert("Lỗi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
            .onAppear {
                if let ton = nguyenLieu.tonKhoBanHang, ton > 0 { soLuongText = TonKhoNguyenLieu.so(ton / heSo) }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        guard let v = parsed, let bhId = nguyenLieu.nguyenLieuBanHangId else { return }
        saving = true
        defer { saving = false }
        let result = await APIClient.shared.dieuChinhTonKho(id: bhId, tonKhoThucTe: v * heSo, ghiChu: "Kiểm kê từ Nguyên liệu & giá")
        if result.success {
            await onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được tồn kho."
        }
    }
}
