import Charts
import SwiftUI

/// Công cụ tính lương shipper (Menu > Công cụ) — không lưu gì lên server, chỉ đọc doanh thu đơn ship/
/// chi xăng/chi ứng của shipper trong 1 tháng (GET /api/ThongKe/luong-shipper-thang), phần tỉ lệ lợi
/// nhuận và lương hiện tại là input tại chỗ để thử nhiều kịch bản.
/// 2 shipper tính KHÁC công thức hẳn nhau (không phải cùng 1 công thức đổi tham số):
///   - Khánh: doanhThuShip * tỉLệ - (lươngHiệnTại + chiXăng)  — Khánh ứng trước lương/tỉ lệ, đối
///     soát bằng doanh thu ship trừ lại phần đã ứng.
///   - Nhã:   lươngHiệnTại - (chiỨng + chiXăng)               — không liên quan doanh thu ship, không
///     có tỉ lệ lợi nhuận, chỉ trừ khoản đã ứng + xăng khỏi lương cố định.
/// Dùng chung 1 view cho cả "Tính lương Khánh"/"Tính lương Nhã", chỉ khác `shipperTen` truyền vào.
struct TinhLuongView: View {
    let shipperTen: String

    private var isNha: Bool { shipperTen == "Nhã" }

    @State private var currentDate = Date()
    @State private var luong: LuongShipperDto?
    @State private var chiTieuMonthItems: [ChiTieuHangNgayDto] = []
    @State private var hasLoaded = false
    @State private var tiLeText = "40"
    @State private var luongHienTaiText = Self.formatThousands("10000000")
    @State private var selectedDetail: LuongDetailKind?
    /// Dữ liệu thô 6 tháng gần đây (kết thúc ở currentDate) — giữ raw luong thay vì tính sẵn ketQua
    /// để biểu đồ tự cập nhật theo tiLe/luongHienTai đang gõ, giống cách ketQua (tháng hiện tại) đã
    /// recompute live mỗi lần input đổi.
    @State private var luong6ThangRaw: [(thang: Int, nam: Int, luong: LuongShipperDto)] = []

    /// Cùng 3 NguyenLieuId cố định như backend (ThongKeService.XangNguyenLieuId/UngNguyenLieuId) — dò
    /// 1 lần qua SSH ngày 2026-09-09. KHÔNG lọc theo Ten (chữ tự do, đã phát hiện 2 dòng "Xăng (Khánh)"/
    /// "Xăng (KHÁNH)" cùng NguyenLieuId nhưng khác hoa/thường làm lệch số giữa 2 nơi hiển thị).
    private static let xangNguyenLieuId: [String: String] = [
        "Khánh": "8602845A-8DD3-4799-ADFD-C25529D02170",
        "Nhã": "C9E6D37B-2344-4D54-B9E8-40E303441B0A",
    ]
    private static let ungNguyenLieuId: [String: String] = [
        "Nhã": "7995B334-44D1-4768-89C7-280E6B0413AE",
    ]

    private func items(nguyenLieuId: String?) -> [ChiTieuHangNgayDto] {
        guard let nguyenLieuId else { return [] }
        return chiTieuMonthItems.filter { $0.nguyenLieuId.caseInsensitiveCompare(nguyenLieuId) == .orderedSame }
    }

    private var tiLe: Double { (Double(tiLeText) ?? 0) / 100 }
    private var luongHienTai: Double { Double(luongHienTaiText.filter(\.isNumber)) ?? 0 }

    /// Gõ tới đâu format dấu chấm ngăn cách tới đó (kiểu "10.000.000") — chỉ giữ lại chữ số rồi
    /// nhóm lại bằng chính moneyFormatter đang dùng chung toàn app, không tạo formatter riêng.
    private static func formatThousands(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard let value = Int(digits) else { return "" }
        return HoaDonFormatting.moneyFormatter.string(from: NSNumber(value: value)) ?? digits
    }

    private func tinhKetQua(_ luong: LuongShipperDto) -> Double {
        if isNha { return luongHienTai - (luong.chiUng + luong.chiXang) }
        return luong.doanhThuShip * tiLe - (luongHienTai + luong.chiXang)
    }

    private var ketQua: Double? {
        guard let luong else { return nil }
        return tinhKetQua(luong)
    }

    fileprivate struct ThangKetQua: Identifiable {
        let thang: Int
        let nam: Int
        let ketQua: Double
        var id: String { "\(nam)-\(thang)" }
        var label: String { "\(thang)/\(nam % 100)" }
    }

