import SwiftUI

/// 1 món cần duyệt — gom size L + XL cùng món để sửa chung trên 1 bảng (Chuẩn | L | XL).
struct MonDuyetCongThuc: Identifiable {
    let sanPhamId: String
    let tenSanPham: String
    /// Mọi size L/XL của món (kể cả size đã duyệt), L trước XL.
    let sizes: [CongThucDuyetSizeDto]
    let congThucChuanId: String?
    var id: String { sanPhamId }

    var sizeChuaDuyet: [CongThucDuyetSizeDto] { sizes.filter { $0.ngayDuyet == nil } }

    /// "Size XL" → "XL" cho tiêu đề cột / dòng danh sách.
    static func tenNgan(_ tenBienThe: String) -> String {
        tenBienThe.split(separator: " ").last.map(String.init) ?? tenBienThe
    }
}

/// Dữ liệu mục "Duyệt công thức L/XL" — TroLyView giữ (@StateObject) và gọi `load()` trong taiLai.
/// KHÔNG để Section tự `.task`: lúc chưa có dữ liệu Section không vẽ dòng nào trong List, SwiftUI
/// không chạy `.task` của view rỗng → không bao giờ tải (gặp thật 23/10, build đầu không gọi API nào).
@MainActor
final class DuyetCongThucSizeModel: ObservableObject {
    @Published var items: [CongThucDuyetSizeDto] = []
    @Published var congThucs: [CongThucDto] = []
    @Published var dinhLuongAll: [SuDungNguyenLieuDto] = []
    @Published var allSanPham: [SanPhamDto] = []
    @Published var allNguyenLieu: [NguyenLieuBanHangDto] = []
    @Published var dangSua: MonDuyetCongThuc?

    /// Món còn size chưa duyệt, giữ thứ tự backend (vừa bán lên đầu).
    var monChuaDuyet: [MonDuyetCongThuc] {
        var thuTu: [String] = []
        var theoMon: [String: [CongThucDuyetSizeDto]] = [:]
        for item in items {
            if theoMon[item.sanPhamId] == nil { thuTu.append(item.sanPhamId) }
            theoMon[item.sanPhamId, default: []].append(item)
        }
        return thuTu.compactMap { id in
            guard let sizes = theoMon[id], sizes.contains(where: { $0.ngayDuyet == nil }) else { return nil }
            let sapXep = sizes.sorted { $0.tenBienThe.count < $1.tenBienThe.count }
            return MonDuyetCongThuc(sanPhamId: id, tenSanPham: sizes[0].tenSanPham, sizes: sapXep,
                                    congThucChuanId: sizes[0].congThucChuanId)
        }
    }

    func lines(of congThucId: String?) -> [SuDungNguyenLieuDto] {
        guard let congThucId else { return [] }
        return dinhLuongAll.filter { $0.congThucId == congThucId }
    }

    func load() async {
        async let dsTask = APIClient.shared.getCongThucDuyetSizeOrNil()
        async let ctTask = APIClient.shared.getCongThucListOrNil()
        async let dlTask = APIClient.shared.getSuDungNguyenLieuListOrNil()
        async let spTask = APIClient.shared.getSanPhamListOrNil(includeNgungBan: true)
        async let nlTask = APIClient.shared.getNguyenLieuBanHangOrNil()
        let (ds, ct, dl, sp, nl) = await (dsTask, ctTask, dlTask, spTask, nlTask)
        // Phải về đủ cả bộ mới áp dụng — cùng lý do CongThucListView.load: thiếu dinhLuongAll mà vẫn
        // mở sửa rồi Lưu sẽ tạo trùng dòng nguyên liệu (trừ tồn kho gấp đôi). Lỗi thì giữ bộ cũ.
        guard let ds, let ct, let dl, let sp, let nl else { return }
        items = ds
        congThucs = ct
        dinhLuongAll = dl
        allSanPham = sp
        allNguyenLieu = nl.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
    }
}

/// Mục "Duyệt công thức L/XL" trong Trợ lý ảo — đa số công thức L/XL đang chép y nguyên Size
/// Chuẩn nên trừ tồn kho thấp hơn thực tế. Hiện 5 món còn size CHƯA duyệt, vừa bán gần nhất, mỗi
/// dòng chỉ tên + size (user 23/10). Chạm → `model.dangSua` → TroLyView mở bảng Chuẩn | L | XL.
struct DuyetCongThucSizeSection: View {
    @ObservedObject var model: DuyetCongThucSizeModel

    private static let soMonHien = 5

