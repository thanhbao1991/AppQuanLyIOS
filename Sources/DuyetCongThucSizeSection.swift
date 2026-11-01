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

/// Dữ liệu duyệt công thức L/XL — MainTabView giữ (@StateObject) làm cổng vào tab Kê/Tiền/Chi/Việc.
/// Từng là mục trong Trợ lý ảo, đã bỏ khỏi đó (user 01/11/2026).
@MainActor
final class DuyetCongThucSizeModel: ObservableObject {
    @Published var items: [CongThucDuyetSizeDto] = []
    @Published var congThucs: [CongThucDto] = []
    @Published var dinhLuongAll: [SuDungNguyenLieuDto] = []
    @Published var allSanPham: [SanPhamDto] = []
    @Published var allNguyenLieu: [NguyenLieuBanHangDto] = []
    @Published var dangSua: MonDuyetCongThuc?
    /// Vừa bấm "Duyệt sau" (đã lưu, chưa duyệt) — cổng tab vẫn cho vào. MainTabView đọc xong tự đặt lại false.
    var duyetSau = false

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

    /// Trả false nếu tải lỗi (giữ bộ cũ).
    @discardableResult
    func load() async -> Bool {
        async let dsTask = APIClient.shared.getCongThucDuyetSizeOrNil()
        async let ctTask = APIClient.shared.getCongThucListOrNil()
        async let dlTask = APIClient.shared.getSuDungNguyenLieuListOrNil()
        async let spTask = APIClient.shared.getSanPhamListOrNil(includeNgungBan: true)
        async let nlTask = APIClient.shared.getNguyenLieuBanHangOrNil()
        let (ds, ct, dl, sp, nl) = await (dsTask, ctTask, dlTask, spTask, nlTask)
        // Phải về đủ cả bộ mới áp dụng — cùng lý do CongThucListView.load: thiếu dinhLuongAll mà vẫn
        // mở sửa rồi Lưu sẽ tạo trùng dòng nguyên liệu (trừ tồn kho gấp đôi). Lỗi thì giữ bộ cũ.
        guard let ds, let ct, let dl, let sp, let nl else { return false }
        items = ds
        congThucs = ct
        dinhLuongAll = dl
        allSanPham = sp
        allNguyenLieu = nl.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
        return true
    }
}

