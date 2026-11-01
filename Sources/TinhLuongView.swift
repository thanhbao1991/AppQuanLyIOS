import SwiftUI

/// Công cụ tính lương shipper (Trợ lý ảo > Chi Phí, trước 28/10/2026 ở Menu > Công cụ) — không lưu gì lên server, chỉ đọc doanh thu đơn ship/
/// chi xăng/chi ứng của shipper trong 1 tháng (GET /api/ThongKe/luong-shipper-thang), phần tỉ lệ lợi
/// nhuận và lương hiện tại là input tại chỗ để thử nhiều kịch bản.
/// 2 shipper tính KHÁC công thức hẳn nhau (không phải cùng 1 công thức đổi tham số):
///   - Khánh: doanhThuShip * tỉLệ - (lươngHiệnTại + chiXăng)  — Khánh ứng trước lương/tỉ lệ, đối
///     soát bằng doanh thu ship trừ lại phần đã ứng.
///   - Nhã:   lươngHiệnTại - (chiỨng + chiXăng)               — không liên quan doanh thu ship, không
///     có tỉ lệ lợi nhuận, chỉ trừ khoản đã ứng + xăng khỏi lương cố định.
/// Dùng chung 1 view cho cả "Tính lương Khánh"/"Tính lương Nhã", chỉ khác `shipperTen` truyền vào.
/// 01/11/2026 (user): bung ngay trong Trợ lý ảo, không mở màn riêng; bỏ biểu đồ 6 tháng, bỏ sheet chi tiết từng
/// khoản. Đổi tháng bằng nút ‹ › tại chỗ (không dùng sheet chọn tháng — sheet gắn trong List bị đóng khi List vẽ lại).
struct TinhLuongView: View {
    let shipperTen: String

    private var isNha: Bool { shipperTen == "Nhã" }

    @State private var currentDate = Date()
    @State private var luong: LuongShipperDto?
    @State private var hasLoaded = false
    /// Chặn lượt load cũ (đổi tháng nhanh) ghi đè, và báo khi tải lỗi thay vì hiện 0đ.
    @State private var loadFailed = false
    @State private var loadGeneration = 0
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
        if isNha { return luongHienTai - (luong.chiUng + luong.chiXang) }
        return luong.doanhThuShip * tiLe - (luongHienTai + luong.chiXang)
    }

    private var tieuDeThang: String {
        let cal = Calendar.current
        return "Tháng \(cal.component(.month, from: currentDate))/\(cal.component(.year, from: currentDate))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { doiThang(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(tieuDeThang).font(.subheadline.weight(.semibold))
                Spacer()
                Button { doiThang(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.borderless)
            .tint(.brandPrimary)

            if !hasLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                if loadFailed {
                    Text("Chưa tải được số liệu tháng này — kéo xuống để thử lại.")
                        .font(.caption).foregroundColor(.dangerColor)
                }
                if isNha {
                    AmountRow(label: "Ứng \(shipperTen)", value: luong?.chiUng ?? 0)
                } else {
                    AmountRow(label: "Đơn \(shipperTen) ship", value: luong?.doanhThuShip ?? 0)
                }
                AmountRow(label: "Chi xăng \(shipperTen)", value: luong?.chiXang ?? 0)
                Divider()
                if !isNha {
                    HStack {
                        Text("Tỉ lệ lợi nhuận").font(.subheadline)
                        Spacer()
                        TextField("40", text: $tiLeText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("%").foregroundColor(.textMuted)
                    }
                }
                HStack {
                    Text("Lương hiện tại").font(.subheadline)
                    Spacer()
                    TextField("10.000.000", text: $luongHienTaiText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: luongHienTaiText) { newValue in
                            let formatted = Self.formatThousands(newValue)
                            if formatted != newValue { luongHienTaiText = formatted }
                        }
                    Text("đ").foregroundColor(.textMuted)
                }
                Divider()
                if let ketQua {
                    let mau: Color = ketQua > 0 ? .successColor : ketQua == 0 ? .warningColor : .dangerColor
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Kết quả").font(.subheadline.weight(.semibold))
                            Text(ketQua > 0 ? "Có lời" : ketQua == 0 ? "Hoà vốn" : "Lỗ vốn")
                                .font(.caption).foregroundColor(mau)
                        }
                        Spacer()
                        Text(HoaDonFormatting.money(ketQua))
                            .font(.title3.weight(.bold)).monospacedDigit()
                            .foregroundColor(mau)
                    }
                }
                Text(isNha
                     ? "Kết quả = Lương hiện tại − (Ứng \(shipperTen) + Chi xăng)"
                     : "Kết quả = Đơn ship × tỉ lệ − (Lương hiện tại + Chi xăng)")
                    .font(.caption2).foregroundColor(.textMuted)
            }
        }
        .task { if !hasLoaded { await load() } }
    }

    private func doiThang(_ buoc: Int) {
        guard let d = Calendar.current.date(byAdding: .month, value: buoc, to: currentDate) else { return }
        currentDate = d
        Task { await load() }
    }

    private func load() async {
        let cal = Calendar.current
        let thang = cal.component(.month, from: currentDate)
        let nam = cal.component(.year, from: currentDate)

        loadGeneration += 1
        let generation = loadGeneration

        let l = await APIClient.shared.getLuongShipperThang(ten: shipperTen, thang: thang, nam: nam)
        guard generation == loadGeneration else { return }   // đã đổi sang tháng khác — bỏ kết quả cũ
        luong = l
        loadFailed = l == nil
        hasLoaded = true
    }
}
