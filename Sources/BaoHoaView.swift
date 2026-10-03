import Charts
import SwiftUI

/// Màn "Phân tích bão hoà" — gom các tín hiệu để trả lời "quán hiện tại đã bão hoà chưa, hay chỉ
/// cần tăng ship/marketing thay vì mở điểm mới" (yêu cầu 2026-10-03, cùng đợt với Bản đồ khách
/// hàng). 4 tín hiệu đã thảo luận, trạng thái từng cái:
/// 1. Doanh thu theo tháng có chững/giảm không — ĐÃ LÀM (Backend HoaDons).
/// 2. Giờ cao điểm có bị nghẽn không — CHỈ LÀM ĐƯỢC PHẦN "giờ nào đông đơn nhất" (tái dùng
///    /api/ThongKe/phan-bo-don-theo-gio). Phần "có bị TRỄ/HUỶ thật không" CHƯA LÀM ĐƯỢC — xem TODO
///    cuối màn.
/// 3. Bán kính ship trung bình theo tháng có tăng dần không — ĐÃ LÀM (từ data.json Bản đồ khách
///    hàng, tính sẵn ở scripts/build-customer-map.py, field shipRadiusTrend).
/// 4. Tỷ lệ khách tháng trước quay lại tháng sau có giảm không — ĐÃ LÀM (Backend HoaDons).
private let mapDataURLForBaoHoa = URL(string: "https://api.denncoffee.com/map-f90702696b23/data.json")!

