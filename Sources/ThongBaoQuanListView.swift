import SwiftUI

/// Quản trị tin khuyến mãi hiện cho app khách (AppDatHangIOS, tab "Thông báo") — GET/POST/PUT/DELETE
/// /api/ThongBaoQuan. Toggle "Đang hoạt động" ẩn/hiện tin khỏi app khách mà không cần xoá.
struct ThongBaoQuanListView: View {
    @State private var items: [ThongBaoQuanDto] = []
    @State private var hasLoaded = false
    @State private var showAdd = false
    @State private var editing: ThongBaoQuanDto?
    @State private var deleting: ThongBaoQuanDto?
    @State private var loadFailed = false
    @State private var actionError: String?

    var body: some View {
        Group {
            if !hasLoaded {
                fullScreenLoading()
            } else {
                List {
                    if loadFailed {
                        ThongKeLoadErrorBanner(text: "Chưa tải được danh sách thông báo") { Task { await load() } }
                            .listRowSeparator(.hidden)
                    }
                    if items.isEmpty && loadFailed {
                        EmptyView()
                    } else if items.isEmpty {
                        Text("Chưa có thông báo/khuyến mãi nào")
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(items) { item in
                            ThongBaoQuanRowView(item: item) {
                                Task { await toggle(item) }
                            } onEdit: {
                                editing = item
                            } onDelete: {
                                deleting = item
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .softScrollEdgeTop()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Thông báo/Khuyến mãi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .confirmDelete($deleting, name: { $0.tieude }, perform: { await APIClient.shared.deleteThongBaoQuan(id: $0.id) }, onDone: load)
        .actionErrorAlert($actionError)
        .sheet(isPresented: $showAdd) {
            ThongBaoQuanEditSheet(existing: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            ThongBaoQuanEditSheet(existing: item) { Task { await load() } }
        }
    }

    private func load() async {
        let fresh = await APIClient.shared.getThongBaoQuanListOrNil()
        if let fresh { items = fresh }
        loadFailed = fresh == nil
        hasLoaded = true
    }

    private func toggle(_ item: ThongBaoQuanDto) async {
        let result = await APIClient.shared.updateThongBaoQuan(
            id: item.id, tieude: item.tieude, noiDung: item.noiDung, dangHoatDong: !item.dangHoatDong)
        if !result.success { actionError = result.message ?? "Chưa đổi được trạng thái thông báo." }
        await load()
    }

}

private struct ThongBaoQuanRowView: View {
    let item: ThongBaoQuanDto
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var mauTrangThai: Color { item.dangHoatDong ? .successColor : .textMuted }

    var body: some View {
        Button(action: onEdit) {
            HStack(alignment: .top, spacing: 12) {
                Text("📣")
                    .font(.system(size: 20))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(mauTrangThai.opacity(0.14)))
                    .grayscale(item.dangHoatDong ? 0 : 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.tieude)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            Circle().fill(mauTrangThai).frame(width: 6, height: 6)
                            Text(item.dangHoatDong ? "Đang hiện" : "Đã ẩn")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(mauTrangThai)
                        }
                        .fixedSize()
                    }
                    Text(item.noiDung)
                        .font(.footnote)
                        .foregroundColor(.textMuted)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if let ngayTao = item.ngayTao {
                        Text(HoaDonFormatting.congNoTime(ngayTao))
                            .font(.caption)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            // Tin đã ẩn khỏi app khách thì làm mờ — nhìn là biết khách đang không thấy.
            .opacity(item.dangHoatDong ? 1 : 0.65)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(action: onDelete) {
                Label("Xoá", systemImage: "trash")
            }
            .tint(.dangerColor)
            Button(action: onToggle) {
                Label(item.dangHoatDong ? "Ẩn" : "Hiện", systemImage: item.dangHoatDong ? "eye.slash" : "eye")
            }
            .tint(.brandPrimary)
        }
    }
}

private struct ThongBaoQuanEditSheet: View {
    let existing: ThongBaoQuanDto?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tieude: String
    @State private var noiDung: String
    @State private var dangHoatDong: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    init(existing: ThongBaoQuanDto?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _tieude = State(initialValue: existing?.tieude ?? "")
        _noiDung = State(initialValue: existing?.noiDung ?? "")
        _dangHoatDong = State(initialValue: existing?.dangHoatDong ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tiêu đề") {
                    TextField("Vd: Flash Sale cuối tuần", text: $tieude)
                }
                Section("Nội dung") {
                    TextField("Nội dung hiện cho khách...", text: $noiDung, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("Đang hoạt động (hiện cho khách)", isOn: $dangHoatDong)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm thông báo" : "Sửa thông báo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "Đang lưu..." : "Lưu")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)
                .disabled(tieude.trimmingCharacters(in: .whitespaces).isEmpty
                    || noiDung.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                // Color(.systemBackground) thay vì .background(.bar) — xem HoaDonEditFormView.
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let t = tieude.trimmingCharacters(in: .whitespaces)
        let n = noiDung.trimmingCharacters(in: .whitespaces)
        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateThongBaoQuan(id: existing.id, tieude: t, noiDung: n, dangHoatDong: dangHoatDong)
        } else {
            result = await APIClient.shared.createThongBaoQuan(tieude: t, noiDung: n, dangHoatDong: dangHoatDong)
        }
        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}
