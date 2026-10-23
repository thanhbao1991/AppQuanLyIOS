import SwiftUI

/// Bảng sửa định lượng 1 món, mọi size trên cùng 1 bảng (user 23/10):
///     Size Chuẩn | Size L | Size XL
///     Tên nguyên liệu
///     − sl +     | − sl + | − sl +
/// Ô để 0 = size đó không dùng nguyên liệu này. Dùng chung cho mục "Duyệt công thức L/XL" trong
/// Trợ lý ảo (Lưu & duyệt) và màn Menu > Công thức (chỉ Lưu) — 2 màn sửa trông giống hệt nhau.
struct CongThucSizeSheet: View {
    /// 1 cột = 1 size của món.
    struct Cot {
        let ten: String
        let bienTheId: String?
        let congThucId: String?
        /// Lưu xong gọi duyệt công thức size này (chỉ L/XL ở mục Duyệt).
        let canDuyet: Bool
    }

    private struct Dong: Identifiable {
        let id = UUID()
        let nguyenLieuId: String
        let ten: String
        /// Số theo từng cột, cùng thứ tự `cots`.
        var soLuong: [Double]
    }

    let tenSanPham: String
    let allNguyenLieu: [NguyenLieuBanHangDto]
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    private let cots: [Cot]
    /// Dòng nguyên liệu đang có trên server của từng cột — gốc để diff lúc lưu.
    private let linesCu: [[SuDungNguyenLieuDto]]
    @State private var dongs: [Dong]
    @State private var dangChonNguyenLieu = false
    @State private var saving = false
    @State private var errorMessage: String?
    /// Lưu dở — dữ liệu gốc của sheet đã cũ, lưu lại sẽ diff sai (tạo trùng). Phải đóng mở lại.
    @State private var luuDoDang = false

    private var coDuyet: Bool { cots.contains { $0.canDuyet } }

    /// `dienSanTuCotDau`: size chưa có công thức điền sẵn số của cột đầu (Size Chuẩn) làm điểm xuất
    /// phát — chỉ dùng ở mục Duyệt (lưu là tạo luôn công thức). Màn Công thức để 0, không nhập gì thì
    /// không tạo công thức cho size đó.
    init(tenSanPham: String, cots: [Cot], dinhLuongAll: [SuDungNguyenLieuDto], allNguyenLieu: [NguyenLieuBanHangDto],
         dienSanTuCotDau: Bool, onSaved: @escaping () async -> Void) {
        self.tenSanPham = tenSanPham
        self.cots = cots
        self.allNguyenLieu = allNguyenLieu
        self.onSaved = onSaved

        let linesTheoCot = cots.map { cot in
            cot.congThucId.map { id in dinhLuongAll.filter { $0.congThucId == id } } ?? []
        }
        self.linesCu = linesTheoCot
        var thuTu: [String] = []
        var ten: [String: String] = [:]
        for l in linesTheoCot.flatMap({ $0 }) where ten[l.nguyenLieuId] == nil {
            thuTu.append(l.nguyenLieuId)
            ten[l.nguyenLieuId] = l.tenNguyenLieu ?? "?"
        }
        thuTu.sort { (ten[$0] ?? "").localizedStandardCompare(ten[$1] ?? "") == .orderedAscending }
        _dongs = State(initialValue: thuTu.map { nl in
            let dau = linesTheoCot.first?.first { $0.nguyenLieuId == nl }?.soLuong ?? 0
            return Dong(
                nguyenLieuId: nl,
                ten: ten[nl] ?? "?",
                soLuong: linesTheoCot.enumerated().map { i, lines in
                    if dienSanTuCotDau && i > 0 && cots[i].congThucId == nil { return dau }
                    return lines.first { $0.nguyenLieuId == nl }?.soLuong ?? 0
                })
        })
    }