struct BaoHoaView: View {
    @State private var doanhThuThang: [DoanhThuTheoThangItemDto] = []
    @State private var gioItems: [PhanBoDonTheoGioItemDto] = []
    @State private var retentionThang: [TyLeKhachQuayLaiThangItemDto] = []
    @State private var shipRadiusThang: [ShipRadiusThangItemDto] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                Section { fullScreenLoading() }
            } else {
                doanhThuSection
                gioSection
                shipRadiusSection
                retentionSection
                todoSection
            }
        }
        .navigationTitle("Phân tích bão hoà")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - 1. Doanh thu theo tháng

    private var doanhThuSection: some View {
        Section("Doanh thu theo tháng (12 tháng gần đây)") {
            if doanhThuThang.allSatisfy({ $0.doanhThu == 0 }) {
                Text("Chưa có đủ dữ liệu.").foregroundColor(.textMuted)
            } else {
                Chart(doanhThuThang) { item in
                    LineMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Doanh thu", item.doanhThu))
                    PointMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Doanh thu", item.doanhThu))
                }
                .frame(height: 180)
                .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }

                if let nhanXet = nhanXetDoanhThu {
                    Text(nhanXet).font(.caption).foregroundColor(.brandPrimary).fontWeight(.semibold)
                }
            }
        }
    }

    /// So sánh doanh thu trung bình nửa ĐẦU kỳ với nửa SAU kỳ (bỏ tháng cuối nếu đang chạy dở, dễ
    /// thấp giả tạo) để đưa ra nhận xét chững/tăng trưởng — ngưỡng ±10% coi là "chững", không phải
    /// con số khoa học, chỉ để gợi ý staff tự nhìn thêm biểu đồ.
    private var nhanXetDoanhThu: String? {
        let items = doanhThuThang.count >= 2 ? Array(doanhThuThang.dropLast()) : doanhThuThang
        guard items.count >= 4 else { return nil }
        let mid = items.count / 2
        let dauKy = items[..<mid].map(\.doanhThu).reduce(0, +) / Double(mid)
        let sauKy = items[mid...].map(\.doanhThu).reduce(0, +) / Double(items.count - mid)
        guard dauKy > 0 else { return nil }
        let tangTruong = (sauKy - dauKy) / dauKy
        if tangTruong > 0.1 {
            return "Doanh thu đang tăng trưởng (+\(Int(tangTruong * 100))% nửa sau so nửa đầu kỳ) — chưa có dấu hiệu bão hoà."
        } else if tangTruong < -0.1 {
            return "Doanh thu đang GIẢM (\(Int(tangTruong * 100))% nửa sau so nửa đầu kỳ) — cần xem thêm nguyên nhân."
        } else {
            return "Doanh thu khá chững (\(tangTruong >= 0 ? "+" : "")\(Int(tangTruong * 100))% nửa sau so nửa đầu kỳ) — 1 dấu hiệu có thể đã bão hoà."
        }
    }

    private func nhanThang(_ thang: Int, _ nam: Int) -> String { "\(thang)/\(nam % 100)" }

    // MARK: - 2. Giờ cao điểm

    private var gioSection: some View {
        Section("Giờ đông đơn nhất (30 ngày gần đây)") {
            if gioItems.allSatisfy({ $0.soDon == 0 }) {
                Text("Chưa có đủ dữ liệu.").foregroundColor(.textMuted)
            } else {
                Chart(gioItems) { item in
                    BarMark(x: .value("Giờ", "\(item.gio)h"), y: .value("Số đơn", item.soDon))
                        .foregroundStyle(topGioSet.contains(item.gio) ? Color.brandPrimary : Color.textMuted.opacity(0.35))
                }
                .frame(height: 160)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { AxisValueLabel().font(.caption2) } }

                let topNames = gioItems.sorted { $0.soDon > $1.soDon }.prefix(3).map { "\($0.gio)h" }.joined(separator: ", ")
                Text("Đông nhất: \(topNames) — kiểm tra thực tế có bị chờ lâu/huỷ đơn nhiều vào các giờ này không.")
                    .font(.caption).foregroundColor(.textMuted)
            }
        }
    }

    private var topGioSet: Set<Int> {
        Set(gioItems.sorted { $0.soDon > $1.soDon }.prefix(3).map(\.gio))
    }

    // MARK: - 3. Bán kính ship trung bình theo tháng

    private var shipRadiusSection: some View {
        Section("Bán kính ship trung bình theo tháng") {
            if shipRadiusThang.isEmpty {
                Text("Chưa có dữ liệu.").foregroundColor(.textMuted)
            } else {
                Chart(shipRadiusThang) { item in
                    LineMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Km", item.banKinhTrungBinhKm))
                    PointMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Km", item.banKinhTrungBinhKm))
                }
                .frame(height: 160)
                .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }

                if let first = shipRadiusThang.first, let last = shipRadiusThang.last, shipRadiusThang.count >= 2 {
                    let delta = last.banKinhTrungBinhKm - first.banKinhTrungBinhKm
                    Text(delta > 0.3
                         ? "Bán kính ship đã tăng +\(String(format: "%.1f", delta))km so tháng đầu kỳ — khách gần quán có thể đã khai thác gần hết, đơn mới phải \"với\" ra xa hơn."
                         : "Bán kính ship khá ổn định (\(String(format: "%+.1f", delta))km so tháng đầu kỳ).")
                        .font(.caption).foregroundColor(.brandPrimary).fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - 4. Tỷ lệ khách quay lại theo tháng

    private var retentionSection: some View {
        Section("Tỷ lệ khách tháng trước quay lại tháng sau") {
            if retentionThang.isEmpty {
                Text("Chưa có đủ dữ liệu.").foregroundColor(.textMuted)
            } else {
                Chart(retentionThang) { item in
                    LineMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Tỷ lệ", item.tyLeQuayLai * 100))
                    PointMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Tỷ lệ", item.tyLeQuayLai * 100))
                }
                .frame(height: 160)
                .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
                .chartYAxis { AxisMarks { AxisValueLabel("\(($0.as(Double.self) ?? 0).formatted(.number.precision(.fractionLength(0))))%") } }

                Text("Tính trên khách CÓ đơn ở tháng trước, bao nhiêu % đặt tiếp ngay tháng sau (không tính quay lại trễ hơn).")
                    .font(.caption2).foregroundColor(.textMuted)
            }
        }
    }

    // MARK: - TODO

    private var todoSection: some View {
        Section("Việc còn thiếu (đọc lại khi quay lại làm tiếp)") {
            VStack(alignment: .leading, spacing: 10) {
                todoItem("Độ trễ/huỷ đơn THẬT theo giờ cao điểm",
                         "Hiện chỉ có 'giờ nào đông đơn nhất' (số đơn), chưa đo được có bị CHẬM/HUỶ nhiều không — " +
                         "vì HoaDons không có mốc thời gian 'hoàn tất đơn', chỉ NgayXacNhanOnline (riêng đơn app, " +
                         "không đại diện cho cả quán). Muốn làm đúng cần thêm field mốc giờ hoàn tất/giao xong.")
                todoItem("Mật độ dân cư theo khu vực",
                         "Đã tra nhưng BỎ QUA — khu lõi Phước An+Ea Yông+Hoà Tiến+Hoà An đã sáp nhập 2025 " +
                         "thành 1 xã duy nhất (~68.7k dân), không còn tách được theo từng khu như bản đồ khách hàng.")
                todoItem("Chi phí mặt bằng theo vị trí cụ thể",
                         "Không có nguồn dữ liệu tự động — khi đã nhắm được 1-2 vị trí ứng viên cụ thể thì phải " +
                         "tự khảo sát/hỏi giá thuê thực tế.")
                todoItem("Danh sách đối thủ có thể chưa đủ 100%",
                         "97 quán hiện tại lọc theo từ khoá tên (coffee/cafe/trà sữa/tiệm trà/giải khát...) từ " +
                         "388 quán FOOD ở Krông Pắc trên shippershipping.com — quán đặt tên không có từ khoá " +
                         "liên quan đồ uống sẽ bị bỏ sót, chưa có cách lọc 100% chính xác.")
            }
            .padding(.vertical, 4)
        }
    }

    private func todoItem(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold)).foregroundColor(.orange)
            Text(detail).font(.caption2).foregroundColor(.textMuted)
        }
    }

    // MARK: - Load

    private func load() async {
        async let doanhThuTask = APIClient.shared.getDoanhThuTheoThang(soThang: 12)
        async let gioTask = APIClient.shared.getPhanBoDonTheoGio(soNgay: 30)
        async let retentionTask = APIClient.shared.getTyLeKhachQuayLaiTheoThang(soThang: 12)
        (doanhThuThang, gioItems, retentionThang) = await (doanhThuTask, gioTask, retentionTask)
        shipRadiusThang = await loadShipRadiusTrend()
        loading = false
    }

    private func loadShipRadiusTrend() async -> [ShipRadiusThangItemDto] {
        struct Response: Decodable { let shipRadiusTrend: [ShipRadiusThangItemDto]? }
        guard let (data, _) = try? await URLSession.shared.data(from: mapDataURLForBaoHoa),
              let resp = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return resp.shipRadiusTrend ?? []
    }
}
