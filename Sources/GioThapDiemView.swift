import Charts
import SwiftUI

/// Tên hiển thị 7 thứ trong tuần theo thang ISO dùng ở Voucher.ThuTrongTuan (1=Thứ Hai...7=Chủ Nhật)
/// — gom về đây để VoucherListView và GioThapDiemView dùng chung, không lệch nhãn.
let tenThuTrongTuan: [Int: String] = [1: "Thứ Hai", 2: "Thứ Ba", 3: "Thứ Tư", 4: "Thứ Năm", 5: "Thứ Sáu", 6: "Thứ Bảy", 7: "Chủ Nhật"]
let tenThuNganGon: [Int: String] = [1: "T2", 2: "T3", 3: "T4", 4: "T5", 5: "T6", 6: "T7", 7: "CN"]

/// Phân tích DOANH THU theo giờ VÀ theo thứ trong tuần (30 ngày gần đây) để staff TỰ NHẬN RA khung
/// giờ + thứ vắng khách thật của quán, thay vì đoán mò khi cấu hình voucher
/// DieuKien=KhungGioThapDiem — xem GET /api/ThongKe/phan-bo-don-theo-gio và
/// /phan-bo-doanh-thu-theo-thu. Màn CHỈ hiện biểu đồ + gợi ý (2026-09-15 bỏ hẳn phần chỉnh tay bằng
/// Stepper theo yêu cầu — xem gợi ý là đủ, không cần chỉnh thủ công ở đây, tinh chỉnh lại thì làm
/// ngay trong form voucher). Khi mở từ form voucher (onChon != nil) có nút "Dùng gợi ý này" áp
/// thẳng cả giờ lẫn thứ vào form đang sửa; mở độc lập từ Công cụ thì chỉ xem tham khảo.
struct GioThapDiemView: View {
    var onChon: ((_ gioBatDau: Int, _ gioKetThuc: Int, _ thuTrongTuan: Set<Int>) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var itemsGio: [PhanBoDonTheoGioItemDto] = []
    @State private var itemsThu: [PhanBoDoanhThuTheoThuItemDto] = []
    @State private var config: GamificationConfigDto?
    @State private var loading = true

    /// Chỉ giờ trong khung mở bán — bỏ hẳn cột giờ đóng cửa khỏi biểu đồ thay vì làm mờ, đỡ rối mắt.
    private var itemsGioMoCua: [PhanBoDonTheoGioItemDto] {
        let mo = config?.gioMoCua ?? 0
        let dong = config?.gioDongCua ?? 24
        return itemsGio.filter { $0.gio >= mo && $0.gio < dong }
    }

    /// Khung 2 giờ liên tiếp trong giờ mở bán có tổng doanh thu thấp nhất.
    private var goiYGio: (batDau: Int, ketThuc: Int)? {
        let sorted = itemsGioMoCua.sorted { $0.gio < $1.gio }
        var best: (batDau: Int, ketThuc: Int, tong: Double)?
        for i in 0..<sorted.count {
            let j = i + 1
            guard j < sorted.count else { continue }
            let tong = sorted[i].doanhThu + sorted[j].doanhThu
            if best == nil || tong < best!.tong {
                best = (sorted[i].gio, sorted[j].gio + 1, tong)
            }
        }
        guard let best else { return nil }
        return (best.batDau, best.ketThuc)
    }

    /// 2 thứ trong tuần có doanh thu thấp nhất — cùng cỡ "2 đơn vị" với gợi ý giờ cho nhất quán.
    private var goiYThu: Set<Int> {
        Set(itemsThu.sorted { $0.doanhThu < $1.doanhThu }.prefix(2).map(\.thu))
    }

    var body: some View {
        List {
            if loading {
                Section {
                    fullScreenLoading()
                }
            } else if itemsGio.allSatisfy({ $0.doanhThu == 0 }) {
                Section {
                    Text("Chưa có đủ dữ liệu đơn hàng 30 ngày gần đây để phân tích.")
                        .foregroundColor(.textMuted)
                }
            } else {
                // 18/10/2026 (BaoCaoUI): kết luận lên đầu bằng chữ to, biểu đồ bên dưới làm bằng chứng.
                if let goiYGio {
                    Section {
                        TheKetLuan(
                            mucDo: .trungTinh,
                            tieuDe: "Vắng nhất: \(goiYGio.batDau)h–\(goiYGio.ketThuc)h",
                            moTa: goiYThu.isEmpty ? "30 ngày gần đây" :
                                goiYThu.sorted().compactMap { tenThuTrongTuan[$0] }.joined(separator: ", ") + " · 30 ngày gần đây")
                    }
                }
                Section("Doanh thu theo giờ (trong giờ mở bán)") {
                    Chart(itemsGioMoCua) { item in
                        let trongGoiY = goiYGio.map { item.gio >= $0.batDau && item.gio < $0.ketThuc } ?? false
                        BarMark(x: .value("Giờ", "\(item.gio)h"), y: .value("Doanh thu", item.doanhThu))
                            .foregroundStyle(trongGoiY ? Color.brandPrimary : Color.textMuted.opacity(0.35))
                            .cornerRadius(3)
                    }
                    .frame(height: 180)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { AxisValueLabel().font(.caption2) } }
                    .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { if let y = v.as(Double.self) { Text(BaoCaoSo.rutGon(y)) } } } }
                }

                Section("Doanh thu theo thứ trong tuần") {
                    Chart(itemsThu.sorted { $0.thu < $1.thu }) { item in
                        BarMark(x: .value("Thứ", tenThuNganGon[item.thu] ?? "?"), y: .value("Doanh thu", item.doanhThu))
                            .foregroundStyle(goiYThu.contains(item.thu) ? Color.brandPrimary : Color.textMuted.opacity(0.35))
                            .cornerRadius(3)
                    }
                    .frame(height: 180)
                    .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { if let y = v.as(Double.self) { Text(BaoCaoSo.rutGon(y)) } } } }
                }

                if let onChon, let goiYGio {
                    Section {
                        Button {
                            onChon(goiYGio.batDau, goiYGio.ketThuc, goiYThu)
                            dismiss()
                        } label: {
                            Label("Dùng gợi ý này cho voucher", systemImage: "sparkles")
                        }
                    }
                }
            }
        }
        .navigationTitle("Giờ vắng khách")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private func load() async {
        async let gioTask = APIClient.shared.getPhanBoDonTheoGio(soNgay: 30)
        async let thuTask = APIClient.shared.getPhanBoDoanhThuTheoThu(soNgay: 30)
        async let configTask = APIClient.shared.getGamificationConfig()
        (itemsGio, itemsThu, config) = await (gioTask, thuTask, configTask)
        loading = false
    }
}
