import SwiftUI

/// Màn "Ảnh menu" — ảnh món cho app khách + chọn món "Nổi bật". Vào từ tab Menu > "Ảnh menu".
/// 20/11/2026 chủ quán: KHÔNG chụp/chọn ảnh từ thư viện nữa (ảnh menu phải là ảnh đã tách nền do quán làm) —
/// chỉ cho món dùng chung ảnh của món khác (POST /api/SanPham/{id}/dung-anh-cua/{nguonId}).
struct SanPhamHinhAnhListView: View {
    @State private var sanPhams: [SanPhamDto] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var query = ""
    @State private var dangDoiId: String?
    @State private var togglingNoiBatId: String?
    @State private var errorMessage: String?
    @State private var monCanAnh: SanPhamDto?

    private var filtered: [SanPhamDto] {
        sanPhams
            .filter { $0.ten.matchesSearch(query) }
            .sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $query, placeholder: "Tìm món...")

            if loading {
                fullScreenLoading()
            } else {
                if loadFailed {
                    ThongKeLoadErrorBanner(text: "Chưa tải được danh sách món") { Task { await load() } }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                List {
                    ForEach(filtered) { sp in
                        SanPhamHinhAnhRow(
                            sanPham: sp,
                            dangDoi: dangDoiId == sp.id,
                            togglingNoiBat: togglingNoiBatId == sp.id,
                            onChonMonKhac: { monCanAnh = sp },
                            onToggleNoiBat: { Task { await toggleNoiBat(sp) } }
                        )
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.appNen)
                .softScrollEdgeTop()
                .padding(.top, 4)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Ảnh menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .sheet(item: $monCanAnh) { dich in
            ChonAnhMonKhacSheet(dich: dich, sanPhams: sanPhams) { nguon in
                monCanAnh = nil
                Task { await dungAnh(dich: dich, nguon: nguon) }
            }
        }
        .popupHost { host in
            host.alert("Lỗi", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func load() async {
        let fresh = await APIClient.shared.getSanPhamListOrNil()
        if let fresh { sanPhams = fresh }
        loadFailed = fresh == nil
        loading = false
    }

    private func dungAnh(dich: SanPhamDto, nguon: SanPhamDto) async {
        dangDoiId = dich.id
        defer { dangDoiId = nil }
        let kq = await APIClient.shared.dungAnhCuaMonKhac(id: dich.id, nguonId: nguon.id)
        if kq.success {
            await load()   // server trả URL mới (?v=) + ảnh nhỏ/gốc — tải lại cho đúng
        } else {
            errorMessage = kq.message ?? "Không đổi được ảnh."
        }
    }

    private func toggleNoiBat(_ sp: SanPhamDto) async {
        guard let idx = sanPhams.firstIndex(where: { $0.id == sp.id }) else { return }
        togglingNoiBatId = sp.id
        defer { togglingNoiBatId = nil }
        let newValue = !sp.noiBat
        let result = await APIClient.shared.setSanPhamNoiBat(id: sp.id, value: newValue)
        if result.success {
            let old = sanPhams[idx]
            sanPhams[idx] = SanPhamDto(
                id: old.id, ten: old.ten, ngungBan: old.ngungBan, tenNhomSanPham: old.tenNhomSanPham,
                thuTu: old.thuTu, bienThe: old.bienThe, timKiem: old.timKiem, hinhAnh: old.hinhAnh,
                noiBat: newValue, hinhAnhNho: old.hinhAnhNho, hinhAnhGoc: old.hinhAnhGoc)
        } else {
            errorMessage = result.message ?? "Không cập nhật được."
        }
    }
}

private struct SanPhamHinhAnhRow: View {
    let sanPham: SanPhamDto
    let dangDoi: Bool
    let togglingNoiBat: Bool
    let onChonMonKhac: () -> Void
    let onToggleNoiBat: () -> Void

    @State private var showFullImage = false

    var body: some View {
        HStack(spacing: 12) {
            // ⭐ bên trái ảnh/tên — đồng bộ với màn Tồn kho và Giá nguyên liệu.
            if togglingNoiBat {
                ProgressView().frame(width: 28, height: 28)
            } else {
                Button(action: onToggleNoiBat) {
                    Image(systemName: sanPham.noiBat ? "star.fill" : "star")
                        .foregroundColor(sanPham.noiBat ? .yellow : .textMuted)
                }
                .buttonStyle(.borderless)
            }
            AnhMonThumb(sanPham: sanPham) { showFullImage = true }
            Text(sanPham.ten)
                .font(.subheadline)
            Spacer()
            if dangDoi {
                ProgressView().frame(width: 36, height: 36)
            } else {
                // .borderless để nhiều nút trong cùng dòng List nhận tap riêng, không bị gộp cả dòng.
                Button(action: onChonMonKhac) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dùng ảnh của món khác")
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showFullImage) {
            if let hinhAnh = sanPham.anhLon, let url = URL(string: hinhAnh) {
                FullSizeImageView(url: url) { showFullImage = false }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

/// Ảnh nhỏ 48x48 của món (bấm để xem to nếu có `onTap`); chưa có ảnh thì hiện chữ cái đầu.
private struct AnhMonThumb: View {
    let sanPham: SanPhamDto
    var onTap: (() -> Void)?

    var body: some View {
        if let hinhAnh = sanPham.anhNho, let url = URL(string: hinhAnh) {
            let anh = AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.textMuted.opacity(0.12)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if let onTap {
                Button(action: onTap) { anh }.buttonStyle(.borderless)
            } else {
                anh
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.textMuted.opacity(0.12))
                .frame(width: 48, height: 48)
                .overlay(
                    Text(sanPham.ten.trimmingCharacters(in: .whitespaces).prefix(1).uppercased())
                        .font(.headline)
                        .foregroundColor(.brandPrimary)
                )
        }
    }
}

/// Chọn món nguồn để món `dich` dùng chung ảnh — chỉ liệt kê món đã có ảnh, bấm 1 món thì hỏi lại trước khi đổi.
private struct ChonAnhMonKhacSheet: View {
    let dich: SanPhamDto
    let sanPhams: [SanPhamDto]
    let onChon: (SanPhamDto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var monXacNhan: SanPhamDto?

    private var dsCoAnh: [SanPhamDto] {
        sanPhams
            .filter { $0.id != dich.id && $0.anhNho != nil && $0.ten.matchesSearch(query) }
            .sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $query, placeholder: "Tìm món có ảnh...")
                List {
                    Section {
                        ForEach(dsCoAnh) { sp in
                            Button {
                                monXacNhan = sp
                            } label: {
                                HStack(spacing: 12) {
                                    AnhMonThumb(sanPham: sp)
                                    Text(sp.ten)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                            }
                        }
                    } header: {
                        Text("Chọn món để \"\(dich.ten)\" dùng chung ảnh")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.appNen)
            }
            .navigationTitle("Ảnh từ món khác")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .popupHost { host in
                host.confirmationDialog(
                    "Dùng ảnh của \"\(monXacNhan?.ten ?? "")\" cho \"\(dich.ten)\"?",
                    isPresented: Binding(get: { monXacNhan != nil }, set: { if !$0 { monXacNhan = nil } }),
                    titleVisibility: .visible
                ) {
                    Button("Dùng ảnh này") {
                        if let sp = monXacNhan { onChon(sp) }
                    }
                    Button("Huỷ", role: .cancel) {}
                }
            }
        }
    }
}


/// Xem ảnh món đúng kích thước gốc (không co giãn theo màn hình) — sheet medium/large giống
/// "Thêm hoá đơn", vuốt xuống để đóng như sheet thường (không cần gesture tự chế). Pinch để zoom
/// thêm khi cần xem chi tiết, double-tap để zoom nhanh.
private struct FullSizeImageView: View {
    let url: URL
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .scaleEffect(scale)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1, min(lastScale * value, 5))
                                    }
                                    .onEnded { _ in lastScale = scale }
                            )
                            .onTapGesture(count: 2) {
                                withAnimation {
                                    scale = scale > 1 ? 1 : 2.5
                                    lastScale = scale
                                }
                            }
                    case .failure:
                        Text("Không tải được ảnh").foregroundColor(.textMuted)
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
            .background(Color.black)
            .navigationTitle("Ảnh món")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { onClose() }
                }
            }
        }
    }
}

extension UIImage {
    /// Center-crop về tỉ lệ 3:4 rồi resize đúng 200x267 — khớp hệt kích thước 92 ảnh seed ban đầu
    /// (từ AppShippingBackend). Cả 2 nơi hiển thị (ô 48x48, 64x64) đều crop-fit sẵn nên không cần
    /// độ phân giải cao hơn — giữ file nhẹ như ảnh seed thay vì để nguyên full-res từ camera.
    func resizedForMenuUpload() -> UIImage {
        // 14/11/2026: nâng 200x267 -> 1080x1440. Ảnh seed cũ quá bé; app khách giờ hiện ảnh to +
        // cần ảnh gốc nét để đổ nền. Server không nén lại nên giữ nguyên bản này (~200-350KB/ảnh).
        // Dùng cho cả chọn tay lẫn "Tự dò ảnh món" (TuDoAnhMonView).
        let targetSize = CGSize(width: 1080, height: 1440)
        let targetRatio = targetSize.width / targetSize.height
        let sourceRatio = size.width / size.height

        var drawSize = targetSize
        if sourceRatio > targetRatio {
            drawSize.width = targetSize.height * sourceRatio
        } else {
            drawSize.height = targetSize.width / sourceRatio
        }
        let origin = CGPoint(x: (targetSize.width - drawSize.width) / 2, y: (targetSize.height - drawSize.height) / 2)

        // scale = 1: ra ĐÚNG 1080×1440 PIXEL. Mặc định renderer lấy scale màn hình (3x) → trước đây ra 3240×4320
        // (phóng to ảnh) và 42 món cũ (khung 200×267) ra 600×801 px — đó là lý do ảnh trên server có cỡ lạ đó.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: origin, size: drawSize)) }
    }

    /// Ảnh món để up — CHỈ nhận ảnh đủ nét: phần cắt 3:4 phải ≥1080×1440 PIXEL (cùng ngưỡng server
    /// SanPhamCrudService.AnhMenuCanhNganToiThieu), KHÔNG phóng to ảnh nhỏ cho "đủ cỡ". 16/11/2026 chủ quán:
    /// không nhận ảnh chất lượng thấp nữa. Dùng cho MỌI chỗ up ảnh menu (chọn, chụp, Tự dò, Tìm ảnh gốc, hoá đơn).
    func menuUploadJPEG() -> (data: Data?, loi: String?) {
        let w = size.width * scale, h = size.height * scale
        let rongCat = min(w, h * 3 / 4)   // bề ngang phần 3:4 được giữ lại
        if rongCat < 1079.5 {
            return (nil, "Ảnh quá nhỏ (\(Int(w))×\(Int(h))). Cần ảnh chụp gốc từ điện thoại, tối thiểu 1080×1440 — "
                + "không dùng ảnh chụp màn hình hay ảnh gửi qua Zalo/Messenger.")
        }
        guard let data = resizedForMenuUpload().jpegData(compressionQuality: 0.9) else { return (nil, "Không nén được ảnh.") }
        return (data, nil)
    }
}
