import SwiftUI

/// Quản trị Công thức bán hàng (Menu > Cấu hình) — mỗi biến thể sản phẩm gắn ĐÚNG 1 công thức gồm
/// nhiều dòng nguyên liệu + số lượng, dùng để tự động trừ tồn kho khi bán (SanPhamBienThe →
/// CongThucBanHang → DinhLuongBanHang). Cổng vào DUY NHẤT để sửa công thức: Desktop đã ẩn hẳn màn
/// này từ trước (CongThucWindow, "chỉ nhập liệu bán hàng"), khớp chủ trương "chỉ AppQuanLyIOS có
/// quyền CRUD nguyên liệu/công thức, Desktop chỉ còn code chết" (2026-09-22).
/// GET /api/CongThuc + /api/SuDungNguyenLieu không join sẵn tên sản phẩm/nguyên liệu — tự ghép ở
/// client như Desktop (CongThucWindow.EnrichCongThuc).
struct CongThucListView: View {
    @State private var congThucs: [CongThucDto] = []
    @State private var dinhLuongAll: [SuDungNguyenLieuDto] = []
    @State private var allSanPham: [SanPhamDto] = []
    @State private var allNguyenLieu: [NguyenLieuBanHangDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editing: CongThucRow?
    @State private var deleting: CongThucRow?
    @State private var loadFailed = false

    struct CongThucRow: Identifiable {
        let dto: CongThucDto
        let tenSanPham: String?
        let tenBienThe: String?
        let soNguyenLieu: Int
        var id: String { dto.id }
    }

    private var rows: [CongThucRow] {
        var out = congThucs.map { ct -> CongThucRow in
            var tenSanPham: String?
            var tenBienThe: String?
            for sp in allSanPham {
                if let bt = sp.bienThe.first(where: { $0.id == ct.sanPhamBienTheId }) {
                    tenSanPham = sp.ten
                    tenBienThe = bt.tenBienThe
                    break
                }
            }
            let soNguyenLieu = dinhLuongAll.filter { $0.congThucId == ct.id }.count
            return CongThucRow(dto: ct, tenSanPham: tenSanPham, tenBienThe: tenBienThe, soNguyenLieu: soNguyenLieu)
        }
        out.sort { ($0.tenSanPham ?? "").localizedStandardCompare($1.tenSanPham ?? "") == .orderedAscending }
        guard !searchText.isEmpty else { return out }
        return out.filter { anyMatchesSearch(searchText, $0.tenSanPham, $0.tenBienThe) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm sản phẩm, biến thể...")

            if !hasLoaded {
                fullScreenLoading()
            } else {
                if loadFailed {
                    ThongKeLoadErrorBanner(text: "Chưa tải được công thức") { Task { await load() } }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                List {
                    ForEach(rows) { row in
                        CongThucRowView(row: row) {
                            editing = row
                        } onDelete: {
                            deleting = row
                        }
                    }
                }
                .listStyle(.plain)
                .softScrollEdgeTop()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Công thức")
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
        .confirmDelete(
            $deleting,
            name: { [$0.tenSanPham, $0.tenBienThe].compactMap { $0 }.joined(separator: " ") },
            note: "Xoá cả \(deleting?.soNguyenLieu ?? 0) dòng nguyên liệu — món này sẽ KHÔNG còn tự trừ tồn kho khi bán.",
            perform: { await delete($0.dto) },
            onDone: load
        )
        .sheet(isPresented: $showAdd) {
            CongThucEditSheet(existing: nil, existingLines: [], allSanPham: allSanPham, allNguyenLieu: allNguyenLieu) {
                Task { await load() }
            }
        }
        .sheet(item: $editing) { row in
            CongThucEditSheet(
                existing: row.dto,
                existingLines: dinhLuongAll.filter { $0.congThucId == row.dto.id },
                allSanPham: allSanPham,
                allNguyenLieu: allNguyenLieu
            ) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        async let ctTask = APIClient.shared.getCongThucListOrNil()
        async let dlTask = APIClient.shared.getSuDungNguyenLieuListOrNil()
        async let spTask = APIClient.shared.getSanPhamListOrNil(includeNgungBan: true)
        async let nlTask = APIClient.shared.getNguyenLieuBanHangOrNil()
        let (ct, dl, sp, nl) = await (ctTask, dlTask, spTask, nlTask)
        // 4 danh sách phải về ĐỦ CẢ BỘ mới áp dụng — thiếu 1 cái mà vẫn hiện thì sai nguy hiểm: thiếu
        // dinhLuongAll thì mọi công thức hiện "0 nguyên liệu", mở ra sửa rồi Lưu sẽ TẠO TRÙNG toàn bộ
        // dòng nguyên liệu (trừ tồn kho gấp đôi); thiếu allSanPham thì mọi dòng báo "Biến thể không
        // còn tồn tại". Lỗi thì giữ nguyên bộ đang có + hiện banner thử lại.
        if let ct, let dl, let sp, let nl {
            congThucs = ct
            dinhLuongAll = dl
            allSanPham = sp
            allNguyenLieu = nl.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
            loadFailed = false
        } else {
            loadFailed = true
        }
        hasLoaded = true
    }

    /// 1 lệnh gọi duy nhất: backend (CongThucService.DeleteAsync) xoá công thức KÈM mọi dòng nguyên
    /// liệu con trong cùng 1 transaction — hoặc xoá hết, hoặc không xoá gì. Trước đây app phải tự xoá
    /// từng dòng rồi mới xoá công thức (FK Restrict), rớt mạng giữa chừng là công thức nằm lại với
    /// một phần nguyên liệu.
    private func delete(_ dto: CongThucDto) async -> ActionResult {
        await APIClient.shared.deleteCongThuc(id: dto.id)
    }
}

private struct CongThucRowView: View {
    let row: CongThucListView.CongThucRow
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text([row.tenSanPham, row.tenBienThe].compactMap { $0 }.joined(separator: "  "))
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    if row.tenSanPham == nil {
                        Text("Biến thể không còn tồn tại")
                            .font(.caption2).foregroundColor(.dangerColor)
                    }
                }
                Spacer()
                Text("\(row.soNguyenLieu) nguyên liệu")
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(row.soNguyenLieu == 0 ? .dangerColor : .brandPrimary)
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
            Button(action: onDelete) {
                EmojiLabel("Xoá", "🗑️")
            }
            .tint(.dangerColor)
        }
    }
}

/// Danh tính riêng cho SwiftUI ForEach (localId luôn duy nhất) — khớp lý do BienTheEditRow
/// (SanPhamListView) tách localId khỏi serverId: nhiều dòng MỚI thêm cùng lúc đều có serverId rỗng
/// giống hệt nhau.
private struct DinhLuongRow: Identifiable {
    let localId = UUID()
    var serverId: String = "00000000-0000-0000-0000-000000000000"
    var nguyenLieuId: String?
    var tenNguyenLieu: String?
    var donViTinh: String?
    var soLuong: Double = 0
    var id: UUID { localId }
}

private struct CongThucEditSheet: View {
    let existing: CongThucDto?
    let existingLines: [SuDungNguyenLieuDto]
    let allSanPham: [SanPhamDto]
    let allNguyenLieu: [NguyenLieuBanHangDto]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sanPhamBienTheId: String?
    @State private var spDisplayName: String
    @State private var spSearchText = ""
    @State private var lines: [DinhLuongRow]
    @State private var pickingLine: UUID?
    @State private var saving = false
    @State private var errorMessage: String?
    /// Lưu dở (vài dòng nguyên liệu lỗi) — khoá nút Lưu: `existingLines` của sheet này đã cũ, lưu
    /// lại lần nữa sẽ diff sai (có thể tạo trùng dòng). Phải đóng rồi mở lại công thức.
    @State private var luuDoDang = false

    init(existing: CongThucDto?, existingLines: [SuDungNguyenLieuDto], allSanPham: [SanPhamDto], allNguyenLieu: [NguyenLieuBanHangDto], onSaved: @escaping () -> Void) {
        self.existing = existing
        self.existingLines = existingLines
        self.allSanPham = allSanPham
        self.allNguyenLieu = allNguyenLieu
        self.onSaved = onSaved

        _sanPhamBienTheId = State(initialValue: existing?.sanPhamBienTheId)
        if let existing, let sp = allSanPham.first(where: { sp in sp.bienThe.contains { $0.id == existing.sanPhamBienTheId } }) {
            let bt = sp.bienThe.first { $0.id == existing.sanPhamBienTheId }
            _spDisplayName = State(initialValue: [sp.ten, bt?.tenBienThe].compactMap { $0 }.joined(separator: "  "))
        } else {
            _spDisplayName = State(initialValue: "")
        }

        let initialLines = existingLines
            .sorted { $0.tenNguyenLieu ?? "" < $1.tenNguyenLieu ?? "" }
            .map { DinhLuongRow(serverId: $0.id, nguyenLieuId: $0.nguyenLieuId, tenNguyenLieu: $0.tenNguyenLieu, donViTinh: $0.donViTinh, soLuong: $0.soLuong) }
        _lines = State(initialValue: initialLines.isEmpty ? [DinhLuongRow()] : initialLines)
    }

    private var matchingSanPham: [SanPhamDto] {
        guard !spSearchText.isEmpty else { return [] }
        return allSanPham.filter { !$0.ngungBan && $0.ten.matchesSearch(spSearchText) }
    }

    var body: some View {
        NavigationStack {
            Form {
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
                                    spDisplayName = [sp.ten, bt.tenBienThe].joined(separator: "  ")
                                    spSearchText = ""
                                } label: {
                                    Text([sp.ten, bt.tenBienThe].joined(separator: "  ")).foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }

                Section {
                    ForEach($lines) { $line in
                        dinhLuongRow($line)
                    }
                    Button {
                        lines.append(DinhLuongRow())
                    } label: {
                        EmojiLabel("Thêm nguyên liệu", "➕")
                    }
                } header: {
                    Text("Nguyên liệu / định lượng")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm công thức" : "Sửa công thức")
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
                .disabled(sanPhamBienTheId == nil || saving || luuDoDang)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
            .sheet(item: $pickingLine) { lineId in
                NguyenLieuBanHangPickerSheet(items: allNguyenLieu) { picked in
                    if let idx = lines.firstIndex(where: { $0.id == lineId }) {
                        lines[idx].nguyenLieuId = picked.id
                        lines[idx].tenNguyenLieu = picked.ten
                        lines[idx].donViTinh = picked.donViTinh
                    }
                }
            }
        }
    }

    private func dinhLuongRow(_ line: Binding<DinhLuongRow>) -> some View {
        HStack {
            Button {
                pickingLine = line.wrappedValue.id
            } label: {
                Text(line.wrappedValue.tenNguyenLieu ?? "Chọn nguyên liệu")
                    .foregroundColor(line.wrappedValue.tenNguyenLieu == nil ? .textMuted : .primary)
            }
            Spacer()
            TextField("SL", value: line.soLuong, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            if let dvt = line.wrappedValue.donViTinh {
                Text(dvt).font(.caption).foregroundColor(.textMuted)
            }
            Button {
                if lines.count > 1 { lines.removeAll { $0.id == line.wrappedValue.id } }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.dangerColor)
            }
            .buttonStyle(.plain)
        }
    }

    private func save() async {
        guard let sanPhamBienTheId else { return }
        errorMessage = nil

        let usedLines = lines.filter { $0.nguyenLieuId != nil && $0.soLuong > 0 }
        guard !usedLines.isEmpty else {
            errorMessage = "Thêm ít nhất 1 nguyên liệu với số lượng > 0."
            return
        }
        if Set(usedLines.map { $0.nguyenLieuId }).count != usedLines.count {
            errorMessage = "Không được chọn trùng nguyên liệu trong 1 công thức."
            return
        }

        saving = true
        defer { saving = false }

        let sp = allSanPham.first { $0.bienThe.contains { $0.id == sanPhamBienTheId } }

        var congThucId: String
        if let existing {
            congThucId = existing.id
            let body = CongThucDto(id: existing.id, ten: sp?.ten ?? existing.ten, sanPhamBienTheId: sanPhamBienTheId, loai: existing.loai, isDefault: true)
            let result = await APIClient.shared.updateCongThuc(id: existing.id, body)
            guard result.success else {
                errorMessage = result.message ?? "Không lưu được."
                return
            }
        } else {
            let body = CongThucDto(ten: sp?.ten ?? "", sanPhamBienTheId: sanPhamBienTheId, isDefault: true)
            let result = await APIClient.shared.createCongThuc(body)
            guard result.success, let newId = result.id else {
                errorMessage = result.message ?? "Không lưu được."
                return
            }
            congThucId = newId
        }

        // Đồng bộ dòng nguyên liệu: sửa dòng còn giữ, xoá dòng bị bỏ, thêm dòng mới — khớp cách
        // Desktop CongThucWindow.SaveBtn_Click diff theo Id (API Update KHÔNG hỗ trợ đổi
        // NguyenLieuId, chỉ sửa SoLuong, nên đổi nguyên liệu của 1 dòng phải xoá rồi tạo lại).
        let keepServerIds = Set(usedLines.map { $0.serverId }.filter { $0 != "00000000-0000-0000-0000-000000000000" })
        let originalIds = Set(existingLines.map { $0.id })

        var loiDong = 0
        for line in usedLines {
            guard let nguyenLieuId = line.nguyenLieuId else { continue }
            if line.serverId != "00000000-0000-0000-0000-000000000000",
               let original = existingLines.first(where: { $0.id == line.serverId }),
               original.nguyenLieuId == nguyenLieuId {
                if original.soLuong != line.soLuong {
                    let updDto = SuDungNguyenLieuDto(id: line.serverId, congThucId: congThucId, nguyenLieuId: nguyenLieuId, soLuong: line.soLuong)
                    if !(await APIClient.shared.updateSuDungNguyenLieu(id: line.serverId, updDto)).success { loiDong += 1 }
                }
                continue
            }
            if line.serverId != "00000000-0000-0000-0000-000000000000" {
                if !(await APIClient.shared.deleteSuDungNguyenLieu(id: line.serverId)).success { loiDong += 1 }
            }
            let newDto = SuDungNguyenLieuDto(congThucId: congThucId, nguyenLieuId: nguyenLieuId, soLuong: line.soLuong)
            if !(await APIClient.shared.createSuDungNguyenLieu(newDto)).success { loiDong += 1 }
        }

        for oldId in originalIds.subtracting(keepServerIds) {
            if !(await APIClient.shared.deleteSuDungNguyenLieu(id: oldId)).success { loiDong += 1 }
        }

        onSaved()
        // Trước đây bỏ qua kết quả từng dòng rồi đóng sheet như đã lưu xong — công thức thiếu/thừa
        // dòng mà không ai biết.
        if loiDong > 0 {
            luuDoDang = true
            errorMessage = "Có \(loiDong) thao tác trên dòng nguyên liệu CHƯA lưu được. Bấm Huỷ rồi mở lại công thức này để kiểm tra và sửa lại."
            return
        }
        dismiss()
    }
}

extension UUID: Identifiable {
    public var id: UUID { self }
}

private struct NguyenLieuBanHangPickerSheet: View {
    let items: [NguyenLieuBanHangDto]
    let onPick: (NguyenLieuBanHangDto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filtered: [NguyenLieuBanHangDto] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.ten.matchesSearch(searchText) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm nguyên liệu...")
                List(filtered) { item in
                    Button {
                        onPick(item)
                        dismiss()
                    } label: {
                        HStack {
                            Text(item.ten).foregroundColor(.primary)
                            Spacer()
                            if let dvt = item.donViTinh {
                                Text(dvt).font(.caption).foregroundColor(.textMuted)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .softScrollEdgeTop()
            }
            .navigationTitle("Chọn nguyên liệu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
        }
    }
}
