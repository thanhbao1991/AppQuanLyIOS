import SwiftUI

/// Quản trị danh mục Tên đường (Menu > Tên đường) — thêm/sửa/xoá gợi ý địa chỉ, thay cho phải mở
/// Desktop (TenDuongWindow). GET/POST/PUT/DELETE /api/TenDuong (server tự viết hoa đầu mỗi từ,
/// xem TenDuongService.CreateAsync/UpdateAsync — không cần làm lại ở client).
struct TenDuongListView: View {
    @State private var items: [TenDuongDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editing: TenDuongDto?

    private var filteredItems: [TenDuongDto] {
        let sorted = items.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.ten.matchesSearch(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm tên đường...")

            if !hasLoaded {
                fullScreenLoading()
            } else {
                List {
                    ForEach(filteredItems) { item in
                        TenDuongRowView(item: item) {
                            editing = item
                        } onDelete: {
                            Task { await delete(item) }
                        }
                    }
                }
                .listStyle(.plain)
                .softScrollEdgeTop()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Tên đường")
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
        .sheet(isPresented: $showAdd) {
            TenDuongEditSheet(existing: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            TenDuongEditSheet(existing: item) { Task { await load() } }
        }
    }

    private func load() async {
        items = await APIClient.shared.getTenDuongList()
        hasLoaded = true
    }

    private func delete(_ item: TenDuongDto) async {
        _ = await APIClient.shared.deleteTenDuong(id: item.id)
        await load()
    }
}

private struct TenDuongRowView: View {
    let item: TenDuongDto
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            Text(item.ten)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandPrimary.pastelBackground(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                EmojiLabel("Xoá", "🗑️")
            }
        }
    }
}

private struct TenDuongEditSheet: View {
    let existing: TenDuongDto?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(existing: TenDuongDto?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _ten = State(initialValue: existing?.ten ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên đường", text: $ten)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm tên đường" : "Sửa tên đường")
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
                .disabled(ten.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil

        let body = TenDuongDto(id: existing?.id ?? "00000000-0000-0000-0000-000000000000", ten: ten.trimmingCharacters(in: .whitespaces))

        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateTenDuong(id: existing.id, body)
        } else {
            result = await APIClient.shared.createTenDuong(body)
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
