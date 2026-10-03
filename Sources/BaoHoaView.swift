import Charts
import SwiftUI

/// Màn "Phân tích bão hoà" — gom các tín hiệu để trả lời "quán hiện tại đã bão hoà chưa, hay chỉ
/// cần tăng ship/marketing thay vì mở điểm mới" (yêu cầu 2026-10-03, cùng đợt với Bản đồ khách
/// hàng). 4 tín hiệu đã thảo luận, trạng thái từng cái:
/// 1. Doanh thu theo tháng có chững/giảm không — ĐÃ LÀM (Backend HoaDons).
/// 2. Giờ cao điểm có bị nghẽn không — CHỈ LÀM ĐƯỢC PHẦN "giờ nào đông đơn nhất" (tái dùng
///    /api/ThongKe/phan-bo-don-theo-gio). Phần "có bị TRỄ/HUỶ thật không" CHƯA LÀM ĐƯỢC — xem TODO
///    cuối màn.
/// 3. Bán kính ship trung bình theo tháng — ĐÃ LÀM, từ 2026-10-04 đọc DB (GET
///    /api/Map/ship-radius-trend, bảng DonViTriLog) thay vì crawl. QUAN TRỌNG: số này KHÔNG tự nó
///    nói lên bão hoà — bán kính tăng CÙNG LÚC số đơn tăng mạnh là dấu hiệu MỞ RỘNG THÀNH CÔNG,
///    chỉ đáng lo khi bán kính tăng mà số đơn đi ngang/giảm (phải "với" xa hơn mới đủ đơn như cũ).
///    Nhận xét tự động phải GHÉP 2 chỉ số này, không tách riêng — bài học từ phản hồi 2026-10-04
///    (ban đầu diễn giải một chiều là bão hoà, sai vì không nhìn số đơn đi kèm).
/// 4. Tỷ lệ khách tháng trước quay lại tháng sau có giảm không — ĐÃ LÀM (Backend HoaDons).

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

                if let nhanXet = nhanXetBanKinhShip {
                    Text(nhanXet).font(.caption).foregroundColor(.brandPrimary).fontWeight(.semibold)
                }
                Text("Bán kính tăng không tự nó là xấu — phải nhìn kèm số đơn: tăng cùng lúc số đơn tăng mạnh là mở rộng thành công, chỉ đáng lo khi số đơn đi ngang/giảm mà vẫn phải với xa hơn.")
                    .font(.caption2).foregroundColor(.textMuted)
            }
        }
    }

    /// Ghép bán kính VỚI số đơn (shipRadiusThang.soDon, từ DonViTriLog) để tránh diễn giải một
    /// chiều — xem comment đầu file.
    private var nhanXetBanKinhShip: String? {
        guard shipRadiusThang.count >= 4 else { return nil }
        let items = Array(shipRadiusThang.dropLast())
        guard items.count >= 4 else { return nil }
        let mid = items.count / 2
        let dauKy = items[..<mid]
        let sauKy = items[mid...]
        let kmDau = dauKy.map(\.banKinhTrungBinhKm).reduce(0, +) / Double(dauKy.count)
        let kmSau = sauKy.map(\.banKinhTrungBinhKm).reduce(0, +) / Double(sauKy.count)
        let donDau = Double(dauKy.map(\.soDon).reduce(0, +)) / Double(dauKy.count)
        let donSau = Double(sauKy.map(\.soDon).reduce(0, +)) / Double(sauKy.count)
        let deltaKm = kmSau - kmDau
        guard donDau > 0 else { return nil }
        let tangTruongDon = (donSau - donDau) / donDau

        if deltaKm <= 0.3 {
            return "Bán kính ship khá ổn định (\(String(format: "%+.1f", deltaKm))km nửa sau so nửa đầu kỳ)."
        } else if tangTruongDon > 0.1 {
            return "Bán kính tăng +\(String(format: "%.1f", deltaKm))km nhưng số đơn cũng tăng +\(Int(tangTruongDon * 100))% — đang MỞ RỘNG THÀNH CÔNG, không phải bão hoà."
        } else if tangTruongDon < -0.1 {
            return "Bán kính tăng +\(String(format: "%.1f", deltaKm))km trong khi số đơn GIẢM \(Int(tangTruongDon * 100))% — dấu hiệu bão hoà thật: phải với xa hơn mới đủ đơn."
        } else {
            return "Bán kính tăng +\(String(format: "%.1f", deltaKm))km nhưng số đơn gần như đi ngang — có thể đã bắt đầu bão hoà, cần theo dõi thêm."
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
        async let shipRadiusTask = APIClient.shared.getShipRadiusTrend(soThang: 12)
        (doanhThuThang, gioItems, retentionThang, shipRadiusThang) = await (doanhThuTask, gioTask, retentionTask, shipRadiusTask)
        loading = false
    }
}
