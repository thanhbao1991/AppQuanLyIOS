import SwiftUI
import UIKit

/// Ô tìm kiếm client-side dùng chung cho mọi tab danh sách — khớp hành vi search trên
/// TraSuaApp.Mobile (web mobile cũ): lọc theo tên khách/ghi chú/tên món ngay trên dữ liệu đã tải,
/// không gọi API riêng.
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Tìm..."
    /// Tô nền gradient brandPrimary tràn lên status bar, khớp DaySearchBar(tinted:) — xem lý do ở đó.
    var tinted: Bool = false

    var body: some View {
        SearchFieldRow(text: $text, placeholder: placeholder)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(
                Group {
                    if tinted {
                        LinearGradient(colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                    }
                }
            )
    }
}

/// Phần lõi ô tìm kiếm (không padding ngoài) — dùng riêng khi cần đặt chung dòng với nút chọn
/// ngày (xem DaySearchBar trong DateNav.swift).
struct SearchFieldRow: View {
    @Binding var text: String
    var placeholder: String = "Tìm..."
    // Focus border xanh brandPrimary khớp ô nhập ở LoginView — dùng chung component này ở hầu hết
    // các tab (Hoá đơn/Thanh toán/Công nợ/Chi tiêu...) nên đổi 1 chỗ là đồng bộ style toàn app.
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(isFocused ? .brandPrimary : .textMuted)
                .font(.system(size: 14))
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isFocused ? Color.brandPrimary : Color(.separator).opacity(0.4), lineWidth: isFocused ? 1.5 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

extension String {
    /// So khớp không phân biệt hoa/thường, bỏ qua nil/rỗng — dùng cho mọi bộ lọc search client-side.
    /// Mặc định KHÔNG phân biệt dấu tiếng Việt (gõ "ca phe" vẫn khớp "Cà Phê") — trừ tab Công nợ
    /// (truyền diacriticInsensitive: false), nơi cần gõ ĐÚNG dấu để tránh khớp nhầm 2 khách tên gần
    /// giống nhau (nợ là tiền thật, không muốn thu/gửi bill nhầm người).
    func matchesSearch(_ query: String, diacriticInsensitive: Bool = true) -> Bool {
        guard !query.isEmpty else { return true }
        var options: String.CompareOptions = [.caseInsensitive]
        if diacriticInsensitive { options.insert(.diacriticInsensitive) }
        return range(of: query, options: options) != nil
    }
}

func anyMatchesSearch(_ query: String, diacriticInsensitive: Bool = true, _ fields: String?...) -> Bool {
    guard !query.isEmpty else { return true }
    return fields.contains { $0?.matchesSearch(query, diacriticInsensitive: diacriticInsensitive) == true }
}
