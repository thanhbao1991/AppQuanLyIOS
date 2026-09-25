import PhotosUI
import SwiftUI

/// Màn "Ảnh menu" — cho nhân viên đổi/thêm ảnh món ăn cho AppDatHangIOS (app khách đặt hàng), vì
/// menu chỉ tự khớp sẵn 92/233 món (tên trùng với ảnh có sẵn ở AppShippingBackend lúc seed), phần
/// còn lại + món đổi ảnh về sau phải cập nhật tay qua đây. Vào từ tab Menu > "Ảnh menu". Cũng là nơi
/// chọn món "Nổi bật" (dải quảng bá đầu tab Thực đơn app khách, tối đa 5 món) — cùng chỗ với ảnh vì
/// cả 2 đều là "cấu hình món hiện thế nào cho app khách", không tách màn riêng.
struct SanPhamHinhAnhListView: View {
    private static let noiBatToiDa = 5

    @State private var sanPhams: [SanPhamDto] = []
    @State private var loading = true
    @State private var query = ""
    @State private var uploadingId: String?
    @State private var togglingNoiBatId: String?
    @State private var errorMessage: String?

    private var filtered: [SanPhamDto] {
        sanPhams
            .filter { $0.ten.matchesSearch(query) }
            .sorted { $0.ten < $1.ten }
    }

    private var soLuongNoiBat: Int { sanPhams.filter(\.noiBat).count }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $query, placeholder: "Tìm món...")

            if loading {
                fullScreenLoading()
            } else {
                HStack {
                    Text("⭐ Nổi bật: \(soLuongNoiBat)/\(Self.noiBatToiDa)")
                        .font(.caption).foregroundColor(.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.top, 6)

                List {
                    ForEach(filtered) { sp in
                        SanPhamHinhAnhRow(
                            sanPham: sp,
                            uploading: uploadingId == sp.id,
                            togglingNoiBat: togglingNoiBatId == sp.id,
                            noiBatDangDay: !sp.noiBat && soLuongNoiBat >= Self.noiBatToiDa,
                            onPicked: { data, mime in Task { await upload(id: sp.id, data: data, mime: mime) } },
                            onToggleNoiBat: { Task { await toggleNoiBat(sp) } }
                        )
                    }
                }
                .listStyle(.plain)
                .padding(.top, 4)
            }
        }
        .navigationTitle("Ảnh menu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .alert("Lỗi", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() async {
        loading = true
        sanPhams = await APIClient.shared.getSanPhamList()
        loading = false
    }

    private func upload(id: String, data: Data, mime: String) async {
        uploadingId = id
        defer { uploadingId = nil }
        let (url, message) = await APIClient.shared.uploadSanPhamHinhAnh(id: id, imageData: data, mimeType: mime)
        if let url {
            if let idx = sanPhams.firstIndex(where: { $0.id == id }) {
                let old = sanPhams[idx]
                // Backend giữ nguyên tên file (id.ext) mỗi lần đổi ảnh nên URL không đổi —
                // gắn query cache-bust để AsyncImage tải lại ngay, không phải thoát vào lại màn hình.
                let bustedUrl = url + "?v=\(Int(Date().timeIntervalSince1970))"
                sanPhams[idx] = SanPhamDto(
                    id: old.id, ten: old.ten, ngungBan: old.ngungBan, tenNhomSanPham: old.tenNhomSanPham,
                    thuTu: old.thuTu, bienThe: old.bienThe, timKiem: old.timKiem, hinhAnh: bustedUrl,
                    noiBat: old.noiBat)
            }
        } else {
            errorMessage = message ?? "Không cập nhật được ảnh."
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
                noiBat: newValue)
        } else {
            errorMessage = result.message ?? "Không cập nhật được."
        }
    }
}

private struct SanPhamHinhAnhRow: View {
    let sanPham: SanPhamDto
    let uploading: Bool
    let togglingNoiBat: Bool
    /// true khi đã đủ 5 món nổi bật VÀ món này chưa nổi bật — disable nút star để khỏi bấm hụt rồi
    /// mới thấy alert lỗi, số đếm ở header đã cho biết đang đầy.
    let noiBatDangDay: Bool
    let onPicked: (Data, String) -> Void
    let onToggleNoiBat: () -> Void

    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showFullImage = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            Text(sanPham.ten)
                .font(.subheadline)
            Spacer()
            if togglingNoiBat {
                ProgressView().frame(width: 28, height: 28)
            } else {
                Button(action: onToggleNoiBat) {
                    Image(systemName: sanPham.noiBat ? "star.fill" : "star")
                        .font(.system(size: 18))
                        .foregroundColor(sanPham.noiBat ? .yellow : .textMuted.opacity(0.5))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .disabled(noiBatDangDay)
            }
            if uploading {
                ProgressView().frame(width: 28, height: 28)
            } else {
                // .borderless để nhiều nút trong cùng dòng List nhận tap riêng, không bị gộp cả dòng.
                Button {
                    showPicker = true
                } label: {
                    Text("🖼️")
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
                Button {
                    showCamera = true
                } label: {
                    Text("📷")
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
        // Mở thẳng vào album Yêu thích — xem FavoritesImagePicker để biết lý do không dùng
        // PhotosPicker mặc định (Apple không cho chọn album ban đầu, luôn mở Recents).
        .sheet(isPresented: $showPicker) {
            FavoritesImagePicker { data in
                showPicker = false
                onPicked(data, "image/jpeg")
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                guard let image, let data = image.resizedForMenuUpload().jpegData(compressionQuality: 0.75) else { return }
                onPicked(data, "image/jpeg")
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showFullImage) {
            if let hinhAnh = sanPham.hinhAnh, let url = URL(string: hinhAnh) {
                FullSizeImageView(url: url) { showFullImage = false }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let hinhAnh = sanPham.hinhAnh, let url = URL(string: hinhAnh) {
            Button {
                showFullImage = true
            } label: {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.textMuted.opacity(0.12)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.borderless)
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
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
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
        let targetSize = CGSize(width: 200, height: 267)
        let targetRatio = targetSize.width / targetSize.height
        let sourceRatio = size.width / size.height

        var drawSize = targetSize
        if sourceRatio > targetRatio {
            drawSize.width = targetSize.height * sourceRatio
        } else {
            drawSize.height = targetSize.width / sourceRatio
        }
        let origin = CGPoint(x: (targetSize.width - drawSize.width) / 2, y: (targetSize.height - drawSize.height) / 2)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in draw(in: CGRect(origin: origin, size: drawSize)) }
    }
}
