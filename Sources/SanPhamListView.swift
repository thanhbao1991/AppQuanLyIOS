import SwiftUI

/// Quản trị danh mục sản phẩm (Menu > Sản phẩm) — thêm/sửa/xoá + đẩy/đồng bộ store, thay cho phải
/// mở Desktop (SanPhamWindow) mỗi khi cần chỉnh sửa. GET/POST/PUT/DELETE /api/SanPham +
/// /api/AppOrder/{sync-store-status,push-san-pham,rename-san-pham,store-visibility,push-topping,push-size-xl},
/// bố cục list + sheet sửa giống NguyenLieuListView/VoucherListView.
struct SanPhamListView: View {
    @State private var items: [SanPhamAdminDto] = []
    @State private var nhoms: [NhomSanPhamDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showNgungBan = false
    @State private var showAdd = false
    @State private var editing: SanPhamAdminDto?
    @State private var isSyncingStore = false
    @State private var isPushingToppingAll = false
    @State private var isPushingSizeXLAll = false
    @State private var toastMessage: String?
    @State private var showPushToppingAllConfirm = false
    @State private var showPushSizeXLAllConfirm = false

    private var filteredItems: [SanPhamAdminDto] {
        var source = items
        if !showNgungBan { source = source.filter { !$0.ngungBan } }
        let sorted = source.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { anyMatchesSearch(searchText, $0.ten, $0.vietTat, $0.tenNhomSanPham) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm sản phẩm, nhóm...")

            Toggle("Hiện sản phẩm ngừng bán", isOn: $showNgungBan)
                .font(.caption)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

            if !hasLoaded {
                fullScreenLoading()
            } else {
                List {
                    ForEach(filteredItems) { item in
                        SanPhamRowView(item: item) {
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
        .navigationTitle("Sản phẩm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        Button {
                            Task { await syncStore() }
                        } label: {
                            Label("Kiểm tra Store", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            showPushToppingAllConfirm = true
                        } label: {
                            Label("Đẩy topping hàng loạt", systemImage: "text.badge.plus")
                        }
                        Button {
                            showPushSizeXLAllConfirm = true
                        } label: {
                            Label("Đẩy Size XL hàng loạt", systemImage: "arrow.up.circle")
                        }
                    } label: {
                        if isSyncingStore || isPushingToppingAll || isPushingSizeXLAll {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "storefront")
                        }
                    }
                    .disabled(isSyncingStore || isPushingToppingAll || isPushingSizeXLAll)
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            SanPhamEditSheet(existing: nil, allItems: items, nhoms: nhoms) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            SanPhamEditSheet(existing: item, allItems: items, nhoms: nhoms) { Task { await load() } }
        }
        .popupHost { host in
        host
        .alert("Store", isPresented: Binding(get: { toastMessage != nil }, set: { if !$0 { toastMessage = nil } })) {
            Button("OK") { toastMessage = nil }
        } message: {
            Text(toastMessage ?? "")
        }
        .confirmationDialog(
            "Đẩy/đồng bộ toàn bộ topping đang bán vào Size/Topping của TẤT CẢ sản phẩm đã có trên store (chưa có thì tạo mới, có rồi mà lệch giá thì cập nhật)?\n\nChạy nền, chậm rãi (có thể mất vài chục phút) — kết quả sẽ báo qua thông báo Hệ thống (icon chuông).",
            isPresented: $showPushToppingAllConfirm, titleVisibility: .visible
        ) {
            Button("Đẩy hàng loạt", role: .destructive) { Task { await pushToppingAll() } }
            Button("Huỷ", role: .cancel) {}
        }
        .confirmationDialog(
            "Đẩy biến thể \"Size XL\" (giá chênh cố định) lên TẤT CẢ sản phẩm đã có trên store VÀ đã có biến thể Size XL nội bộ?\n\nChạy nền, chậm rãi — kết quả sẽ báo qua thông báo Hệ thống (icon chuông).",
            isPresented: $showPushSizeXLAllConfirm, titleVisibility: .visible
        ) {
            Button("Đẩy hàng loạt", role: .destructive) { Task { await pushSizeXLAll() } }
            Button("Huỷ", role: .cancel) {}
        }
        }
    }

    private func load() async {
        async let itemsTask = APIClient.shared.getSanPhamAdmin()
        async let nhomsTask = APIClient.shared.getNhomSanPham()
        items = await itemsTask
        nhoms = (await nhomsTask).sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
        hasLoaded = true
    }

    private func delete(_ item: SanPhamAdminDto) async {
        _ = await APIClient.shared.deleteSanPham(id: item.id)
        await load()
    }

    private func syncStore() async {
        isSyncingStore = true
        let result = await APIClient.shared.syncSanPhamStoreStatus()
        isSyncingStore = false
        toastMessage = result.message ?? (result.success ? "Đã kiểm tra xong." : "Kiểm tra Store thất bại.")
        await load()
    }

    private func pushToppingAll() async {
        isPushingToppingAll = true
        let result = await APIClient.shared.pushToppingAllToStore()
        isPushingToppingAll = false
        toastMessage = result.message ?? (result.success ? "Đang đẩy topping hàng loạt." : "Không gửi được yêu cầu.")
    }

    private func pushSizeXLAll() async {
        isPushingSizeXLAll = true
        let result = await APIClient.shared.pushSizeXLAllToStore()
        isPushingSizeXLAll = false
        toastMessage = result.message ?? (result.success ? "Đang đẩy Size XL hàng loạt." : "Không gửi được yêu cầu.")
    }
}

private struct SanPhamRowView: View {
    let item: SanPhamAdminDto
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var giaHienThi: String {
        guard !item.bienThe.isEmpty else { return "" }
        let prices = item.bienThe.map(\.giaBan).sorted()
        guard let min = prices.first, let max = prices.last else { return "" }
        return min == max ? HoaDonFormatting.money(min) : "\(HoaDonFormatting.money(min)) - \(HoaDonFormatting.money(max))"
    }

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 4) {
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
                    Text(giaHienThi)
                        .font(.caption).fontWeight(.bold)
                        .foregroundColor(.brandPrimary)
                }
                HStack {
                    if let nhom = item.tenNhomSanPham, !nhom.isEmpty {
                        Text(nhom)
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                    if let store = item.storeStatus, !store.isEmpty {
                        Text(store).font(.caption2).foregroundColor(.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                EmojiLabel("Xoá", "🗑️")
            }
        }
    }
}

/// Danh tính riêng cho SwiftUI ForEach (localId: UUID luôn duy nhất) — TÁCH khỏi serverId vì nhiều
/// biến thể MỚI thêm cùng lúc đều có serverId rỗng ("00000000-...") giống hệt nhau, nếu dùng
/// serverId làm id cho ForEach sẽ đụng identity, sửa 1 dòng lại ảnh hưởng nhầm dòng khác.
private struct BienTheEditRow: Identifiable {
    let localId = UUID()
    var serverId: String = "00000000-0000-0000-0000-000000000000"
    var tenBienThe: String
    var giaBan: Double
    var macDinh: Bool
    var dinhLuong: String?
    var id: UUID { localId }
}

private struct SanPhamEditSheet: View {
    let existing: SanPhamAdminDto?
    let allItems: [SanPhamAdminDto]
    let nhoms: [NhomSanPhamDto]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten: String
    @State private var vietTat: String
    @State private var nhomSanPhamId: String?
    @State private var ngungBan: Bool
    @State private var khongLenStore: Bool
    @State private var bienThe: [BienTheEditRow]
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var storeActionMessage: String?
    @State private var storeActionRunning = false

    init(existing: SanPhamAdminDto?, allItems: [SanPhamAdminDto], nhoms: [NhomSanPhamDto], onSaved: @escaping () -> Void) {
        self.existing = existing
        self.allItems = allItems
        self.nhoms = nhoms
        self.onSaved = onSaved
        _ten = State(initialValue: existing?.ten ?? "")
        _vietTat = State(initialValue: existing?.vietTat ?? "")
        _nhomSanPhamId = State(initialValue: existing?.nhomSanPhamId)
        _ngungBan = State(initialValue: existing?.ngungBan ?? false)
        _khongLenStore = State(initialValue: existing?.khongLenStore ?? false)
        _bienThe = State(initialValue: existing?.bienThe.isEmpty == false
            ? existing!.bienThe
                .sorted { $0.macDinh && !$1.macDinh }
                .map { BienTheEditRow(serverId: $0.id, tenBienThe: $0.tenBienThe, giaBan: $0.giaBan, macDinh: $0.macDinh, dinhLuong: $0.dinhLuong) }
            : [BienTheEditRow(tenBienThe: "Size chuẩn", giaBan: 0, macDinh: true)])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên sản phẩm", text: $ten)
                    TextField("Viết tắt (VD: ts, cfk...)", text: $vietTat)
                    Picker("Nhóm sản phẩm", selection: $nhomSanPhamId) {
                        Text("Chưa chọn").tag(String?.none)
                        ForEach(nhoms) { nhom in
                            Text(nhom.ten).tag(String?.some(nhom.id))
                        }
                    }
                }

                Section {
                    Toggle("Ngừng bán", isOn: $ngungBan)
                    Toggle("Không lên store", isOn: $khongLenStore)
                }

                Section("Biến thể") {
                    ForEach($bienThe) { $row in
                        bienTheRow($row)
                    }
                    Button {
                        bienThe.append(BienTheEditRow(tenBienThe: "Size", giaBan: 0, macDinh: bienThe.isEmpty))
                    } label: {
                        EmojiLabel("Thêm biến thể", "➕")
                    }
                }

                if existing != nil {
                    Section("Store") {
                        if let storeStatus = existing?.storeStatus, !storeStatus.isEmpty {
                            Text(storeStatus).font(.caption).foregroundColor(.textMuted)
                        }
                        storeActionButton("Đẩy lên store", icon: "icloud.and.arrow.up") { await pushToStore() }
                        storeActionButton("Đổi tên trên store", icon: "pencil") { await renameOnStore() }
                        storeActionButton("Ngừng bán trên store", icon: "storefront") { await toggleStoreVisibility(ngungBan: true) }
                        storeActionButton("Bán lại trên store", icon: "storefront.fill") { await toggleStoreVisibility(ngungBan: false) }
                        storeActionButton("Đẩy topping lên store", icon: "plus.circle") { await pushToppingToStore() }
                        if bienThe.contains(where: { $0.tenBienThe == "Size XL" }) {
                            storeActionButton("Đẩy Size XL lên store", icon: "arrow.up.circle") { await pushSizeXLToStore() }
                        }
                        if storeActionRunning { ProgressView() }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm sản phẩm" : "Sửa sản phẩm")
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
            .popupHost { host in
                host.alert("Store", isPresented: Binding(get: { storeActionMessage != nil }, set: { if !$0 { storeActionMessage = nil } })) {
                    Button("OK") { storeActionMessage = nil }
                } message: {
                    Text(storeActionMessage ?? "")
                }
            }
        }
    }

    private func bienTheRow(_ row: Binding<BienTheEditRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Tên biến thể", text: row.tenBienThe)
                Spacer()
                Button {
                    if bienThe.count > 1 { bienThe.removeAll { $0.id == row.wrappedValue.id } }
                } label: {
                    Image(systemName: "trash").foregroundColor(.dangerColor)
                }
            }
            HStack {
                TextField("Giá bán", value: row.giaBan, format: .number)
                    .keyboardType(.numberPad)
                TextField("Định lượng (tuỳ chọn)", text: Binding(
                    get: { row.wrappedValue.dinhLuong ?? "" },
                    set: { row.wrappedValue.dinhLuong = $0.isEmpty ? nil : $0 }
                ))
                // Toggle "Mặc định" đã BỎ 28/9 — macDinh giờ tự động gán cho biến thể rẻ nhất lúc
                // save() (xem comment ở đó), staff không tự chọn tay được nữa để tránh gán nhầm.
            }
        }
        .padding(.vertical, 2)
    }

    private func storeActionButton(_ title: String, icon: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: icon)
        }
        .disabled(storeActionRunning)
    }

