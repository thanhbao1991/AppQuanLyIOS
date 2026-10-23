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
/// Chuẩn nên trừ tồn kho thấp hơn thực tế. Hiện 10 size CHƯA duyệt vừa bán gần nhất (nhân viên đang
/// pha món đó, xem lại định lượng ngay lúc còn nhớ). Chạm 1 món → so với Size Chuẩn, sửa số rồi
/// "Lưu & duyệt" (POST /api/CongThuc/{id}/duyet ghi NgayDuyet + NguoiDuyet), món kế tiếp tự lên.
struct DuyetCongThucSizeSection: View {
    @ObservedObject var model: DuyetCongThucSizeModel

    private static let soMonHien = 10

    @State private var dangSua: CongThucDuyetSizeDto?

    var body: some View {
        // Backend đã xếp món vừa bán lên đầu. Hết món chưa duyệt (hoặc tải lỗi) thì ẩn cả mục.
        let chuaDuyet = model.chuaDuyet
        if !chuaDuyet.isEmpty {
            Section {
                ForEach(chuaDuyet.prefix(Self.soMonHien)) { item in
                    Button { dangSua = item } label: { row(item) }
                        .buttonStyle(.plain)
                }
            } header: {
                Text("Duyệt công thức L/XL (còn \(chuaDuyet.count))")
            } footer: {
                Text("Món vừa bán lên đầu. Chạm để so với Size Chuẩn, sửa định lượng rồi Lưu & duyệt.")
            }
            .sheet(item: $dangSua) { item in
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

    private func row(_ item: CongThucDuyetSizeDto) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.tenSanPham)  \(item.tenBienThe)")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text([item.lanBanCuoi.map { "bán \(ThongBaoNoiBoFormatting.thoiGian($0))" }, "\(item.soLyBan30Ngay) ly / 30 ngày"]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.textMuted)
            }
            Spacer()
            nhan(item)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func nhan(_ item: CongThucDuyetSizeDto) -> some View {
        let l = model.lines(of: item.congThucId)
        if l.isEmpty {
            Text("Chưa có CT").font(.caption).fontWeight(.bold).foregroundColor(.dangerColor)
        } else if key(l) == key(model.lines(of: item.congThucChuanId)) {
            Text("Giống Chuẩn").font(.caption).fontWeight(.bold).foregroundColor(.orange)
        } else {
            Text("Đã khác Chuẩn").font(.caption).fontWeight(.bold).foregroundColor(.brandPrimary)
        }
    }

    private func key(_ x: [SuDungNguyenLieuDto]) -> [String] {
        x.map { "\($0.nguyenLieuId)|\($0.soLuong)" }.sorted()
    }
}
