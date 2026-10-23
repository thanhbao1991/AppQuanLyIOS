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
            duyetCongThucMonSheet(mon: mon, model: model)
        }
    }
}
