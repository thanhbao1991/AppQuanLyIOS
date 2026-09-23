import PhotosUI
import SwiftUI

/// Màn "Ảnh menu" — cho nhân viên đổi/thêm ảnh món ăn cho AppDatHangIOS (app khách đặt hàng), vì
/// menu chỉ tự khớp sẵn 92/233 món (tên trùng với ảnh có sẵn ở AppShippingBackend lúc seed), phần
/// còn lại + món đổi ảnh về sau phải cập nhật tay qua đây. Vào từ tab Menu > "Ảnh menu".
struct SanPhamHinhAnhListView: View {
    @State private var sanPhams: [SanPhamDto] = []
    @State private var loading = true
    @State private var query = ""
    @State private var uploadingId: String?
    @State private var errorMessage: String?

    private var filtered: [SanPhamDto] {
        sanPhams
            .filter { $0.ten.matchesSearch(query) }
            .sorted { $0.ten < $1.ten }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $query, placeholder: "Tìm món...")

            if loading {
                fullScreenLoading()
            } else {
                List {
                    ForEach(filtered) { sp in
                        SanPhamHinhAnhRow(
                            sanPham: sp,
                            uploading: uploadingId == sp.id,
                            onPicked: { data, mime in Task { await upload(id: sp.id, data: data, mime: mime) } }
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
        .alert("Đổi ảnh thất bại", isPresented: Binding(
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
                    thuTu: old.thuTu, bienThe: old.bienThe, timKiem: old.timKiem, hinhAnh: bustedUrl)
            }
        } else {
            errorMessage = message ?? "Không cập nhật được ảnh."
        }
    }
}

private struct SanPhamHinhAnhRow: View {
    let sanPham: SanPhamDto
    let uploading: Bool
    let onPicked: (Data, String) -> Void

    @State private var showPicker = false
    @State private var showCamera = false
    @State private var showFullImage = false

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            Text(sanPham.ten)
                .font(.subheadline)
            Spacer()
            if uploading {
                ProgressView().frame(width: 28, height: 28)
            } else {
                // .borderless để 2 nút trong cùng dòng List nhận tap riêng, không bị gộp cả dòng.
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
        .fullScreenCover(isPresented: $showFullImage) {
            if let hinhAnh = sanPham.hinhAnh, let url = URL(string: hinhAnh) {
                FullSizeImageView(url: url) { showFullImage = false }
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

/// Xem ảnh món size gốc, nền đen toàn màn hình — pinch để zoom, kéo khi đã zoom, tap để đóng.
private struct FullSizeImageView: View {
    let url: URL
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1, min(lastScale * value, 5))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale == 1 { offset = .zero; lastOffset = .zero }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard scale > 1 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                                }
                                .onEnded { _ in lastOffset = offset }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = scale > 1 ? 1 : 2.5
                                lastScale = scale
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                case .failure:
                    Text("Không tải được ảnh").foregroundColor(.white)
                default:
                    ProgressView().tint(.white)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onTapGesture {
            if scale == 1 { onClose() }
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
