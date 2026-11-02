import SwiftUI

/// Bộ icon dùng chung cả app — SF Symbols thay emoji (02/11/2026): 1 phong cách, tô màu được, nút
/// disabled tự xám. Đổi icon 1 loại đơn/thanh toán thì đổi ở đây, mọi màn ăn theo.
enum AppIcon {
    // Phân loại đơn
    static let ship = "scooter"
    static let taiCho = "cup.and.saucer.fill"
    static let muaVe = "bag.fill"
    static let muaHo = "hand.raised.fill"
    static let app = "iphone"
    static let appDatHang = "cart.fill"

    // Thanh toán
    static let tienMat = "banknote.fill"
    static let chuyenKhoan = "creditcard.fill"
    static let viXu = "star.circle.fill"
    static let tuDong = "bolt.fill"

    // Thao tác
    static let them = "plus"
    static let sua = "pencil"
    static let xoa = "trash"
    static let ghiNo = "exclamationmark.triangle.fill"
    static let doiPhuongThuc = "arrow.triangle.2.circlepath"
    static let bill = "doc.text.image"
    static let link = "link"
    static let daCopy = "checkmark"

    /// Theo mã PhanLoai trên HoaDon ("Ship", "Tại Chỗ", "Mv", "Mh", "App", "AppDatHang"); lạ → Ship.
    static func phanLoai(_ phanLoai: String?) -> String {
        switch phanLoai {
        case "Tại Chỗ", "TaiCho": return taiCho
        case "Mv": return muaVe
        case "Mh": return muaHo
        case "App": return app
        case "AppDatHang": return appDatHang
        case "Khac": return them
        default: return ship
        }
    }
}

/// Icon trắng trên nền tròn đặc màu — đầu thẻ đơn/thông báo/thanh toán (thay emoji 20pt trước đây).
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color))
    }
}