    /// Cột cho 1 món ở màn Công thức: mọi biến thể, size thường (mặc định trước) rồi L, XL.
    static func cots(of sanPham: SanPhamDto, congThucs: [CongThucDto]) -> [Cot] {
        func hang(_ bt: SanPhamBienTheDto) -> Int {
            bt.tenBienThe.hasSuffix(" XL") ? 2 : bt.tenBienThe.hasSuffix(" L") ? 1 : 0
        }
        return sanPham.bienThe
            .sorted {
                if hang($0) != hang($1) { return hang($0) < hang($1) }
                if $0.macDinh != $1.macDinh { return $0.macDinh }
                return $0.tenBienThe.localizedStandardCompare($1.tenBienThe) == .orderedAscending
            }
            .map { bt in
                Cot(ten: bt.tenBienThe, bienTheId: bt.id,
                    congThucId: congThucs.first { $0.sanPhamBienTheId == bt.id }?.id, canDuyet: false)
            }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($dongs) { $dong in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dong.ten).font(.subheadline.weight(.semibold))
                            HStack(spacing: Self.khoangCot) {
                                ForEach(cots.indices, id: \.self) { i in
                                    oSoLuong($dong.soLuong[i], tat: cots[i].bienTheId == nil)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        dangChonNguyenLieu = true
                    } label: {
                        Label("Thêm nguyên liệu", systemImage: "plus")
                    }
                } header: {
                    HStack(spacing: Self.khoangCot) {
                        ForEach(cots.indices, id: \.self) { i in
                            Text(cots[i].ten).frame(maxWidth: .infinity)
                        }
                    }
                } footer: {
                    Text("Để 0 nếu size đó không dùng nguyên liệu này.")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(tenSanPham)
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
                    Text(saving ? "Đang lưu..." : (coDuyet ? "Lưu & duyệt" : "Lưu"))
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)
                .disabled(saving || luuDoDang)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
            .sheet(isPresented: $dangChonNguyenLieu) {
                NguyenLieuBanHangPickerSheet(items: allNguyenLieu) { picked in
                    guard !dongs.contains(where: { $0.nguyenLieuId == picked.id }) else { return }
                    dongs.append(Dong(nguyenLieuId: picked.id, ten: picked.ten,
                                      soLuong: Array(repeating: 0, count: cots.count)))
                }
            }
        }
    }

    /// Khoảng trống giữa 2 cột size — bản đầu để 0, nút + cột này dính nút − cột kế (user 23/10: "sát quá").
    private static let khoangCot: CGFloat = 10

    /// − sl + giống CongThucEditSheet, mỗi size 1 ô nền xám riêng cho tách cột. Nút phải .borderless:
    /// trong List, nhiều Button chung 1 dòng để style mặc định thì chạm đâu cũng kích hoạt cả dòng.
    private func oSoLuong(_ value: Binding<Double>, tat: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                value.wrappedValue = max(0, ((value.wrappedValue - 1) * 1000).rounded() / 1000)
            } label: {
                Image(systemName: "minus.circle.fill").font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(tat || value.wrappedValue <= 0)
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .disabled(tat)
            Button {
                value.wrappedValue = ((value.wrappedValue + 1) * 1000).rounded() / 1000
            } label: {
                Image(systemName: "plus.circle.fill").font(.body)
            }
            .buttonStyle(.borderless)
            .disabled(tat)
        }
        .tint(.brandPrimary)
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
    }

    private func save() async {
        errorMessage = nil
        // Size cần duyệt, hoặc đã có công thức, thì phải còn ít nhất 1 nguyên liệu — muốn bỏ hẳn
        // công thức 1 size thì vuốt xoá ở danh sách, đừng để công thức rỗng (bán không trừ kho).
        for (i, c) in cots.enumerated() where (c.canDuyet || c.congThucId != nil) && !dongs.contains(where: { $0.soLuong[i] > 0 }) {
            errorMessage = "\(c.ten) chưa có nguyên liệu nào > 0."
            return
        }
        saving = true
        defer { saving = false }

        var loi = 0
        for (i, cot) in cots.enumerated() {
            // Size chưa có công thức và cũng không nhập gì thì bỏ qua, khỏi tạo công thức rỗng.
            if !cot.canDuyet && cot.congThucId == nil && !dongs.contains(where: { $0.soLuong[i] > 0 }) { continue }
            guard let congThucId = await damBaoCongThuc(cot) else { loi += 1; continue }
            loi += await luuDinhLuong(congThucId: congThucId, cot: i, cu: linesCu[i])
            if cot.canDuyet, !(await APIClient.shared.duyetCongThuc(id: congThucId)).success { loi += 1 }
        }

        await onSaved()
        if loi > 0 {
            luuDoDang = true
            errorMessage = "Có \(loi) thao tác CHƯA lưu được. Bấm Huỷ rồi mở lại món này để kiểm tra."
            return
        }
        dismiss()
    }

    /// Size chưa có công thức thì tạo mới — trả nil nếu lỗi.
    private func damBaoCongThuc(_ cot: Cot) async -> String? {
        if let id = cot.congThucId { return id }
        guard let bienTheId = cot.bienTheId else { return nil }
        let body = CongThucDto(ten: tenSanPham, sanPhamBienTheId: bienTheId, isDefault: true)
        let result = await APIClient.shared.createCongThuc(body)
        return result.success ? result.id : nil
    }

    /// Đồng bộ dòng nguyên liệu 1 size theo cột `cot` — trả số thao tác lỗi. API Update chỉ sửa
    /// SoLuong (khớp CongThucEditSheet.save).
    private func luuDinhLuong(congThucId: String, cot: Int, cu: [SuDungNguyenLieuDto]) async -> Int {
        var loi = 0
        var conLai = cu
        for dong in dongs {
            let moi = dong.soLuong[cot]
            if let idx = conLai.firstIndex(where: { $0.nguyenLieuId == dong.nguyenLieuId }) {
                let line = conLai.remove(at: idx)
                if moi <= 0 {
                    if !(await APIClient.shared.deleteSuDungNguyenLieu(id: line.id)).success { loi += 1 }
                } else if moi != line.soLuong {
                    let dto = SuDungNguyenLieuDto(id: line.id, congThucId: congThucId, nguyenLieuId: line.nguyenLieuId, soLuong: moi)
                    if !(await APIClient.shared.updateSuDungNguyenLieu(id: line.id, dto)).success { loi += 1 }
                }
            } else if moi > 0 {
                let dto = SuDungNguyenLieuDto(congThucId: congThucId, nguyenLieuId: dong.nguyenLieuId, soLuong: moi)
                if !(await APIClient.shared.createSuDungNguyenLieu(dto)).success { loi += 1 }
            }
        }
        // Dòng trùng nguyên liệu còn sót trong công thức cũ (lỡ nhập trùng) — xoá cho khỏi trừ kho 2 lần.
        for line in conLai {
            if !(await APIClient.shared.deleteSuDungNguyenLieu(id: line.id)).success { loi += 1 }
        }
        return loi
    }
}

