import Charts
import SwiftUI

/// Phân tích số đơn theo giờ trong ngày (30 ngày gần đây) để staff TỰ NHẬN RA khung giờ vắng khách
/// thật của quán, thay vì đoán mò khi cấu hình voucher DieuKien=KhungGioThapDiem — xem
/// GET /api/ThongKe/phan-bo-don-theo-gio. Có gợi ý tự động (khung 2 giờ liên tiếp ít đơn nhất trong
/// số giờ ĐANG MỞ CỬA — loại giờ 0 đơn tuyệt đối vì nhiều khả năng là giờ đóng cửa, không phải "vắng
/// khách") kèm nút áp thẳng vào form voucher đang mở (onChon), hoặc chỉ xem tham khảo khi mở độc lập.
struct GioThapDiemView: View {
    var onChon: ((Int, Int) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhanBoDonTheoGioItemDto] = []
    @State private var loading = true
    @State private var gioBatDau = 14
    @State private var gioKetThuc = 16

    /// Khung 2 giờ liên tiếp có tổng số đơn thấp nhất, chỉ xét trong các giờ CÓ ít nhất 1 đơn (loại
    /// giờ đóng cửa hẳn) — tránh gợi ý nhầm 2h-4h sáng chỉ vì quán không mở cửa giờ đó.
    private var goiY: (batDau: Int, ketThuc: Int)? {
        let sorted = items.sorted { $0.gio < $1.gio }
        var best: (batDau: Int, ketThuc: Int, tong: Int)?
        for i in 0..<sorted.count {
            let j = i + 1
            guard sorted[i].soDon > 0, j < sorted.count, sorted[j].soDon > 0 else { continue }
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
                        BarMark(x: .value("Giờ", "\(item.gio)h"), y: .value("Số đơn", item.soDon))
                            .foregroundStyle(
                                item.gio >= gioBatDau && item.gio < gioKetThuc
                                    ? Color.brandPrimary
                                    : Color.textMuted.opacity(0.35)
                            )
                    }
                    .frame(height: 200)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { AxisValueLabel().font(.caption2) } }
                    Text("Cột xanh = khung giờ đang chọn bên dưới").font(.caption2).foregroundColor(.textMuted)
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
                    Stepper("Bắt đầu: \(gioBatDau)h", value: $gioBatDau, in: 0...22)
                    Stepper("Kết thúc: \(gioKetThuc)h", value: $gioKetThuc, in: (gioBatDau + 1)...23)
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
        items = await APIClient.shared.getPhanBoDonTheoGio(soNgay: 30)
        loading = false
        if let goiY {
            gioBatDau = goiY.batDau
            gioKetThuc = goiY.ketThuc
        }
    }
}
