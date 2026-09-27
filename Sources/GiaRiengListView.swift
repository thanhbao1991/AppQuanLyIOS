import SwiftUI

/// Quản trị Giá riêng theo khách hàng (Menu > Giá riêng) — thêm/sửa/xoá giá riêng cho 1 khách +
/// 1 biến thể sản phẩm, thay cho phải mở Desktop (GiaRiengWindow). GET /api/KhachHangGiaBan (đã
/// join sẵn tên khách/sản phẩm/biến thể + giá hệ thống), lưu qua POST .../upsert (server tự khớp
/// theo khachHangId+sanPhamBienTheId: có rồi thì cập nhật giá, chưa có thì tạo mới).
struct GiaRiengListView: View {
    @State private var items: [GiaRiengAdminDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editing: GiaRiengAdminDto?

    private var filteredItems: [GiaRiengAdminDto] {
        guard !searchText.isEmpty else { return items }
        return items.filter { anyMatchesSearch(searchText, $0.tenKhachHang, $0.tenSanPham, $0.tenBienThe) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm khách, sản phẩm...")

            if !hasLoaded {
                fullScreenLoading()
            } else {
                List {
                    ForEach(filteredItems) { item in
                        GiaRiengRowView(item: item) {
                            editing = item
                        } onDelete: {
                            Task { await delete(item) }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Giá riêng")
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
            GiaRiengEditSheet(existing: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            GiaRiengEditSheet(existing: item) { Task { await load() } }
        }
    }

    private func load() async {
        items = await APIClient.shared.getGiaRiengAdmin()
            .sorted { $0.tenKhachHang ?? "" < $1.tenKhachHang ?? "" }
        hasLoaded = true
    }

    private func delete(_ item: GiaRiengAdminDto) async {
        _ = await APIClient.shared.deleteGiaRieng(id: item.id)
        await load()
    }
}

private struct GiaRiengRowView: View {
    let item: GiaRiengAdminDto
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var isGiamGia: Bool { item.giaBan < item.giaBanHeThong }

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.tenKhachHang ?? "?")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                HStack {
                    Text([item.tenSanPham, item.tenBienThe].compactMap { $0 }.joined(separator: "  "))
                        .font(.caption)
                        .foregroundColor(.textMuted)
                    Spacer()
                    if isGiamGia {
                        Text(HoaDonFormatting.money(item.giaBanHeThong))
                            .font(.caption2)
                            .strikethrough()
                            .foregroundColor(.textMuted)
                    }
                    Text(HoaDonFormatting.money(item.giaBan))
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(isGiamGia ? .dangerColor : .brandPrimary)
                }
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

private struct GiaRiengEditSheet: View {
    let existing: GiaRiengAdminDto?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var khachHangId: String?
    @State private var khachDisplayName: String
    @State private var khachSearchText = ""
    @State private var khachSearchResults: [KhachHangDto] = []
    @State private var khachSearchTask: Task<Void, Never>?

    @State private var sanPhamBienTheId: String?
    @State private var spDisplayName: String
    @State private var spSearchText = ""
    @State private var allSanPham: [SanPhamDto] = []
    @State private var giaHeThong: Double?

    @State private var giaBan: Double
    @State private var saving = false
    @State private var errorMessage: String?

    init(existing: GiaRiengAdminDto?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _khachHangId = State(initialValue: existing?.khachHangId)
        _khachDisplayName = State(initialValue: existing?.tenKhachHang ?? "")
        _sanPhamBienTheId = State(initialValue: existing?.sanPhamBienTheId)
        _spDisplayName = State(initialValue: [existing?.tenSanPham, existing?.tenBienThe].compactMap { $0 }.joined(separator: "  "))
        _giaHeThong = State(initialValue: existing?.giaBanHeThong)
        _giaBan = State(initialValue: existing?.giaBan ?? 0)
    }

    private var matchingSanPham: [SanPhamDto] {
        guard !spSearchText.isEmpty else { return [] }
        return allSanPham.filter { $0.ten.matchesSearch(spSearchText) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Khách hàng") {
                    if let khachHangId, khachSearchText.isEmpty {
                        HStack {
                            Text(khachDisplayName)
                            Spacer()
                            Button("Đổi") { self.khachHangId = nil; khachDisplayName = "" }
                                .font(.caption)
                        }
                        .id(khachHangId)
                    } else {
                        TextField("Tìm khách theo tên/SĐT...", text: $khachSearchText)
                            .onChange(of: khachSearchText) { q in scheduleKhachSearch(q) }
                        ForEach(khachSearchResults) { kh in
                            Button {
                                khachHangId = kh.id
                                khachDisplayName = kh.ten
                                khachSearchText = ""
                                khachSearchResults = []
                            } label: {
                                Text(kh.ten).foregroundColor(.primary)
                            }
                        }
                    }
                }

                Section("Sản phẩm / biến thể") {
                    if let sanPhamBienTheId, spSearchText.isEmpty {
                        HStack {
                            Text(spDisplayName)
                            Spacer()
                            Button("Đổi") { self.sanPhamBienTheId = nil; spDisplayName = "" }
                                .font(.caption)
                        }
                        .id(sanPhamBienTheId)
                    } else {
                        TextField("Tìm sản phẩm...", text: $spSearchText)
                        ForEach(matchingSanPham) { sp in
                            ForEach(sp.bienThe) { bt in
                                Button {
                                    sanPhamBienTheId = bt.id
                                    spDisplayName = formatSpBt(sp, bt)
                                    giaHeThong = bt.giaBan
                                    spSearchText = ""
                                } label: {
                                    HStack {
                                        Text(formatSpBt(sp, bt)).foregroundColor(.primary)
                                        Spacer()
                                        Text(HoaDonFormatting.money(bt.giaBan)).font(.caption).foregroundColor(.textMuted)
                                    }
                                }
                            }
                        }
                    }
                    if let giaHeThong {
                        Text("Giá hệ thống: \(HoaDonFormatting.money(giaHeThong))")
                            .font(.caption).foregroundColor(.textMuted)
                    }
                }

                Section("Giá riêng") {
                    TextField("0", value: $giaBan, format: .number)
                        .keyboardType(.numberPad)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm giá riêng" : "Sửa giá riêng")
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
                .disabled(khachHangId == nil || sanPhamBienTheId == nil || giaBan <= 0 || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
        }
        .task {
            allSanPham = await APIClient.shared.getSanPhamList()
        }
    }

    private func formatSpBt(_ sp: SanPhamDto, _ bt: SanPhamBienTheDto) -> String {
        let size = ["Mặc định", "Size Chuẩn", "Chuẩn"].contains(bt.tenBienThe) ? "" : bt.tenBienThe
        return size.isEmpty ? sp.ten : "\(sp.ten)  \(size)"
    }

    private func scheduleKhachSearch(_ q: String) {
        khachSearchTask?.cancel()
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            khachSearchResults = []
            return
        }
        khachSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let result = await APIClient.shared.searchKhachHang(q)
            guard !Task.isCancelled else { return }
            khachSearchResults = result
        }
    }

    private func save() async {
        guard let khachHangId, let sanPhamBienTheId else { return }
        saving = true
        errorMessage = nil

        let body = GiaRiengUpsertRequest(khachHangId: khachHangId, sanPhamBienTheId: sanPhamBienTheId, giaBan: giaBan)
        let result = await APIClient.shared.upsertGiaRieng(body)

        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}
