import Charts
import SwiftUI

/// Phân tích số đơn theo giờ trong ngày (30 ngày gần đây) để staff TỰ NHẬN RA khung giờ vắng khách
/// thật của quán, thay vì đoán mò khi cấu hình voucher DieuKien=KhungGioThapDiem — xem
/// GET /api/ThongKe/phan-bo-don-theo-gio. Gợi ý tự động (khung 2 giờ liên tiếp ít đơn nhất) CHỈ xét
/// trong giờ mở bán thật (GamificationConfig.gioMoCua/gioDongCua, xem GamificationConfigView) — trước
/// đây (2026-09-15) chỉ đoán qua "giờ có ít nhất 1 đơn" nên có thể lẫn giờ gần đóng cửa (đơn lác đác
/// do khách đặt app chờ giao sau) vào coi như "giờ mở cửa bình thường". Kèm nút áp thẳng vào form
/// voucher đang mở (onChon), hoặc chỉ xem tham khảo khi mở độc lập từ Công cụ.
struct GioThapDiemView: View {
    var onChon: ((Int, Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhanBoDonTheoGioItemDto] = []
    @State private var config: GamificationConfigDto?
    @State private var loading = true
    @State private var gioBatDau = 14
    @State private var gioKetThuc = 16

    /// Khung 2 giờ liên tiếp trong giờ mở bán có tổng số đơn thấp nhất — chưa tải được config thì
    /// coi như mở cửa cả ngày (không lọc gì) để vẫn ra gợi ý thay vì im lặng.
    private var goiY: (batDau: Int, ketThuc: Int)? {
        let mo = config?.gioMoCua ?? 0
        let dong = config?.gioDongCua ?? 24
        let sorted = items.filter { $0.gio >= mo && $0.gio < dong }.sorted { $0.gio < $1.gio }
        var best: (batDau: Int, ketThuc: Int, tong: Int)?
        for i in 0..<sorted.count {
            let j = i + 1
            guard j < sorted.count else { continue }
            let tong = sorted[i].soDon + sorted[j].soDon
            if best == nil || tong < best!.tong {
                best = (sorted[i].gio, sorted[j].gio + 1, tong)
            }
        }
        guard let best else { return nil }
        return (best.batDau, best.ketThuc)
    }

    private var maxSoDon: Int { items.map(\.soDon).max() ?? 0 }

    var body: some View {
        List {
            if loading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if items.allSatisfy({ $0.soDon == 0 }) {
                Section {
                    Text("Chưa có đủ dữ liệu đơn hàng 30 ngày gần đây để phân tích.")
                        .foregroundColor(.textMuted)
                }
            } else {
                Section("Số đơn theo giờ (30 ngày gần đây)") {
                    Chart(items) { item in
                        let dangMoCua = item.gio >= (config?.gioMoCua ?? 0) && item.gio < (config?.gioDongCua ?? 24)
                        BarMark(x: .value("Giờ", "\(item.gio)h"), y: .value("Số đơn", item.soDon))
                            .foregroundStyle(
                                !dangMoCua ? Color.textMuted.opacity(0.15)
                                    : (item.gio >= gioBatDau && item.gio < gioKetThuc ? Color.brandPrimary : Color.textMuted.opacity(0.35))
                            )
                    }
                    .frame(height: 200)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { AxisValueLabel().font(.caption2) } }
                    if let config {
                        Text("Cột xanh = khung giờ đang chọn · Cột mờ nhạt nhất (\(config.gioDongCua)h–24h, 0h–\(config.gioMoCua)h) = ngoài giờ mở bán")
                            .font(.caption2).foregroundColor(.textMuted)
                    }
                }

                if let goiY {
                    Section {
                        Button {
                            gioBatDau = goiY.batDau
                            gioKetThuc = goiY.ketThuc
                        } label: {
                            Label("Dùng gợi ý: \(goiY.batDau)h–\(goiY.ketThuc)h (vắng khách nhất)", systemImage: "sparkles")
                        }
                    }
                }

                Section("Khung giờ") {
                    Stepper("Bắt đầu: \(gioBatDau)h", value: $gioBatDau, in: (config?.gioMoCua ?? 0)...min(22, (config?.gioDongCua ?? 24) - 1))
                    Stepper("Kết thúc: \(gioKetThuc)h", value: $gioKetThuc, in: (gioBatDau + 1)...min(23, config?.gioDongCua ?? 23))
                }
            }
        }
        .navigationTitle("Giờ vắng khách")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onChon {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Dùng khung này") {
                        onChon(gioBatDau, gioKetThuc)
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        async let itemsTask = APIClient.shared.getPhanBoDonTheoGio(soNgay: 30)
        async let configTask = APIClient.shared.getGamificationConfig()
        (items, config) = await (itemsTask, configTask)
        loading = false
        if let goiY {
            gioBatDau = goiY.batDau
            gioKetThuc = goiY.ketThuc
        }
    }
}
