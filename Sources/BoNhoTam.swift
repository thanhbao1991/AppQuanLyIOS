import Foundation

/// Bộ nhớ tạm (chỉ RAM, mất khi tắt app) cho các tab chính — 09/11/2026: MainTabView dựng lại view mỗi lần chuyển tab
/// → trước đây tab nào cũng xoá trắng + vòng xoay rồi mới tải. Giờ quay lại tab CÙNG NGÀY thì hiện ngay số liệu lần
/// trước, load() vẫn tải lại ngay rồi thay vào. Khoá kèm ngày đang xem → không bao giờ hiện số của ngày khác.
/// Xoá cùng Prefs.clear() (đăng xuất).
enum BoNhoTam {
    private static var kho: [String: Any] = [:]

    static func lay<T>(_ khoa: String) -> T? { kho[khoa] as? T }
    static func luu(_ khoa: String, _ giaTri: Any) { kho[khoa] = giaTri }
    static func xoa() { kho.removeAll() }
}