    var body: some View {
        // Hết món chưa duyệt (hoặc tải lỗi) thì ẩn cả mục.
        let mons = model.monChuaDuyet
        if !mons.isEmpty {
            Section("Duyệt công thức L/XL (còn \(mons.count) món)") {
                ForEach(mons.prefix(Self.soMonHien)) { mon in
                    Button { model.dangSua = mon } label: {
                        Text("\(mon.tenSanPham)  \(mon.sizeChuaDuyet.map { MonDuyetCongThuc.tenNgan($0.tenBienThe) }.joined(separator: " · "))")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

extension View {
    /// Gắn ở cấp màn hình (TroLyView), KHÔNG gắn trong Section của List: sheet gắn vào nội dung List
    /// bị SwiftUI đóng ngay khi List vẽ lại (gặp thật 23/10 — mở sửa rồi tự đóng).
    func duyetCongThucSheet(_ model: DuyetCongThucSizeModel) -> some View {
        sheet(item: Binding(get: { model.dangSua }, set: { model.dangSua = $0 })) { mon in
            DuyetCongThucMonSheet(mon: mon, model: model)
        }
    }
}

/// Bảng sửa định lượng 1 món: mỗi dòng 1 nguyên liệu, cột Chuẩn (chỉ xem) | L | XL (sửa được).
/// Ô để 0 = size đó không dùng nguyên liệu này. "Lưu & duyệt" lưu cả L và XL rồi duyệt cả hai.
struct DuyetCongThucMonSheet: View {
    let mon: MonDuyetCongThuc
    let model: DuyetCongThucSizeModel

    private struct Dong: Identifiable {
        let id = UUID()
        let nguyenLieuId: String
        let ten: String
        let chuan: Double?
        /// Số theo từng size, cùng thứ tự `mon.sizes`.
        var soLuong: [Double]
    }

    @Environment(\.dismiss) private var dismiss
    @State private var dongs: [Dong]
    @State private var dangChonNguyenLieu = false
    @State private var saving = false
    @State private var errorMessage: String?
    /// Lưu dở — dữ liệu gốc của sheet đã cũ, lưu lại sẽ diff sai (tạo trùng). Phải đóng mở lại.
    @State private var luuDoDang = false

    private static let rongCot: CGFloat = 58

    init(mon: MonDuyetCongThuc, model: DuyetCongThucSizeModel) {
        self.mon = mon
        self.model = model

        let chuanLines = model.lines(of: mon.congThucChuanId)
        let sizeLines = mon.sizes.map { model.lines(of: $0.congThucId) }
        var thuTu: [String] = []
        var ten: [String: String] = [:]
        for l in chuanLines + sizeLines.flatMap({ $0 }) where ten[l.nguyenLieuId] == nil {
            thuTu.append(l.nguyenLieuId)
            ten[l.nguyenLieuId] = l.tenNguyenLieu ?? "?"
        }
        thuTu.sort { (ten[$0] ?? "").localizedStandardCompare(ten[$1] ?? "") == .orderedAscending }
        _dongs = State(initialValue: thuTu.map { nl in
            let chuan = chuanLines.first { $0.nguyenLieuId == nl }?.soLuong
            return Dong(
                nguyenLieuId: nl,
                ten: ten[nl] ?? "?",
                chuan: chuan,
                // Size chưa có công thức: điền sẵn số Size Chuẩn làm điểm xuất phát.
                soLuong: sizeLines.map { lines in
                    lines.isEmpty ? (chuan ?? 0) : (lines.first { $0.nguyenLieuId == nl }?.soLuong ?? 0)
                })
        })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($dongs) { $dong in
                        HStack(spacing: 6) {
                            Text(dong.ten).font(.subheadline).lineLimit(2)
                            Spacer(minLength: 4)
                            Text(dong.chuan.map { $0.formatted() } ?? "–")
                                .font(.subheadline).foregroundColor(.textMuted)
                                .frame(width: Self.rongCot)
                            ForEach(mon.sizes.indices, id: \.self) { i in
                                TextField("0", value: $dong.soLuong[i], format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.center)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .frame(width: Self.rongCot)
                            }
                        }
                    }
                    Button {
                        dangChonNguyenLieu = true
                    } label: {
                        Label("Thêm nguyên liệu", systemImage: "plus")
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Nguyên liệu")
                        Spacer(minLength: 4)
                        Text("Chuẩn").frame(width: Self.rongCot)
                        ForEach(mon.sizes) { s in
                            Text(MonDuyetCongThuc.tenNgan(s.tenBienThe)).frame(width: Self.rongCot)
                        }
                    }
                } footer: {
                    Text("Để 0 nếu size đó không dùng nguyên liệu này.")
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(mon.tenSanPham)
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
                    Text(saving ? "Đang lưu..." : "Lưu & duyệt")
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
                NguyenLieuBanHangPickerSheet(items: model.allNguyenLieu) { picked in
                    guard !dongs.contains(where: { $0.nguyenLieuId == picked.id }) else { return }
                    dongs.append(Dong(nguyenLieuId: picked.id, ten: picked.ten, chuan: nil,
                                      soLuong: Array(repeating: 0, count: mon.sizes.count)))
                }
            }
        }
    }

    private func save() async {
        errorMessage = nil
        for (i, s) in mon.sizes.enumerated() where !dongs.contains(where: { $0.soLuong[i] > 0 }) {
            errorMessage = "\(s.tenBienThe) chưa có nguyên liệu nào > 0."
            return
        }
        saving = true
        defer { saving = false }

        var loi = 0
        for (i, size) in mon.sizes.enumerated() {
            guard let congThucId = await damBaoCongThuc(size) else { loi += 1; continue }
            loi += await luuDinhLuong(congThucId: congThucId, cot: i, cu: model.lines(of: size.congThucId))
            if !(await APIClient.shared.duyetCongThuc(id: congThucId)).success { loi += 1 }
        }

        await model.load()
        if loi > 0 {
            luuDoDang = true
            errorMessage = "Có \(loi) thao tác CHƯA lưu được. Bấm Huỷ rồi mở lại món này để kiểm tra."
            return
        }
        dismiss()
    }

    /// Size chưa có công thức thì tạo mới — trả nil nếu lỗi.
    private func damBaoCongThuc(_ size: CongThucDuyetSizeDto) async -> String? {
        if let id = size.congThucId { return id }
        let body = CongThucDto(ten: mon.tenSanPham, sanPhamBienTheId: size.sanPhamBienTheId, isDefault: true)
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