    private var bieuDo6Thang: [ThangKetQua] {
        luong6ThangRaw.map { ThangKetQua(thang: $0.thang, nam: $0.nam, ketQua: tinhKetQua($0.luong)) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    VStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    Form {
                        Section {
                            if isNha {
                                AmountRow(label: "Ứng \(shipperTen)", value: luong?.chiUng ?? 0)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedDetail = .ung }
                            } else {
                                AmountRow(label: "Đơn \(shipperTen) ship", value: luong?.doanhThuShip ?? 0)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedDetail = .doanhThu }
                            }
                            AmountRow(label: "Chi xăng \(shipperTen)", value: luong?.chiXang ?? 0)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedDetail = .xang }
                        }

                        Section {
                            if !isNha {
                                HStack {
                                    Text("Tỉ lệ lợi nhuận")
                                    Spacer()
                                    TextField("40", text: $tiLeText)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 70)
                                    Text("%").foregroundColor(.textMuted)
                                }
                            }
                            HStack {
                                Text("Lương hiện tại")
                                Spacer()
                                TextField("10.000.000", text: $luongHienTaiText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 130)
                                    .onChange(of: luongHienTaiText) { newValue in
                                        let formatted = Self.formatThousands(newValue)
                                        if formatted != newValue { luongHienTaiText = formatted }
                                    }
                                Text("đ").foregroundColor(.textMuted)
                            }
                        } footer: {
                            Text(isNha
                                 ? "Kết quả = Lương hiện tại − (Ứng \(shipperTen) + Chi xăng)"
                                 : "Kết quả = Đơn ship × tỉ lệ − (Lương hiện tại + Chi xăng)")
                        }

                        Section {
                            KetQuaCard(ketQua: ketQua)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())

                        if !bieuDo6Thang.isEmpty {
                            Section {
                                KetQua6ThangChart(items: bieuDo6Thang)
                            } header: {
                                Text("Kết quả 6 tháng gần đây")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tính lương \(shipperTen)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MonthDateBar(date: $currentDate, tinted: true) { Task { await load() } }
                }
            }
        }
        .task { await load() }
        .sheet(item: $selectedDetail) { kind in
            switch kind {
            case .xang:
                ChiTieuThangDetailSheet(ten: "Chi xăng \(shipperTen)", items: items(nguyenLieuId: Self.xangNguyenLieuId[shipperTen]))
            case .ung:
                ChiTieuThangDetailSheet(ten: "Ứng \(shipperTen)", items: items(nguyenLieuId: Self.ungNguyenLieuId[shipperTen]))
            case .doanhThu:
                DoanhThuShipperChiTietSheet(shipperTen: shipperTen, currentDate: currentDate)
            }
        }
    }

    private func load() async {
        let cal = Calendar.current
        let thang = cal.component(.month, from: currentDate)
        let nam = cal.component(.year, from: currentDate)

        async let a = APIClient.shared.getLuongShipperThang(ten: shipperTen, thang: thang, nam: nam)
        async let b = APIClient.shared.getChiTieuByMonth(year: nam, month: thang)
        (luong, chiTieuMonthItems) = await (a, b)
        hasLoaded = true

        await load6Thang()
    }

    /// 6 tháng gần đây tính tới currentDate (đang chọn) — gọi song song qua TaskGroup, giữ đúng thứ
    /// tự tăng dần theo thời gian cho biểu đồ dù các request hoàn tất không theo thứ tự.
    private func load6Thang() async {
        let cal = Calendar.current
        let thangNamList: [(thang: Int, nam: Int)] = (0..<6).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .month, value: -offset, to: currentDate) else { return nil }
            return (cal.component(.month, from: d), cal.component(.year, from: d))
        }

        let results = await withTaskGroup(of: (Int, Int, Int, LuongShipperDto?).self) { group in
            for (index, tn) in thangNamList.enumerated() {
                group.addTask {
                    let luong = await APIClient.shared.getLuongShipperThang(ten: shipperTen, thang: tn.thang, nam: tn.nam)
                    return (index, tn.thang, tn.nam, luong)
                }
            }
            var collected: [(Int, Int, Int, LuongShipperDto?)] = []
            for await item in group { collected.append(item) }
            return collected.sorted { $0.0 < $1.0 }
        }

        luong6ThangRaw = results.compactMap { _, thang, nam, luong in
            luong.map { (thang: thang, nam: nam, luong: $0) }
        }
    }
}

