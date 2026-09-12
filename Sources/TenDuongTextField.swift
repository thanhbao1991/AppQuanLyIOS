import SwiftUI

/// Cache tên đường dùng chung toàn app — tải 1 lần, mọi TenDuongTextField dùng lại thay vì mỗi ô tự
/// gọi API riêng. Khớp cách Desktop cache AppDataCache.TenDuongs cho TenDuongBox.
@MainActor
final class TenDuongCache: ObservableObject {
    static let shared = TenDuongCache()

    @Published private(set) var items: [TenDuongDto] = []
    private var loadTask: Task<Void, Never>?

    func ensureLoaded() {
        guard items.isEmpty, loadTask == nil else { return }
        loadTask = Task {
            items = await APIClient.shared.getTenDuongList()
            loadTask = nil
        }
    }
}

/// TextField địa chỉ có gợi ý tên đường — khớp TenDuongBox bên TraSuaApp.Desktop: nhận diện số nhà
/// bằng regex, so khớp phần CÒN LẠI sau số nhà với danh sách TenDuong, chọn gợi ý giữ nguyên số nhà
/// đã gõ, chỉ thay phần tên đường. Bản port SwiftUI (Desktop dùng Popup/ListBox riêng của WPF, ở
/// đây dùng 1 danh sách gợi ý xổ ngay dưới ô nhập).
struct TenDuongTextField: View {
    @Binding var text: String
    var placeholder: String = "Địa chỉ"
    var keyboard: UIKeyboardType = .default

    @FocusState private var focused: Bool
    @ObservedObject private var cache = TenDuongCache.shared

    private static let houseNumberPrefixRegex = try! NSRegularExpression(pattern: "^\\d+[A-Za-z]{0,2}(/\\d+[A-Za-z]{0,2})?[\\s.,-]*")

    private static func houseNumberPrefixRange(in text: String) -> Range<String.Index>? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = houseNumberPrefixRegex.firstMatch(in: text, range: range) else { return nil }
        return Range(m.range, in: text)
    }

    private var streetFragment: String {
        guard let r = Self.houseNumberPrefixRange(in: text) else { return text }
        return String(text[r.upperBound...])
    }

    private var housePrefix: String {
        guard let r = Self.houseNumberPrefixRange(in: text) else { return "" }
        return String(text[..<r.upperBound])
    }

    private func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "vi_VN"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Chỉ hiện khi đang gõ (còn focus) VÀ fragment sau số nhà chưa khớp CHÍNH XÁC 1 tên đường có
    /// sẵn — tránh xổ dropdown thừa ngay sau khi vừa chọn gợi ý hoặc gõ đủ tên.
    private var suggestions: [String] {
        guard focused else { return [] }
        let fragment = streetFragment.trimmingCharacters(in: .whitespaces)
        guard !fragment.isEmpty else { return [] }
        let matches = cache.items.map(\.ten).filter { $0.matchesSearch(fragment) }
        if matches.count == 1 && normalized(matches[0]) == normalized(fragment) { return [] }
        return Array(matches.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .keyboardType(keyboard)
                .focused($focused)

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { ten in
                        Button {
                            text = housePrefix + ten
                        } label: {
                            Text(ten)
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        if ten != suggestions.last { Divider() }
                    }
                }
                .background(Color.brandPrimary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear { cache.ensureLoaded() }
    }
}
