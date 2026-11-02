import SwiftUI

/// Icon SF Symbol + chữ, icon tô màu thương hiệu — thay EmojiLabel (emoji) từ 02/11/2026. Icon khung
/// rộng cố định để các dòng trong cùng 1 List thẳng hàng.
struct IconLabel: View {
    let title: String
    let icon: String

    init(_ title: String, _ icon: String) {
        self.title = title
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.brandPrimary).frame(width: 24)
            Text(title)
        }
    }
}
