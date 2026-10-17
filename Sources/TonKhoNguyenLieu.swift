import SwiftUI

/// Tồn kho hiện trong màn "Nguyên liệu & giá" (thay mục menu "Tồn kho" riêng). Nguồn số duy nhất là
/// NguyenLieuBanHangs.TonKho (đơn vị BÁN, vd lon) — tự trừ khi bán theo công thức, tự cộng khi nhập Chi
/// tiêu. Nguyên liệu mua (vd thùng) chỉ quy đổi để hiển thị/kiểm kê qua HeSoQuyDoiBanHang (1 thùng = 24 lon).
/// Toàn bộ tồn kho đã reset về 0 ngày 17/10/2026 để bắt đầu theo dõi thật (số cũ ở bảng
/// _Backup_TonKho_20261017) — chỉ món bật "Quản lý số lượng" mới hiện số.
enum TonKhoNguyenLieu {
    static func coTheTheoDoi(_ nl: NguyenLieuDto) -> Bool { nl.nguyenLieuBanHangId != nil }

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
        return ton < 0 ? .red : ton == 0 ? .orange : .primary
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
                    Text("Hiện tại: \(TonKhoNguyenLieu.chinh(nguyenLieu) ?? "—")")
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
                if let ton = nguyenLieu.tonKhoBanHang, ton != 0 { soLuongText = TonKhoNguyenLieu.so(ton / heSo) }
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