/// Mục Duyệt: cột Size Chuẩn (lưu, không cần duyệt) + các size L/XL (lưu & duyệt).
func duyetCongThucMonSheet(mon: MonDuyetCongThuc, model: DuyetCongThucSizeModel) -> CongThucSizeSheet {
    // Biến thể Size Chuẩn = biến thể không phải L/XL của món, ưu tiên mặc định (khớp backend).
    let sizeIds = Set(mon.sizes.map(\.sanPhamBienTheId))
    let chuanBienThe = model.allSanPham.first { $0.id == mon.sanPhamId }?.bienThe
        .filter { !sizeIds.contains($0.id) }
        .sorted { $0.macDinh && !$1.macDinh }
        .first
    let cots = [CongThucSizeSheet.Cot(ten: "Size Chuẩn", bienTheId: chuanBienThe?.id, congThucId: mon.congThucChuanId, canDuyet: false)]
        + mon.sizes.map { CongThucSizeSheet.Cot(ten: $0.tenBienThe, bienTheId: $0.sanPhamBienTheId, congThucId: $0.congThucId, canDuyet: true) }
    return CongThucSizeSheet(tenSanPham: mon.tenSanPham, cots: cots, dinhLuongAll: model.dinhLuongAll,
                             allNguyenLieu: model.allNguyenLieu, dienSanTuCotDau: true,
                             onSaved: { await model.load() })
}
