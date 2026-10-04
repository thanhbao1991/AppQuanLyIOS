import SwiftUI

extension View {
    /// Gắn .alert()/.confirmationDialog() lên 1 view nền riêng có tint .brandPrimary: SwiftUI lấy màu
    /// chữ nút popup từ tint trong environment TẠI NƠI GẮN modifier (tint đặt trên view bên trong, hay
    /// trên Button trong popup, không có tác dụng). Dùng cách này thay vì .tint() bọc ngoài cả màn để
    /// không đụng màu chevron/nút trên thanh nav bar.
    func popupHost<P: View>(@ViewBuilder _ attach: (Color) -> P) -> some View {
        background(attach(Color.clear).tint(.brandPrimary))
    }
}
