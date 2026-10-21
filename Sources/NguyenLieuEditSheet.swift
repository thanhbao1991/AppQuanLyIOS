import SwiftUI

/// Nhãn hiển thị cho NguyenLieuDto.phanLoai — khớp giá trị int lưu ở Backend (NguyenLieuEntity.PhanLoai).
enum PhanLoaiNguyenLieu: Int, CaseIterable, Identifiable {
    case nguyenLieu = 1
    case vatLieu = 2
    case chiPhiKhac = 3
    case vatTu = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .nguyenLieu: return "Nguyên liệu"
        case .vatLieu: return "Vật liệu"
        case .chiPhiKhac: return "Chi phí khác"
        case .vatTu: return "Vật tư"
        }
    }

    var color: Color {
        switch self {
        case .nguyenLieu: return .brandPrimary
        case .vatLieu: return .blue
        case .chiPhiKhac: return .textMuted
        case .vatTu: return .orange
        }
    }

    /// Tiêu đề màn "Giá ..." (GiaNguyenLieuView) ứng với nhóm này.
    var giaScreenTitle: String {
        switch self {
        case .nguyenLieu: return "Giá nguyên liệu"
        case .vatLieu: return "Giá vật liệu"
        case .chiPhiKhac: return "Giá chi phí khác"
        case .vatTu: return "Giá vật tư"
        }
    }

    static func label(for rawValue: Int) -> String? {
        PhanLoaiNguyenLieu(rawValue: rawValue)?.label
    }

    static func color(for rawValue: Int) -> Color {
        PhanLoaiNguyenLieu(rawValue: rawValue)?.color ?? .textMuted
    }
}

/// Sheet thêm/sửa/xoá nguyên liệu — mở từ màn "Nguyên liệu & giá" (GiaNguyenLieuView): nút + trên
/// toolbar để thêm, nút "Sửa" ở màn chi tiết giá để sửa/xoá. Trước đây có màn danh mục riêng
/// (NguyenLieuListView), đã gộp vào GiaNguyenLieuView cho khỏi 2 mục menu cùng 1 danh sách.
/// GET/POST/PUT/DELETE /api/NguyenLieu.
struct NguyenLieuEditSheet: View {
    let existing: NguyenLieuDto?
    /// Gọi sau khi lưu thành công (xoá nằm ở vuốt trái trên danh sách GiaNguyenLieuView).
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten: String
    @State private var donViTinh: String
    @State private var giaNhap: Double
    @State private var ngungSuDung: Bool
    @State private var phanLoai: Int?
    @State private var saving = false
    @State private var errorMessage: String?
    /// Nối tồn kho: nguyên liệu bán hàng (đơn vị bán, vd lon) + 1 đơn vị nhập = bao nhiêu đơn vị bán.
    @State private var nguyenLieuBanHangId: String?
    @State private var heSoQuyDoi: Double?
    @State private var dsBanHang: [NguyenLieuBanHangDto] = []

    init(existing: NguyenLieuDto?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _ten = State(initialValue: existing?.ten ?? "")
        _donViTinh = State(initialValue: existing?.donViTinh ?? "")
        _giaNhap = State(initialValue: existing?.giaNhap ?? 0)
        _ngungSuDung = State(initialValue: existing?.ngungSuDung ?? false)
        _phanLoai = State(initialValue: existing?.phanLoai)
        _nguyenLieuBanHangId = State(initialValue: existing?.nguyenLieuBanHangId)
        _heSoQuyDoi = State(initialValue: existing?.heSoQuyDoiBanHang)
    }

    /// Đang dùng + mục đang chọn (kể cả khi nó đã ngừng dùng, để không mất liên kết cũ khi lưu).
    private var dsBanHangChon: [NguyenLieuBanHangDto] {
        dsBanHang.filter { $0.dangSuDung != false || $0.id == nguyenLieuBanHangId }
            .sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
    }

    private var donViBan: String {
        dsBanHang.first { $0.id == nguyenLieuBanHangId }?.donViTinh ?? "đơn vị bán"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên nguyên liệu", text: $ten)
                    TextField("Đơn vị tính (VD: Kg, Ly, Cái...)", text: $donViTinh)
                    HStack {
                        Text("Giá nhập")
                        Spacer()
                        TextField("0", value: $giaNhap, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Phân loại") {
                    Picker("Loại", selection: $phanLoai) {
                        Text("Chưa phân loại").tag(Int?.none)
                        ForEach(PhanLoaiNguyenLieu.allCases) { loai in
                            Text(loai.label).tag(Int?.some(loai.rawValue))
                        }
                    }
                }

                // Nối tồn kho — trước đây không sửa được ở đâu (Desktop cũng không có màn này), nên
                // bật "Quản lý số lượng" cho món chưa nối là vô dụng. Số tồn nằm ở nguyên liệu bán hàng.
                Section {
                    Picker("Nguyên liệu bán hàng", selection: $nguyenLieuBanHangId) {
                        Text("Không nối").tag(String?.none)
                        ForEach(dsBanHangChon) { bh in
                            Text(bh.ten).tag(String?.some(bh.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    if nguyenLieuBanHangId != nil {
                        HStack {
                            Text("1 \(donViTinh.isEmpty ? "đơn vị nhập" : donViTinh) =")
                            Spacer()
                            TextField("1", value: $heSoQuyDoi, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 90)
                            Text(donViBan).foregroundColor(.textMuted)
                        }
                    }
                } header: {
                    Text("Tồn kho")
                } footer: {
                    Text("Nhập Chi tiêu món này sẽ cộng tồn theo hệ số (vd 1 thùng = 24 lon); bán theo công thức tự trừ.")
                }

                Section {
                    Toggle("Ngưng sử dụng", isOn: $ngungSuDung)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm nguyên liệu" : "Sửa nguyên liệu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "Đang lưu..." : "Lưu")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)
                .disabled(ten.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
            .task { dsBanHang = await APIClient.shared.getNguyenLieuBanHangOrNil() ?? [] }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil

        let body = NguyenLieuUpdateRequest(
            ten: ten.trimmingCharacters(in: .whitespaces),
            donViTinh: donViTinh.trimmingCharacters(in: .whitespaces).isEmpty ? nil : donViTinh,
            giaNhap: giaNhap,
            ngungSuDung: ngungSuDung,
            thuTu: existing?.thuTu ?? 0,
            // Chưa tải xong danh sách NL bán hàng thì giữ nguyên liên kết cũ (Picker chưa có lựa chọn).
            nguyenLieuBanHangId: dsBanHang.isEmpty ? existing?.nguyenLieuBanHangId : nguyenLieuBanHangId,
            heSoQuyDoiBanHang: dsBanHang.isEmpty ? existing?.heSoQuyDoiBanHang
                : (nguyenLieuBanHangId == nil ? nil : (heSoQuyDoi ?? 1)),
            phanLoai: phanLoai
        )

        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateNguyenLieu(id: existing.id, body)
        } else {
            result = await APIClient.shared.createNguyenLieuFull(body)
        }

        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}
