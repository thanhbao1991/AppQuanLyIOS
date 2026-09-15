import SwiftUI

/// Quản trị danh mục nguyên liệu (Menu > Công cụ) — thêm/sửa/xoá/đổi nhóm chi tiêu, thay cho phải mở
/// Desktop mỗi khi cần chỉnh sửa nhỏ. GET/POST/PUT/DELETE /api/NguyenLieu, giống hệt VoucherListView
/// về mặt bố cục (list + sheet sửa).
struct NguyenLieuListView: View {
    @State private var items: [NguyenLieuDto] = []
    @State private var danhMucs: [DanhMucChiTieuDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editing: NguyenLieuDto?
    /// nil = tất cả nhóm; "" (rỗng) = chỉ nguyên liệu chưa gắn nhóm nào.
    @State private var filterDanhMucId: String?

    private var filteredItems: [NguyenLieuDto] {
        var list = items
        if let filterDanhMucId {
            list = filterDanhMucId.isEmpty
                ? list.filter { $0.danhMucChiTieuId == nil }
                : list.filter { $0.danhMucChiTieuId == filterDanhMucId }
        }
        let sorted = list.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.ten.matchesSearch(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm nguyên liệu...")

            if !hasLoaded {
                Spacer(); ProgressView(); Spacer()
            } else {
                List {
                    ForEach(filteredItems) { item in
                        NguyenLieuRowView(item: item) {
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
        .navigationTitle("Nguyên liệu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        filterDanhMucId = nil
                    } label: {
                        if filterDanhMucId == nil { Label("Tất cả nhóm", systemImage: "checkmark") }
                        else { Text("Tất cả nhóm") }
                    }
                    Button {
                        filterDanhMucId = ""
                    } label: {
                        if filterDanhMucId == "" { Label("Chưa có nhóm", systemImage: "checkmark") }
                        else { Text("Chưa có nhóm") }
                    }
                    Divider()
                    ForEach(danhMucs) { dm in
                        Button {
                            filterDanhMucId = dm.id
                        } label: {
                            if filterDanhMucId == dm.id { Label(dm.ten, systemImage: "checkmark") }
                            else { Text(dm.ten) }
                        }
                    }
                } label: {
                    Image(systemName: filterDanhMucId == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            NguyenLieuEditSheet(existing: nil, danhMucs: danhMucs) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            NguyenLieuEditSheet(existing: item, danhMucs: danhMucs) { Task { await load() } }
        }
    }

    private func load() async {
        async let itemsTask = APIClient.shared.getNguyenLieu()
        async let danhMucTask = APIClient.shared.getDanhMucChiTieuList()
        items = await itemsTask
        danhMucs = await danhMucTask
        hasLoaded = true
    }

    private func delete(_ item: NguyenLieuDto) async {
        _ = await APIClient.shared.deleteNguyenLieu(id: item.id)
        await load()
    }
}

private struct NguyenLieuRowView: View {
    let item: NguyenLieuDto
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.ten)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .strikethrough(item.ngungSuDung)
                    if item.ngungSuDung {
                        Text("Ngưng dùng")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.textMuted)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text(HoaDonFormatting.money(item.giaNhap))
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.brandPrimary)
                }
                HStack {
                    if let donViTinh = item.donViTinh, !donViTinh.isEmpty {
                        Text(donViTinh).font(.caption2).foregroundColor(.textMuted)
                    }
                    if let tenDanhMuc = item.tenDanhMucChiTieu, !tenDanhMuc.isEmpty {
                        Text(tenDanhMuc)
                            .font(.caption2)
                            .foregroundColor(.brandPrimary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.brandPrimary.pastelBackground())
                            .clipShape(Capsule())
                    }
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

private struct NguyenLieuEditSheet: View {
    let existing: NguyenLieuDto?
    let danhMucs: [DanhMucChiTieuDto]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten: String
    @State private var donViTinh: String
    @State private var giaNhap: Double
    @State private var ngungSuDung: Bool
    @State private var danhMucChiTieuId: String?
    @State private var saving = false
    @State private var errorMessage: String?

    init(existing: NguyenLieuDto?, danhMucs: [DanhMucChiTieuDto], onSaved: @escaping () -> Void) {
        self.existing = existing
        self.danhMucs = danhMucs
        self.onSaved = onSaved
        _ten = State(initialValue: existing?.ten ?? "")
        _donViTinh = State(initialValue: existing?.donViTinh ?? "")
        _giaNhap = State(initialValue: existing?.giaNhap ?? 0)
        _ngungSuDung = State(initialValue: existing?.ngungSuDung ?? false)
        _danhMucChiTieuId = State(initialValue: existing?.danhMucChiTieuId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên nguyên liệu", text: $ten)
                    TextField("Đơn vị tính (VD: Kg, Ly, Cái...)", text: $donViTinh)
                    HStack {
                        Text("Giá nhập")
                        Spacer()
                        TextField("0", value: $giaNhap, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Nhóm chi tiêu") {
                    Picker("Nhóm", selection: $danhMucChiTieuId) {
                        Text("Không thuộc nhóm nào").tag(String?.none)
                        ForEach(danhMucs) { dm in
                            Text(dm.ten).tag(String?.some(dm.id))
                        }
                    }
                }

                Section {
                    Toggle("Ngưng sử dụng", isOn: $ngungSuDung)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm nguyên liệu" : "Sửa nguyên liệu")
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

        let body = NguyenLieuUpdateRequest(
            ten: ten.trimmingCharacters(in: .whitespaces),
            donViTinh: donViTinh.trimmingCharacters(in: .whitespaces).isEmpty ? nil : donViTinh,
            giaNhap: giaNhap,
            ngungSuDung: ngungSuDung,
            thuTu: existing?.thuTu ?? 0,
            // Giữ nguyên liên kết tồn kho bán hàng — không cho sửa ở màn này, xem NguyenLieuDto.
            nguyenLieuBanHangId: existing?.nguyenLieuBanHangId,
            heSoQuyDoiBanHang: existing?.heSoQuyDoiBanHang,
            danhMucChiTieuId: danhMucChiTieuId
        )

        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateNguyenLieu(id: existing.id, body)
        } else {
            result = await APIClient.shared.createNguyenLieuFull(body)
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
