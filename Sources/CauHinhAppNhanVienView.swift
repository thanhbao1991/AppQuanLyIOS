import SwiftUI

/// Chọn loại đơn nào báo sang AppNhanVienIOS ("Chi Tiêu" của nhân viên) — áp cho MỌI máy nhân viên, cả
/// push lẫn chuông xem lại. AppQuanLy (app này) không bị ảnh hưởng, vẫn nhận đủ. Bật/tắt là lưu luôn.
/// GET/PUT api/cau-hinh/thong-bao-nhan-vien.
struct CauHinhAppNhanVienView: View {
    @State private var config: CauHinhThongBaoNhanVienDto?
    @State private var hasLoaded = false
    @State private var saving = false
    @State private var errorMessage: String?

    /// Khớp CauHinhThongBaoNhanVienDto.TatCaPhanLoai bên Backend (thứ tự hiện).
    private static let phanLoai: [(khoa: String, ten: String, emoji: String)] = [
        ("Ship", "Ship", "🛵"),
        ("AppDatHang", "App Đenn", "🛒"),
        ("App", "Đơn App", "📱"),
        ("Mh", "Mua hộ", "✋"),
        ("Mv", "Mua về", "🛍️"),
        ("TaiCho", "Tại chỗ", "🪑"),
        ("Khac", "Khác", "➕"),
    ]

    var body: some View {
        Group {
            if !hasLoaded {
                fullScreenLoading()
            } else if config != nil {
                form
            } else {
                VStack(spacing: 12) {
                    Text("Không tải được cấu hình").font(.headline)
                    Button("Thử lại") {
                        Task {
                            hasLoaded = false
                            await load()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Cấu hình App nhân viên")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if saving {
                ToolbarItem(placement: .navigationBarTrailing) { ProgressView().tint(.white) }
            }
        }
        .task { await load() }
    }

    private var form: some View {
        Form {
            Section {
                ForEach(Self.phanLoai, id: \.khoa) { item in
                    Toggle(isOn: phanLoaiBinding(item.khoa)) {
                        Text("\(item.emoji)  \(item.ten)")
                    }
                }
            } header: {
                Text("Loại đơn")
            } footer: {
                Text("Tắt loại nào thì máy nhân viên không nhận push và không thấy trong chuông — kể cả khi đơn loại đó bị sửa hay xoá.")
            }

            Section {
                Toggle("➕  Đơn mới", isOn: boolBinding(\.tao))
                Toggle("✏️  Sửa đơn", isOn: boolBinding(\.sua))
                Toggle("🗑️  Xoá đơn", isOn: boolBinding(\.xoa))
            } header: {
                Text("Báo khi")
            } footer: {
                Text("Áp cho mọi máy đang dùng App nhân viên. App quản lý (app này) vẫn nhận đủ mọi thông báo.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundColor(.red)
                }
            }
        }
        .tint(.brandPrimary)
    }

    private func phanLoaiBinding(_ khoa: String) -> Binding<Bool> {
        Binding(
            get: { config?.phanLoai.contains(khoa) ?? false },
            set: { bat in
                guard var cfg = config else { return }
                cfg.phanLoai.removeAll { $0 == khoa }
                if bat { cfg.phanLoai.append(khoa) }
                apply(cfg)
            }
        )
    }

    private func boolBinding(_ path: WritableKeyPath<CauHinhThongBaoNhanVienDto, Bool>) -> Binding<Bool> {
        Binding(
            get: { config?[keyPath: path] ?? false },
            set: { value in
                guard var cfg = config else { return }
                cfg[keyPath: path] = value
                apply(cfg)
            }
        )
    }

    /// Đổi ngay trên màn rồi lưu; lưu lỗi thì trả lại trạng thái cũ để màn không nói dối.
    private func apply(_ moi: CauHinhThongBaoNhanVienDto) {
        let cu = config
        config = moi
        Task {
            saving = true
            errorMessage = nil
            let result = await APIClient.shared.saveCauHinhThongBaoNhanVien(moi)
            saving = false
            if !result.success {
                config = cu
                errorMessage = result.message ?? "Không lưu được, thử lại."
            }
        }
    }

    private func load() async {
        config = await APIClient.shared.getCauHinhThongBaoNhanVien()
        hasLoaded = true
    }
}
