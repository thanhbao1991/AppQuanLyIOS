import SwiftUI

enum SuaTonNhanhFormat {
    /// "500" / "12,5" / "12.5" → số. Rỗng/chữ → nil.
    static func doiSo(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }

    /// Số nguyên bỏ phần thập phân, còn lại tối đa 2 chữ số.
    static func soChu(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.2f", v)
    }
}

/// Sửa nhanh tồn kho ngay trong Trợ lý ảo (25/10/2026): bấm vào 1 dòng tồn kho → gõ số đếm thực tế → Lưu.
/// Ô nhập để TRỐNG (số hiện tại ghi ngay bên dưới) và bật bàn phím sẵn, gõ số rồi Lưu là xong. Dùng chung API kiểm kê
/// (PUT /api/NguyenLieuBanHang/{id}/adjust) với màn Tồn kho — số nhập ghi đè tồn hiện tại theo ĐƠN VỊ BÁN.
struct SuaTonNhanhSheet: View {
    let dong: TroLyTraLoi.Dong
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var soLuongText = ""
    @State private var dangLuu = false
    @State private var loi: String?
    @FocusState private var dangNhap: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Tồn kho thực tế (\(dong.donVi ?? "đơn vị"))") {
                    TextField(dong.ton.map(SuaTonNhanhFormat.soChu) ?? "Số lượng", text: $soLuongText)
                        .keyboardType(.decimalPad)
                        .focused($dangNhap)
                }
                if let ton = dong.ton {
                    Section {
                        Text("Hiện tại: \(SuaTonNhanhFormat.soChu(ton)) \(dong.donVi ?? "")").foregroundColor(.textMuted)
                    }
                }
                if let loi {
                    Section { Text(loi).foregroundColor(.red) }
                }
            }
            .navigationTitle(dong.ten)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(dangLuu ? "Đang lưu…" : "Lưu") { Task { await luu() } }
                        .disabled(dangLuu || SuaTonNhanhFormat.doiSo(soLuongText) == nil)
                }
            }
            .onAppear { dangNhap = true }
        }
        .presentationDetents([.medium])
    }

    private func luu() async {
        guard let id = dong.nguyenLieuBanHangId, let gia = SuaTonNhanhFormat.doiSo(soLuongText) else { return }
        dangLuu = true
        defer { dangLuu = false }
        let kq = await APIClient.shared.dieuChinhTonKho(id: id, tonKhoThucTe: gia, ghiChu: "Sửa nhanh từ Trợ lý ảo")
        if kq.success {
            onSaved()
            dismiss()
        } else {
            loi = kq.message ?? "Không lưu được tồn kho."
        }
    }
}