    private func save() async {
        saving = true
        errorMessage = nil

        let rows = bienThe.filter { !$0.tenBienThe.trimmingCharacters(in: .whitespaces).isEmpty || $0.giaBan > 0 }
        guard !rows.isEmpty else {
            errorMessage = "Thêm ít nhất 1 biến thể (để lấy giá bán)."
            saving = false
            return
        }
        for row in rows where row.giaBan <= 0 {
            errorMessage = "Giá biến thể \"\(row.tenBienThe)\" không hợp lệ."
            saving = false
            return
        }
        // macDinh KHÔNG còn cho staff tự chọn tay (đã ẩn Toggle ở bienTheRow) — luôn tự động gán cho
        // biến thể RẺ NHẤT, tránh lặp lại anomaly 28/9: nhiều món bị gán nhầm "Size L" làm mặc định
        // (giá cao hơn "Size Chuẩn"), gây giá/định lượng hiển thị sai chỗ khắp app.
        var finalBienThe = rows
        if let cheapestIdx = finalBienThe.indices.min(by: { finalBienThe[$0].giaBan < finalBienThe[$1].giaBan }) {
            for i in finalBienThe.indices { finalBienThe[i].macDinh = (i == cheapestIdx) }
        }
        let bienTheDtos = finalBienThe.map {
            SanPhamBienTheAdminDto(id: $0.serverId, tenBienThe: $0.tenBienThe.trimmingCharacters(in: .whitespaces), giaBan: $0.giaBan, macDinh: $0.macDinh, dinhLuong: $0.dinhLuong)
        }

        let thuTu = existing?.thuTu ?? ((allItems.map(\.thuTu).max() ?? 0) + 1)

        let body = SanPhamAdminDto(
            id: existing?.id ?? "00000000-0000-0000-0000-000000000000",
            ten: ten.trimmingCharacters(in: .whitespaces),
            vietTat: vietTat.trimmingCharacters(in: .whitespaces).isEmpty ? nil : vietTat.trimmingCharacters(in: .whitespaces),
            thuTu: thuTu,
            ngungBan: ngungBan,
            khongLenStore: khongLenStore,
            nhomSanPhamId: nhomSanPhamId,
            tenNhomSanPham: nil,
            storeStatus: nil,
            bienThe: bienTheDtos
        )

        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateSanPham(id: existing.id, body)
        } else {
            result = await APIClient.shared.createSanPham(body)
        }

        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }

    // ── Store ────────────────────────────────────────

    private func runStoreAction(_ action: () async -> ActionResult) async {
        guard let existing else { return }
        _ = existing
        storeActionRunning = true
        let result = await action()
        storeActionRunning = false
        storeActionMessage = result.message ?? (result.success ? "Xong." : "Thất bại.")
        // Nạp lại danh sách để badge Store ở màn ngoài cập nhật theo trạng thái mới (existing?.storeStatus
        // trong sheet này giữ nguyên vì được chụp lúc mở sheet, không tự đổi theo).
        if result.success { onSaved() }
    }

    private func pushToStore() async {
        guard let existing else { return }
        let gia = existing.bienThe.map(\.giaBan).min() ?? 0
        guard gia > 0 else {
            storeActionMessage = "Sản phẩm chưa có giá hợp lệ."
            return
        }
        let req = PushSanPhamToStoreRequest(
            sanPhamId: existing.id, ten: existing.ten.trimmingCharacters(in: .whitespaces),
            finalPrice: gia, tenNhomSanPham: existing.tenNhomSanPham
        )
        await runStoreAction { await APIClient.shared.pushSanPhamToStore(req) }
    }

    private func renameOnStore() async {
        guard let existing else { return }
        await runStoreAction { await APIClient.shared.renameSanPhamOnStore(id: existing.id) }
    }

    private func toggleStoreVisibility(ngungBan: Bool) async {
        guard let existing else { return }
        await runStoreAction { await APIClient.shared.toggleSanPhamStoreVisibility(id: existing.id, ngungBan: ngungBan) }
    }

    private func pushToppingToStore() async {
        guard let existing else { return }
        await runStoreAction { await APIClient.shared.pushToppingToStore(id: existing.id) }
    }

    private func pushSizeXLToStore() async {
        guard let existing else { return }
        await runStoreAction { await APIClient.shared.pushSizeXLToStore(id: existing.id) }
    }
}
