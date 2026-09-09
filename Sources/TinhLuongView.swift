import SwiftUI

/// Công cụ tính lương shipper (Menu > Công cụ) — không lưu gì lên server, chỉ đọc doanh thu đơn ship
/// + chi xăng của shipper trong 1 tháng (GET /api/ThongKe/luong-shipper-thang), phần tỉ lệ lợi nhuận
/// và lương hiện tại là input tại chỗ để thử nhiều kịch bản. Công thức:
///   kết quả = doanhThuShip * tỉLệ - (lươngHiệnTại + chiXăng)
/// Dùng chung 1 view cho cả "Tính lương Khánh"/"Tính lương Nhã", chỉ khác `shipperTen` truyền vào.
struct TinhLuongView: View {
    let shipperTen: String

    @State private var currentDate = Date()
    @State private var luong: LuongShipperDto?
    @State private var hasLoaded = false
    @State private var tiLeText = "40"
    @State private var luongHienTaiText = Self.formatThousands("10000000")

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
                            AmountRow(label: "Doanh thu đơn ship \(shipperTen)", value: luong?.doanhThuShip ?? 0)
                            AmountRow(label: "Chi xăng \(shipperTen)", value: luong?.chiXang ?? 0)
                        }

                        Section {
                            HStack {
                                Text("Tỉ lệ lợi nhuận")
                                Spacer()
                                TextField("40", text: $tiLeText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                Text("%").foregroundColor(.textMuted)
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
                            Text("Kết quả = Doanh thu ship × tỉ lệ − (Lương hiện tại + Chi xăng)")
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
    }

    private func load() async {
        let cal = Calendar.current
        luong = await APIClient.shared.getLuongShipperThang(
            ten: shipperTen,
            thang: cal.component(.month, from: currentDate),
            nam: cal.component(.year, from: currentDate)
        )
        hasLoaded = true
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
