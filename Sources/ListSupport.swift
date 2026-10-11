import SwiftUI

extension View {
    /// Hỏi xác nhận trước khi xoá (hoặc 1 thao tác phá huỷ tương tự) rồi mới gọi API, và BÁO LỖI nếu
    /// server từ chối. Trước đây các màn danh mục trong Menu vuốt trái là xoá thẳng, kết quả gọi API
    /// bị bỏ qua (`_ = await ...`) — vuốt nhầm là mất dữ liệu, xoá thất bại thì không ai biết.
    /// Gán `pending` = item cần xoá để mở hộp xác nhận; `onDone` luôn chạy sau khi gọi API (thường là
    /// `load()` lại danh sách).
    func confirmDelete<Item>(
        _ pending: Binding<Item?>,
        title: String = "Xoá",
        confirmLabel: String = "Xoá",
        name: @escaping (Item) -> String,
        note: String = "Không thể hoàn tác.",
        perform: @escaping (Item) async -> ActionResult,
        onDone: @escaping () async -> Void
    ) -> some View {
        modifier(ConfirmDeleteModifier(
            pending: pending, title: title, confirmLabel: confirmLabel,
            name: name, note: note, perform: perform, onDone: onDone))
    }

    /// Alert báo lỗi dùng chung cho các thao tác nhanh (bật/tắt, gỡ...) — nil = không hiện.
    func actionErrorAlert(_ message: Binding<String?>) -> some View {
        popupHost { host in
            host.alert("Không thực hiện được", isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(message.wrappedValue ?? "")
            }
        }
    }
}

private struct ConfirmDeleteModifier<Item>: ViewModifier {
    @Binding var pending: Item?
    let title: String
    let confirmLabel: String
    let name: (Item) -> String
    let note: String
    let perform: (Item) async -> ActionResult
    let onDone: () async -> Void

    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .popupHost { host in
                host.confirmationDialog(
                    title,
                    isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                    titleVisibility: .visible,
                    presenting: pending
                ) { item in
                    Button(confirmLabel, role: .destructive) { Task { await run(item) } }
                    Button("Huỷ", role: .cancel) {}
                } message: { item in
                    Text("\(confirmLabel) \"\(name(item))\"? \(note)")
                }
            }
            .actionErrorAlert($errorMessage)
    }

    private func run(_ item: Item) async {
        let result = await perform(item)
        if !result.success {
            errorMessage = result.message?.isEmpty == false ? result.message! : "Thao tác thất bại — thử lại."
        }
        await onDone()
    }
}