private enum LuongDetailKind: String, Identifiable {
    case xang, ung, doanhThu
    var id: String { rawValue }
}

/// Danh sách hoá đơn của dòng "Doanh thu đơn ship" — khớp layout DoanhThuChiTietSheet (MainTabView.swift)
/// nhưng gọi endpoint riêng lọc theo NguoiShip thay vì theo PhânLoại/tên hạng mục.
private struct DoanhThuShipperChiTietSheet: View {
    let shipperTen: String
    let currentDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var items: [HoaDonListDto] = []
    @State private var hasLoaded = false
    @State private var selectedHoaDonId: String?

    private var total: Double { items.reduce(0) { $0 + $1.thanhTien } }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ProgressView()
                } else {
                    List {
                        Section {
                            HStack {
                                Text("Tổng cộng").foregroundColor(.textMuted)
                                Spacer()
                                Text(HoaDonFormatting.money(total)).font(.headline).monospacedDigit()
                            }
                        }
                        ForEach(items) { item in
                            Button {
                                selectedHoaDonId = item.id
                            } label: {
                                HStack {
                                    Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(HoaDonFormatting.money(item.thanhTien))
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Đơn \(shipperTen) ship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
        .task {
            let cal = Calendar.current
            items = await APIClient.shared.getDoanhThuShipperChiTietThang(
                ten: shipperTen,
                thang: cal.component(.month, from: currentDate),
                nam: cal.component(.year, from: currentDate)
            )
            hasLoaded = true
        }
        .sheet(item: Binding(
            get: { selectedHoaDonId.map { IdentifiableId($0) } },
            set: { selectedHoaDonId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {}
        }
        .presentationDragIndicator(.visible)
    }
}

/// Đường xu hướng kết quả 6 tháng gần đây — mỗi điểm tô màu theo lời/lỗ giống KetQuaCard, đường
/// nối dùng màu trung tính (brandPrimary) vì bản thân đường không mang nghĩa lời/lỗ, chỉ nối các
/// điểm cho dễ nhìn xu hướng tăng/giảm.
private struct KetQua6ThangChart: View {
    let items: [TinhLuongView.ThangKetQua]

    var body: some View {
        Chart(items) { item in
            LineMark(x: .value("Tháng", item.label), y: .value("Kết quả", item.ketQua))
                .foregroundStyle(Color.brandPrimary)
            PointMark(x: .value("Tháng", item.label), y: .value("Kết quả", item.ketQua))
                .foregroundStyle(item.ketQua >= 0 ? Color.successColor : Color.dangerColor)
                .symbolSize(60)
            RuleMark(y: .value("Hoà vốn", 0))
                .foregroundStyle(Color.textMuted.opacity(0.3))
                .lineStyle(StrokeStyle(dash: [4, 4]))
        }
        .chartXAxis { AxisMarks(values: .automatic) { AxisValueLabel().font(.caption2) } }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(HoaDonFormatting.moneyShort(d)).font(.caption2)
                    }
                }
            }
        }
        .frame(height: 160)
        .padding(.vertical, 8)
    }
}

/// 3 trạng thái riêng: dương = có lời (thẻ xanh, ăn mừng icon nảy nhẹ), 0 = hoà vốn (thẻ vàng, điềm
/// tĩnh), âm = lỗ vốn (thẻ đỏ, không ăn mừng).
private struct KetQuaCard: View {
    let ketQua: Double?
    @State private var bounce = false

    private var trangThai: (emoji: String, text: String, color: Color)? {
        guard let ketQua else { return nil }
        if ketQua > 0 { return ("🎉🥳🎊", "Đang có lời, ăn mừng thôi ahihi!", .successColor) }
        if ketQua == 0 { return ("⚖️", "Hoà vốn, huề nhau nhé!", .warningColor) }
        return ("😥", "Đang lỗ vốn, ráng lên nào 💪", .dangerColor)
    }

    var body: some View {
        VStack(spacing: 8) {
            if let ketQua, let trangThai {
                Text(trangThai.emoji)
                    .font(.system(size: 40))
                    .scaleEffect(bounce ? 1.15 : 1.0)
                    .onAppear {
                        guard ketQua > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                            bounce = true
                        }
                    }
                Text(HoaDonFormatting.money(ketQua))
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                Text(trangThai.text)
                    .font(.subheadline.weight(.semibold))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background((trangThai?.color ?? .textMuted).opacity(0.12))
        .foregroundColor(trangThai?.color ?? .textMuted)
        .cornerRadius(16)
    }
}
