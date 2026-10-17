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

/// 18/10/2026: trình bày lại theo BaoCaoUI (kết luận trước, chi tiết sau) — thẻ kết luận tổng đầu màn,
/// mỗi tín hiệu 1 dòng (kết luận 1 câu + màu mức độ + con số), chạm mới mở biểu đồ + giải thích dài.
struct BaoHoaView: View {
    @State private var doanhThuThang: [DoanhThuTheoThangItemDto] = []
    @State private var gioItems: [PhanBoDonTheoGioItemDto] = []
    @State private var retentionThang: [TyLeKhachQuayLaiThangItemDto] = []
    @State private var shipRadiusThang: [ShipRadiusThangItemDto] = []
    @State private var loading = true
    @State private var moRa: Set<String> = []

    /// Kết luận 1 tín hiệu: mức độ, câu ngắn hiện ở dòng thu gọn, con số canh phải, nhận xét đầy đủ khi mở.
    private struct TinHieu {
        let mucDo: MucDo
        let ketLuan: String
        let giaTri: String?
        let nhanXet: String?
    }

    var body: some View {
        List {
            if loading {
                Section { fullScreenLoading() }
            } else {
                Section { theKetLuan }
                Section {
                    khoi("doanh-thu", icon: "chart.line.uptrend.xyaxis", tieuDe: "Doanh thu theo tháng", tinHieuDoanhThu) { doanhThuChart }
                    khoi("ban-kinh", icon: "scope", tieuDe: "Bán kính ship", tinHieuBanKinh) { shipRadiusChart }
                    khoi("quay-lai", icon: "arrow.uturn.backward.circle", tieuDe: "Khách quay lại", tinHieuQuayLai) { retentionChart }
                    khoi("gio", icon: "clock", tieuDe: "Giờ đông đơn nhất", tinHieuGio) { gioChart }
                } header: {
                    Text("Tín hiệu")
                } footer: {
                    Text("Chạm từng dòng để xem biểu đồ và giải thích. Doanh thu, bán kính, khách quay lại tính trên 12 tháng; giờ đông tính 30 ngày.")
                }
                todoSection
            }
        }
        .navigationTitle("Phân tích bão hoà")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    // MARK: - Kết luận tổng

    /// Gộp 3 tín hiệu có thể nói lên bão hoà (giờ đông chỉ để tham khảo): ≥ 2 xấu → có dấu hiệu; 1 xấu hoặc
    /// có cảnh báo → cần theo dõi; còn lại → chưa có dấu hiệu.
    @ViewBuilder private var theKetLuan: some View {
        let ds = [("Doanh thu", tinHieuDoanhThu), ("Bán kính ship", tinHieuBanKinh), ("Khách quay lại", tinHieuQuayLai)]
            .compactMap { ten, th in th.map { (ten, $0) } }
        let xau = ds.filter { $0.1.mucDo == .xau }
        let canhBao = ds.filter { $0.1.mucDo == .canhBao }
        if ds.isEmpty {
            TheKetLuan(mucDo: .trungTinh, tieuDe: "Chưa đủ dữ liệu", moTa: "Cần ít nhất vài tháng số liệu để đánh giá.")
        } else if xau.count >= 2 {
            TheKetLuan(mucDo: .xau, tieuDe: "Có dấu hiệu bão hoà",
                       moTa: (xau + canhBao).map { "\($0.0): \($0.1.ketLuan.lowercased())" }.joined(separator: " · "))
        } else if !xau.isEmpty || !canhBao.isEmpty {
            TheKetLuan(mucDo: .canhBao, tieuDe: "Cần theo dõi",
                       moTa: (xau + canhBao).map { "\($0.0): \($0.1.ketLuan.lowercased())" }.joined(separator: " · "))
        } else {
            TheKetLuan(mucDo: .tot, tieuDe: "Chưa có dấu hiệu bão hoà", moTa: "\(ds.count) tín hiệu đều ổn")
        }
    }

    @ViewBuilder
    private func khoi<C: View>(_ ma: String, icon: String, tieuDe: String, _ th: TinHieu?, @ViewBuilder chart: () -> C) -> some View {
        let t = th ?? TinHieu(mucDo: .trungTinh, ketLuan: "Chưa đủ dữ liệu", giaTri: nil, nhanXet: nil)
        KhoiChiSo(icon: icon, tieuDe: tieuDe, ketLuan: t.ketLuan, mucDo: t.mucDo, giaTri: t.giaTri,
                  moRa: moRa.contains(ma), onToggle: {
                      withAnimation { if moRa.contains(ma) { moRa.remove(ma) } else { moRa.insert(ma) } }
                  }) {
            VStack(alignment: .leading, spacing: 8) {
                chart()
                if let nx = t.nhanXet {
                    Text(nx).font(.caption).foregroundColor(.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 1. Doanh thu theo tháng

    /// So sánh doanh thu trung bình nửa ĐẦU kỳ với nửa SAU kỳ (bỏ tháng cuối nếu đang chạy dở, dễ
    /// thấp giả tạo) — ngưỡng ±10% coi là "chững", không phải con số khoa học, chỉ để gợi ý staff tự
    /// nhìn thêm biểu đồ.
    private var tinHieuDoanhThu: TinHieu? {
        let items = doanhThuThang.count >= 2 ? Array(doanhThuThang.dropLast()) : doanhThuThang
        guard items.count >= 4 else { return nil }
        let mid = items.count / 2
        let dauKy = items[..<mid].map(\.doanhThu).reduce(0, +) / Double(mid)
        let sauKy = items[mid...].map(\.doanhThu).reduce(0, +) / Double(items.count - mid)
        guard dauKy > 0 else { return nil }
        let pt = Int(((sauKy - dauKy) / dauKy * 100).rounded())
        let giaTri = "\(pt >= 0 ? "+" : "")\(pt)%"
        let tb = "TB nửa sau kỳ \(BaoCaoSo.rutGon(sauKy))/tháng so với \(BaoCaoSo.rutGon(dauKy))/tháng nửa đầu kỳ (không tính tháng đang chạy)."
        if pt > 10 { return TinHieu(mucDo: .tot, ketLuan: "Đang tăng trưởng", giaTri: giaTri, nhanXet: tb) }
        if pt < -10 { return TinHieu(mucDo: .xau, ketLuan: "Đang giảm", giaTri: giaTri, nhanXet: tb + " Cần xem thêm nguyên nhân.") }
        return TinHieu(mucDo: .canhBao, ketLuan: "Chững lại", giaTri: giaTri, nhanXet: tb + " Chững là 1 dấu hiệu có thể đã bão hoà.")
    }

    @ViewBuilder private var doanhThuChart: some View {
        if doanhThuThang.allSatisfy({ $0.doanhThu == 0 }) {
            Text("Chưa có đủ dữ liệu.").foregroundColor(.textMuted)
        } else {
            Chart(doanhThuThang) { item in
                BarMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Doanh thu", item.doanhThu))
                    .foregroundStyle(Color.brandPrimary.gradient)
                    .cornerRadius(3)
            }
            .frame(height: 180)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { if let y = v.as(Double.self) { Text(BaoCaoSo.rutGon(y)) } } } }
        }
    }

    private func nhanThang(_ thang: Int, _ nam: Int) -> String { "\(thang)/\(nam % 100)" }

    // MARK: - 2. Giờ cao điểm

    private var topGio: [PhanBoDonTheoGioItemDto] {
        Array(gioItems.filter { $0.soDon > 0 }.sorted { $0.soDon > $1.soDon }.prefix(3))
    }

    private var tinHieuGio: TinHieu? {
        guard !topGio.isEmpty else { return nil }
        return TinHieu(mucDo: .trungTinh,
                       ketLuan: "Đông nhất: " + topGio.map { "\($0.gio)h" }.joined(separator: ", "),
                       giaTri: nil,
                       nhanXet: "Chỉ để tham khảo: kiểm tra thực tế có bị chờ lâu/huỷ đơn nhiều vào các giờ này không.")
    }

    @ViewBuilder private var gioChart: some View {
        let top = Set(topGio.map(\.gio))
        Chart(gioItems) { item in
            BarMark(x: .value("Giờ", "\(item.gio)h"), y: .value("Số đơn", item.soDon))
                .foregroundStyle(top.contains(item.gio) ? Color.brandPrimary : Color.textMuted.opacity(0.35))
                .cornerRadius(3)
        }
        .frame(height: 160)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 8)) { AxisValueLabel().font(.caption2) } }
    }

    // MARK: - 3. Bán kính ship trung bình theo tháng

    /// Ghép bán kính VỚI số đơn (shipRadiusThang.soDon, từ DonViTriLog) để tránh diễn giải một
    /// chiều — xem comment đầu file.
    private var tinHieuBanKinh: TinHieu? {
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
        let ptDon = Int(((donSau - donDau) / donDau * 100).rounded())
        let giaTri = String(format: "%+.1f km", deltaKm)
        let soLieu = String(format: "Bán kính TB %.1f km → %.1f km, số đơn %+ld%% (nửa đầu → nửa sau kỳ).", kmDau, kmSau, ptDon)

        if deltaKm <= 0.3 {
            return TinHieu(mucDo: .tot, ketLuan: "Ổn định", giaTri: giaTri, nhanXet: soLieu)
        } else if ptDon > 10 {
            return TinHieu(mucDo: .tot, ketLuan: "Mở rộng thành công", giaTri: giaTri,
                           nhanXet: soLieu + " Bán kính tăng cùng lúc số đơn tăng mạnh — không phải bão hoà.")
        } else if ptDon < -10 {
            return TinHieu(mucDo: .xau, ketLuan: "Phải với xa hơn mới đủ đơn", giaTri: giaTri,
                           nhanXet: soLieu + " Bán kính tăng trong khi số đơn giảm — dấu hiệu bão hoà thật.")
        } else {
            return TinHieu(mucDo: .canhBao, ketLuan: "Xa hơn nhưng đơn đi ngang", giaTri: giaTri,
                           nhanXet: soLieu + " Có thể đã bắt đầu bão hoà, cần theo dõi thêm.")
        }
    }

    @ViewBuilder private var shipRadiusChart: some View {
        if shipRadiusThang.isEmpty {
            Text("Chưa có dữ liệu.").foregroundColor(.textMuted)
        } else {
            Chart(shipRadiusThang) { item in
                LineMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Km", item.banKinhTrungBinhKm))
                    .foregroundStyle(Color.brandPrimary)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Km", item.banKinhTrungBinhKm))
                    .foregroundStyle(Color.brandPrimary)
            }
            .frame(height: 160)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartYAxis { AxisMarks(position: .leading) { v in AxisGridLine(); AxisValueLabel { if let y = v.as(Double.self) { Text(String(format: "%.1f km", y)) } } } }
        }
    }

    // MARK: - 4. Tỷ lệ khách quay lại theo tháng

    /// Nửa sau kỳ so nửa đầu kỳ (điểm %): giảm > 3 điểm → xấu, tăng > 3 → tốt, còn lại ổn định (cũng tốt).
    private var tinHieuQuayLai: TinHieu? {
        let items = Array(retentionThang.dropLast())
        guard items.count >= 4 else { return nil }
        let mid = items.count / 2
        let dau = items[..<mid].map(\.tyLeQuayLai).reduce(0, +) / Double(mid) * 100
        let sau = items[mid...].map(\.tyLeQuayLai).reduce(0, +) / Double(items.count - mid) * 100
        let delta = sau - dau
        let giaTri = String(format: "%.0f%%", sau)
        let nx = String(format: "TB %.0f%% → %.0f%% (nửa đầu → nửa sau kỳ). Tính trên khách CÓ đơn tháng trước, bao nhiêu %% đặt tiếp ngay tháng sau.", dau, sau)
        if delta < -3 { return TinHieu(mucDo: .xau, ketLuan: String(format: "Đang giảm (%.0f điểm)", delta), giaTri: giaTri, nhanXet: nx) }
        if delta > 3 { return TinHieu(mucDo: .tot, ketLuan: String(format: "Đang tăng (+%.0f điểm)", delta), giaTri: giaTri, nhanXet: nx) }
        return TinHieu(mucDo: .tot, ketLuan: "Ổn định", giaTri: giaTri, nhanXet: nx)
    }

    @ViewBuilder private var retentionChart: some View {
        if retentionThang.isEmpty {
            Text("Chưa có đủ dữ liệu.").foregroundColor(.textMuted)
        } else {
            Chart(retentionThang) { item in
                LineMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Tỷ lệ", item.tyLeQuayLai * 100))
                    .foregroundStyle(Color.brandPrimary)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Tháng", nhanThang(item.thang, item.nam)), y: .value("Tỷ lệ", item.tyLeQuayLai * 100))
                    .foregroundStyle(Color.brandPrimary)
            }
            .frame(height: 160)
            .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
            .chartYAxis { AxisMarks(position: .leading) { AxisValueLabel("\(($0.as(Double.self) ?? 0).formatted(.number.precision(.fractionLength(0))))%") } }
        }
    }

    // MARK: - TODO

    private var todoSection: some View {
        Section {
            DisclosureGroup("Việc còn thiếu (4)") {
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
            .font(.subheadline)
            .foregroundColor(.textMuted)
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
