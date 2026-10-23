import SwiftUI
import UIKit

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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(action: onDelete) {
                Label("Xoá", systemImage: "trash")
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

/// Dùng chung cho màn Công thức và màn Duyệt công thức L/XL. `chuanLines` khác nil = chế độ DUYỆT:
/// hiện định lượng Size Chuẩn để so, nút "Lưu & duyệt" lưu xong thì đánh dấu đã duyệt.
struct CongThucEditSheet: View {
    let existing: CongThucDto?
    let existingLines: [SuDungNguyenLieuDto]
    let allSanPham: [SanPhamDto]
    let allNguyenLieu: [NguyenLieuBanHangDto]
    /// Món + size đã chốt sẵn (màn Duyệt mở món chưa có công thức) — ẩn ô chọn món.
    var bienTheCoDinhId: String? = nil
    var chuanLines: [SuDungNguyenLieuDto]? = nil
    let onSaved: () -> Void

    private var cheDoDuyet: Bool { chuanLines != nil }

    @Environment(\.dismiss) private var dismiss
    @State private var sanPhamBienTheId: String?
    @State private var spDisplayName: String
    @State private var spSearchText = ""
    @State private var lines: [DinhLuongRow]
    @State private var pickingLine: UUID?
    @State private var saving = false
    @State private var errorMessage: String?
    @FocusState private var focusedSoLuongLineId: UUID?
    /// Lưu dở (vài dòng nguyên liệu lỗi) — khoá nút Lưu: `existingLines` của sheet này đã cũ, lưu
    /// lại lần nữa sẽ diff sai (có thể tạo trùng dòng). Phải đóng rồi mở lại công thức.
    @State private var luuDoDang = false

    init(existing: CongThucDto?, existingLines: [SuDungNguyenLieuDto], allSanPham: [SanPhamDto], allNguyenLieu: [NguyenLieuBanHangDto], bienTheCoDinhId: String? = nil, chuanLines: [SuDungNguyenLieuDto]? = nil, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.existingLines = existingLines
        self.allSanPham = allSanPham
        self.allNguyenLieu = allNguyenLieu
        self.bienTheCoDinhId = bienTheCoDinhId
        self.chuanLines = chuanLines
        self.onSaved = onSaved

        let bienTheId = existing?.sanPhamBienTheId ?? bienTheCoDinhId
        _sanPhamBienTheId = State(initialValue: bienTheId)
        if let bienTheId, let sp = allSanPham.first(where: { sp in sp.bienThe.contains { $0.id == bienTheId } }) {
            let bt = sp.bienThe.first { $0.id == bienTheId }
            _spDisplayName = State(initialValue: [sp.ten, bt?.tenBienThe].compactMap { $0 }.joined(separator: "  "))
        } else {
            _spDisplayName = State(initialValue: "")
        }

        let initialLines = existingLines
            .sorted { $0.tenNguyenLieu ?? "" < $1.tenNguyenLieu ?? "" }
            .map { DinhLuongRow(serverId: $0.id, nguyenLieuId: $0.nguyenLieuId, tenNguyenLieu: $0.tenNguyenLieu, donViTinh: $0.donViTinh, soLuong: $0.soLuong) }
        // Size L/XL chưa có công thức: chép sẵn nguyên liệu của Size Chuẩn làm điểm xuất phát (dòng
        // MỚI, chưa có serverId) — nhân viên chỉ việc sửa số.
        let chepTuChuan = (chuanLines ?? [])
            .sorted { $0.tenNguyenLieu ?? "" < $1.tenNguyenLieu ?? "" }
            .map { DinhLuongRow(nguyenLieuId: $0.nguyenLieuId, tenNguyenLieu: $0.tenNguyenLieu, donViTinh: $0.donViTinh, soLuong: $0.soLuong) }
        let lines = initialLines.isEmpty ? chepTuChuan : initialLines
        _lines = State(initialValue: lines.isEmpty ? [DinhLuongRow()] : lines)
    }

    private func soLuongChuan(_ nguyenLieuId: String?) -> Double? {
        guard let nguyenLieuId else { return nil }
        return chuanLines?.first { $0.nguyenLieuId == nguyenLieuId }?.soLuong
    }

    private var matchingSanPham: [SanPhamDto] {
        guard !spSearchText.isEmpty else { return [] }
        return allSanPham.filter { !$0.ngungBan && $0.ten.matchesSearch(spSearchText) }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Sửa công thức có sẵn thì KHÔNG cho đổi món/biến thể — tên món + size lên tiêu đề màn
                // hình. Chỉ màn Thêm mới cần chọn.
                if existing == nil && bienTheCoDinhId == nil {
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
                }

                Section {
                    ForEach($lines) { $line in
                        dinhLuongRow($line)
                    }
                    Button {
                        lines.append(DinhLuongRow())
                    } label: {
                        Label("Thêm nguyên liệu", systemImage: "plus")
                    }
                } header: {
                    Text("Nguyên liệu / định lượng")
                } footer: {
                    if cheDoDuyet {
                        Text("Số nhỏ màu xám dưới tên nguyên liệu là định lượng Size Chuẩn để so.")
                    }
                }

                if let chuanLines {
                    Section("Size Chuẩn (để so)") {
                        if chuanLines.isEmpty {
                            Text("Size Chuẩn chưa có công thức").foregroundColor(.textMuted)
                        }
                        ForEach(chuanLines.sorted { $0.tenNguyenLieu ?? "" < $1.tenNguyenLieu ?? "" }) { dl in
                            HStack {
                                Text(dl.tenNguyenLieu ?? "?").foregroundColor(.textMuted)
                                Spacer()
                                Text(dl.soLuong.formatted()).foregroundColor(.textMuted)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil && bienTheCoDinhId == nil ? "Thêm công thức" : (spDisplayName.isEmpty ? "Sửa công thức" : spDisplayName))
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
                    Text(saving ? "Đang lưu..." : (cheDoDuyet ? "Lưu & duyệt" : "Lưu"))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.wrappedValue.tenNguyenLieu ?? "Chọn nguyên liệu")
                        .foregroundColor(line.wrappedValue.tenNguyenLieu == nil ? .textMuted : .primary)
                    if cheDoDuyet, line.wrappedValue.nguyenLieuId != nil {
                        if let chuan = soLuongChuan(line.wrappedValue.nguyenLieuId) {
                            Text("Chuẩn: \(chuan.formatted())")
                                .font(.caption).foregroundColor(.textMuted)
                        } else {
                            Text("Size Chuẩn không có")
                                .font(.caption).foregroundColor(.textMuted)
                        }
                    }
                }
            }
            Spacer()
            // Nút −/+ sửa nhanh từng 1 đơn vị (không xuống dưới 0). Phải .borderless: trong Form,
            // nhiều Button chung 1 dòng mà để style mặc định thì chạm đâu cũng kích hoạt CẢ dòng.
            Button {
                line.wrappedValue.soLuong = max(0, ((line.wrappedValue.soLuong - 1) * 1000).rounded() / 1000)
            } label: {
                Image(systemName: "minus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .tint(.brandPrimary)
            .disabled(line.wrappedValue.soLuong <= 0)
            TextField("SL", value: line.soLuong, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 60)
                .focused($focusedSoLuongLineId, equals: line.wrappedValue.id)
                .onChange(of: focusedSoLuongLineId) { newValue in
                    guard newValue == line.wrappedValue.id else { return }
                    DispatchQueue.main.async {
                        UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                    }
                }
            Button {
                line.wrappedValue.soLuong = ((line.wrappedValue.soLuong + 1) * 1000).rounded() / 1000
            } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .tint(.brandPrimary)
            // Không hiện đơn vị sau ô SL: tên nguyên liệu đã kèm (ĐVT) theo quy định đặt tên NLBH, và
            // cột đơn vị rộng hẹp khác nhau làm cụm −/SL/+ lệch giữa các dòng.
        }
        // Xoá dòng bằng vuốt trái thay cho nút ✕ cạnh ô số lượng — nút cũ nằm sát ô SL nên rất
        // dễ chạm nhầm. Xoá hết thì chừa lại 1 dòng trống để còn chỗ chọn nguyên liệu.
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                let id = line.wrappedValue.id
                focusedSoLuongLineId = nil
                lines.removeAll { $0.id == id }
                if lines.isEmpty { lines.append(DinhLuongRow()) }
            } label: {
                Label("Xoá", systemImage: "trash")
            }
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
        if cheDoDuyet {
            let duyet = await APIClient.shared.duyetCongThuc(id: congThucId)
            guard duyet.success else {
                // Định lượng đã lưu xong, chỉ chưa đánh dấu duyệt. KHÔNG cho bấm lại ở sheet này:
                // existing/existingLines đã cũ — công thức mới sẽ bị tạo trùng, dòng mới bị thêm trùng.
                luuDoDang = true
                errorMessage = "Đã lưu định lượng nhưng CHƯA duyệt được. Bấm Huỷ rồi mở lại món này để duyệt."
                return
            }
            onSaved()
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
