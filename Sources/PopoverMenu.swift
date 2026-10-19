import SwiftUI

/// Thay cho `Menu` hệ thống ở MỌI chỗ trong app (đổi 2026-10-19). Lý do: trên iOS 26+ UIMenu tự giới
/// hạn chiều cao — menu lọc tab Đơn (12 mục) bị cắt mất dòng cuối dù màn hình còn trống; UIMenu cũng
/// bỏ qua mọi style (màu/đậm/view lồng nhau). Popover co theo nội dung, chỉ cuộn khi thật sự hết chỗ.
///
/// Dùng:
/// ```
/// PopoverMenu {
///     PopoverMenuItem("Hôm nay") { ... }
///     PopoverMenuDivider()
///     PopoverMenuItem("Xoá", role: .destructive) { ... }
/// } label: { Image(systemName: "ellipsis.circle") }
/// ```
/// Bấm 1 mục là đóng popover; action chạy SAU khi popover đóng hẳn, nên action mở sheet/alert/
/// DatePicker... không bị đụng "đang có presentation khác".
struct PopoverMenu<Content: View, MenuLabel: View>: View {
    var width: CGFloat = 270
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> MenuLabel

    @State private var isPresented = false
    @State private var pendingAction: (() -> Void)?

    var body: some View {
        Button(action: { isPresented = true }, label: label)
            .popover(isPresented: $isPresented, arrowEdge: .top) {
                PopoverMenuPanel(width: width, content: content)
                    .environment(\.popoverMenuSelect, PopoverMenuSelect { action in
                        pendingAction = action
                        isPresented = false
                    })
                    .onDisappear {
                        let action = pendingAction
                        pendingAction = nil
                        action?()
                    }
            }
    }
}

/// Mục trong `PopoverMenu`. `icon` (avatar/emoji/SF Symbol) nằm ô 28pt bên trái — mục không có icon
/// thì chữ sát lề. `isSelected` = dấu ✓ bên phải + nền nhạt; `isDimmed` = chữ xám (vd filter đếm 0).
struct PopoverMenuItem<Icon: View>: View {
    private let title: String
    private let isSelected: Bool
    private let isDimmed: Bool
    private let role: ButtonRole?
    private let icon: Icon?
    private let action: () -> Void

    @Environment(\.popoverMenuSelect) private var select

    init(_ title: String, isSelected: Bool = false, isDimmed: Bool = false, role: ButtonRole? = nil,
         action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        self.role = role
        self.icon = icon()
        self.action = action
    }

    var body: some View {
        Button(role: role) {
            select.run(action)
        } label: {
            HStack(spacing: 12) {
                if let icon {
                    icon.frame(width: 28, height: 28)
                }
                Text(title)
                    .font(.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.brandPrimary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, icon == nil ? 11 : 8)
            .background(isSelected ? Color.brandPrimary.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PopoverMenuRowStyle())
    }

    private var textColor: Color {
        if role == .destructive { return .red }
        return isDimmed ? .secondary : .primary
    }
}

extension PopoverMenuItem where Icon == EmptyView {
    init(_ title: String, isSelected: Bool = false, isDimmed: Bool = false, role: ButtonRole? = nil,
         action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.isDimmed = isDimmed
        self.role = role
        self.icon = nil
        self.action = action
    }
}

extension PopoverMenuItem where Icon == PopoverMenuSymbol {
    init(_ title: String, systemImage: String, isSelected: Bool = false, isDimmed: Bool = false,
         role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(title, isSelected: isSelected, isDimmed: isDimmed, role: role, action: action) {
            PopoverMenuSymbol(name: systemImage, isDestructive: role == .destructive)
        }
    }
}

/// Icon SF Symbol cho `PopoverMenuItem(_:systemImage:)`.
struct PopoverMenuSymbol: View {
    let name: String
    let isDestructive: Bool

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 18))
            .foregroundColor(isDestructive ? .red : .brandPrimary)
    }
}

/// Đường phân cách giữa các cụm mục trong `PopoverMenu`.
struct PopoverMenuDivider: View {
    var body: some View {
        Divider().padding(.vertical, 4)
    }
}

// MARK: - Nội bộ

private struct PopoverMenuPanel<Content: View>: View {
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        let rows = VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.vertical, 8)
            .frame(width: width)
        // Co theo chiều cao nội dung; chỉ khi không đủ chỗ mới chuyển sang cuộn (ScrollView luôn
        // chiếm hết chiều cao được cấp nên không dùng nó mặc định).
        let fitted = ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
        }
        if #available(iOS 16.4, *) {
            fitted.presentationCompactAdaptation(.popover)
        } else {
            fitted
        }
    }
}

private struct PopoverMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear)
    }
}

struct PopoverMenuSelect {
    let run: (@escaping () -> Void) -> Void
}

private struct PopoverMenuSelectKey: EnvironmentKey {
    static let defaultValue = PopoverMenuSelect { $0() }
}

extension EnvironmentValues {
    var popoverMenuSelect: PopoverMenuSelect {
        get { self[PopoverMenuSelectKey.self] }
        set { self[PopoverMenuSelectKey.self] = newValue }
    }
}
