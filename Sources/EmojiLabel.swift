import SwiftUI

/// Thay cho `Label(_:systemImage:)` — icon là emoji thay vì SF Symbol (đổi 2026-09-13, đồng bộ
/// phong cách emoji đã dùng cho ActionButtonView/tab bar). Layout giống Label mặc định: icon + chữ
/// cạnh nhau, icon có width cố định để các dòng trong cùng 1 List thẳng hàng dù emoji rộng hẹp khác
/// nhau (SF Symbol tự căn giữa theo font, emoji thì không).
struct EmojiLabel: View {
    let title: String
    let icon: String

    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(icon).font(.system(size: 17)).frame(width: 24)
            Text(title)
        }
    }
}
