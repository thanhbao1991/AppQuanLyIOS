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
    @State private var luongHienTaiText = "10000000"

    private var tiLe: Double { (Double(tiLeText) ?? 0) / 100 }
    private var luongHienTai: Double { Double(luongHienTaiText) ?? 0 }

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
                                TextField("10000000", text: $luongHienTaiText)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 110)
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

/// Không private — trùng tên/layout AmountRow đã dùng ở ThongKeView, nhưng đây là bản riêng để
/// tránh phụ thuộc ngược vào file đó chỉ vì 1 struct nhỏ.
private struct AmountRow: View {
    let label: String
    let value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(HoaDonFormatting.money(value)).monospacedDigit()
        }
    }
}

/// Dương = đang có lời -> thẻ xanh ăn mừng kèu icon nảy nhẹ. Âm/0 = đang lỗ/hoà vốn -> thẻ đỏ điềm
/// tĩnh hơn, không ăn mừng khi đang lỗ.
private struct KetQuaCard: View {
    let ketQua: Double?
    @State private var bounce = false

    var body: some View {
        VStack(spacing: 8) {
            if let ketQua {
                Text(ketQua > 0 ? "🎉🥳🎊" : "😥")
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
                Text(ketQua > 0 ? "Đang có lời, ăn mừng thôi ahihi!" : "Đang lỗ/hoà vốn, ráng lên nào 💪")
                    .font(.subheadline.weight(.semibold))
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            ((ketQua ?? 0) > 0 ? Color.successColor : Color.dangerColor).opacity(0.12)
        )
        .foregroundColor((ketQua ?? 0) > 0 ? .successColor : .dangerColor)
        .cornerRadius(16)
    }
}
