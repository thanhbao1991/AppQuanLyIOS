import PhotosUI
import SwiftUI

/// Chọn ảnh món từ thư viện bằng PhotosPicker chuẩn của iOS (mở vào "Gần đây" như mặc định hệ thống).
/// Trước đây tự vẽ lưới album "Yêu thích" — đã bỏ theo yêu cầu 15/11/2026, dùng mặc định của iOS.
/// Ảnh được cắt 3:4 + nén JPEG giống đường chụp camera trước khi trả về; ảnh quá nhỏ (ảnh chụp màn hình, ảnh gửi
/// qua Zalo...) bị TỪ CHỐI qua onLoi — xem UIImage.menuUploadJPEG.
extension View {
    func menuPhotoPicker(isPresented: Binding<Bool>, onPicked: @escaping (Data) -> Void,
                         onLoi: @escaping (String) -> Void) -> some View {
        modifier(MenuPhotoPickerModifier(isPresented: isPresented, onPicked: onPicked, onLoi: onLoi))
    }
}

private struct MenuPhotoPickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onPicked: (Data) -> Void
    let onLoi: (String) -> Void
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
                          let image = UIImage(data: raw) else { onLoi("Không đọc được ảnh."); return }
                    let kq = image.menuUploadJPEG()
                    if let data = kq.data { onPicked(data) } else { onLoi(kq.loi ?? "Ảnh không dùng được.") }
                }
            }
    }
}
