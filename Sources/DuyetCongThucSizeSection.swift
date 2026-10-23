import SwiftUI

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
    @Published var dangSua: CongThucDuyetSizeDto?

    var chuaDuyet: [CongThucDuyetSizeDto] { items.filter { $0.ngayDuyet == nil } }

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
/// Chuẩn nên trừ tồn kho thấp hơn thực tế. Hiện 5 size CHƯA duyệt vừa bán gần nhất, mỗi dòng chỉ
/// tên + size (user 23/10). Chạm → `model.dangSua` → TroLyView mở CongThucEditSheet chế độ duyệt.
struct DuyetCongThucSizeSection: View {
    @ObservedObject var model: DuyetCongThucSizeModel

    private static let soMonHien = 5

    var body: some View {
        // Backend đã xếp món vừa bán lên đầu. Hết món chưa duyệt (hoặc tải lỗi) thì ẩn cả mục.
        let chuaDuyet = model.chuaDuyet
        if !chuaDuyet.isEmpty {
            Section("Duyệt công thức L/XL (còn \(chuaDuyet.count))") {
                ForEach(chuaDuyet.prefix(Self.soMonHien)) { item in
                    Button { model.dangSua = item } label: {
                        Text("\(item.tenSanPham)  \(item.tenBienThe)")
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
        sheet(item: Binding(get: { model.dangSua }, set: { model.dangSua = $0 })) { item in
            CongThucEditSheet(
                existing: item.congThucId.flatMap { id in model.congThucs.first { $0.id == id } },
                existingLines: model.lines(of: item.congThucId),
                allSanPham: model.allSanPham,
                allNguyenLieu: model.allNguyenLieu,
                bienTheCoDinhId: item.sanPhamBienTheId,
                chuanLines: model.lines(of: item.congThucChuanId)
            ) {
                Task { await model.load() }
            }
        }
    }
}
