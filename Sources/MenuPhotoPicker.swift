import PhotosUI
import SwiftUI

/// Chọn ảnh món từ thư viện bằng PhotosPicker chuẩn của iOS (mở vào "Gần đây" như mặc định hệ thống).
/// Trước đây tự vẽ lưới album "Yêu thích" — đã bỏ theo yêu cầu 15/11/2026, dùng mặc định của iOS.
/// Ảnh được thu nhỏ + nén JPEG giống đường chụp camera trước khi trả về.
extension View {
    func menuPhotoPicker(isPresented: Binding<Bool>, onPicked: @escaping (Data) -> Void) -> some View {
        modifier(MenuPhotoPickerModifier(isPresented: isPresented, onPicked: onPicked))
    }
}

private struct MenuPhotoPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPicked: (Data) -> Void
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images,
                          preferredItemEncoding: .compatible)
            .onChange(of: item) { newItem in
                guard let newItem else { return }
                Task {
                    defer { item = nil }
                    guard let raw = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: raw),
                          let data = image.resizedForMenuUpload().jpegData(compressionQuality: 0.75) else { return }
                    onPicked(data)
                }
            }
    }
}
