import Photos
import PhotosUI
import SwiftUI

/// Grid ảnh mở thẳng vào album "Yêu thích" — PhotosPicker/PHPickerViewController chuẩn của iOS
/// không có API công khai để mặc định vào Favorites (luôn mở "Recents" đầu tiên), nên tự fetch
/// smart album Favorites qua PhotoKit và tự vẽ lưới ảnh. Có nút "Thư viện khác" dùng PhotosPicker
/// chuẩn cho trường hợp ảnh cần không nằm trong Yêu thích.
struct FavoritesImagePicker: View {
    let onPicked: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var loading = true
    @State private var authDenied = false
    @State private var picking = false
    @State private var fallbackItem: PhotosPickerItem?

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 4)]

    var body: some View {
        NavigationView {
            Group {
                if authDenied {
                    VStack(spacing: 12) {
                        Text("Chưa cấp quyền truy cập ảnh").foregroundColor(.textMuted)
                        Button("Mở Cài đặt") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } else if loading {
                    ProgressView()
                } else if assets.isEmpty {
                    Text("Album Yêu thích chưa có ảnh nào").foregroundColor(.textMuted)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                AssetThumbnailView(asset: asset)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .opacity(picking ? 0.4 : 1)
                                    .onTapGesture { pick(asset) }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .overlay {
                if picking { ProgressView() }
            }
            .navigationTitle("Album Yêu thích")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $fallbackItem, matching: .images) {
                        Text("Thư viện khác")
                    }
                    .disabled(picking)
                }
            }
        }
        .task { await load() }
        .onChange(of: fallbackItem) { item in
            guard let item else { return }
            Task {
                defer { fallbackItem = nil }
                guard let raw = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: raw),
                      let data = image.resizedForMenuUpload().jpegData(compressionQuality: 0.75) else { return }
                onPicked(data)
            }
        }
    }

    private func load() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let granted: Bool
        switch status {
        case .authorized, .limited:
            granted = true
        case .notDetermined:
            granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite) == .authorized
        default:
            granted = false
        }
        guard granted else {
            authDenied = true
            loading = false
            return
        }

        let collections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil)
        guard let favorites = collections.firstObject else {
            loading = false
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(in: favorites, options: options)
        var fetched: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in fetched.append(asset) }
        assets = fetched
        loading = false
    }

    private func pick(_ asset: PHAsset) {
        guard !picking else { return }
        picking = true
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let targetSize = CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        PHImageManager.default().requestImage(
            for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options
        ) { image, _ in
            picking = false
            guard let image, let data = image.resizedForMenuUpload().jpegData(compressionQuality: 0.75) else { return }
            onPicked(data)
        }
    }
}

private struct AssetThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.textMuted.opacity(0.12))
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            }
            .task {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.resizeMode = .fast
                PHImageManager.default().requestImage(
                    for: asset, targetSize: CGSize(width: 180, height: 180), contentMode: .aspectFill, options: options
                ) { result, _ in
                    if let result { image = result }
                }
            }
    }
}
