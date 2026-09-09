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

    /// Cùng logic LIKE '%từ khoá%' + '%tên shipper%' như backend (GetLuongShipperThangAsync) — khớp
    /// không phân biệt hoa/thường/dấu để không lệch với số tổng server đã tính.
    private func items(matching keyword: String) -> [ChiTieuHangNgayDto] {
        chiTieuMonthItems.filter { $0.ten.matchesSearch(keyword) && $0.ten.matchesSearch(shipperTen) }
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

    private var ketQua: Double? {
        guard let luong else { return nil }
        if isNha { return luongHienTai - (luong.chiUng + luong.chiXang) }
        return luong.doanhThuShip * tiLe - (luongHienTai + luong.chiXang)
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
                                AmountRow(label: "Doanh thu đơn ship \(shipperTen)", value: luong?.doanhThuShip ?? 0)
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
                                 : "Kết quả = Doanh thu ship × tỉ lệ − (Lương hiện tại + Chi xăng)")
                        }

                        Section {
                            KetQuaCard(ketQua: ketQua)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
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
                ChiTieuThangDetailSheet(ten: "Chi xăng \(shipperTen)", items: items(matching: "xăng"))
            case .ung:
                ChiTieuThangDetailSheet(ten: "Ứng \(shipperTen)", items: items(matching: "ứng"))
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
    }
}

private enum LuongDetailKind: String, Identifiable {
    case xang, ung
    var id: String { rawValue }
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
