import SwiftUI

/// Quản trị danh mục Topping (Menu > Topping) — thêm/sửa/xoá, thay cho phải mở Desktop
/// (ToppingWindow). GET/POST/PUT/DELETE /api/Topping, bố cục giống NguyenLieuListView.
struct ToppingListView: View {
    @State private var items: [ToppingDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showNgungBan = false
    @State private var showAdd = false
    @State private var editing: ToppingDto?

    private var filteredItems: [ToppingDto] {
        var source = items
        if !showNgungBan { source = source.filter { !$0.ngungBan } }
        let sorted = source.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.ten.matchesSearch(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm topping...")

            Toggle("Hiện topping ngừng bán", isOn: $showNgungBan)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            if !hasLoaded {
                fullScreenLoading()
            } else {
                List {
                    ForEach(filteredItems) { item in
                        ToppingRowView(item: item) {
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
        .navigationTitle("Topping")
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
            ToppingEditSheet(existing: nil, allItems: items) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            ToppingEditSheet(existing: item, allItems: items) { Task { await load() } }
        }
    }

    private func load() async {
        items = await APIClient.shared.getToppingAdmin()
        hasLoaded = true
    }

    private func delete(_ item: ToppingDto) async {
        _ = await APIClient.shared.deleteTopping(id: item.id)
        await load()
    }
}

private struct ToppingRowView: View {
    let item: ToppingDto
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack {
                Text(item.ten)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .strikethrough(item.ngungBan)
                if item.ngungBan {
                    Text("Ngừng bán")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.textMuted)
                        .clipShape(Capsule())
                }
                Spacer()
                Text(HoaDonFormatting.money(item.gia))
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(.brandPrimary)
            }
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

private struct ToppingEditSheet: View {
    let existing: ToppingDto?
    let allItems: [ToppingDto]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten: String
    @State private var gia: Double
    @State private var ngungBan: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    init(existing: ToppingDto?, allItems: [ToppingDto], onSaved: @escaping () -> Void) {
        self.existing = existing
        self.allItems = allItems
        self.onSaved = onSaved
        _ten = State(initialValue: existing?.ten ?? "")
        _gia = State(initialValue: existing?.gia ?? 0)
        _ngungBan = State(initialValue: existing?.ngungBan ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên topping", text: $ten)
                    HStack {
                        Text("Giá")
                        Spacer()
                        TextField("0", value: $gia, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Toggle("Ngừng bán", isOn: $ngungBan)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm topping" : "Sửa topping")
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

        guard gia >= 0 else {
            errorMessage = "Giá không hợp lệ."
            saving = false
            return
        }

        let stt = existing?.stt ?? ((allItems.map(\.stt).max() ?? 0) + 1)

        let body = ToppingDto(
            id: existing?.id ?? "00000000-0000-0000-0000-000000000000",
            ten: ten.trimmingCharacters(in: .whitespaces),
            gia: gia,
            ngungBan: ngungBan,
            stt: stt
        )

        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateTopping(id: existing.id, body)
        } else {
            result = await APIClient.shared.createTopping(body)
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
