import SwiftUI
import UIKit

// Tông xanh navy chuyên nghiệp, khớp COLORS.primary của AppShippingIOS (src/theme.ts).
extension Color {
    // brandPrimary: navy, đổi theo dịp lễ — xem DipLe.swift.
    static let textMuted = Color(red: 0x6C / 255, green: 0x75 / 255, blue: 0x7D / 255)
    static let successColor = Color(red: 0x19 / 255, green: 0x87 / 255, blue: 0x54 / 255)
    static let dangerColor = Color(red: 0xDC / 255, green: 0x35 / 255, blue: 0x45 / 255)
    static let warningColor = Color(red: 0xFF / 255, green: 0xC1 / 255, blue: 0x07 / 255)
    static let pinkColor = Color(red: 0xD6 / 255, green: 0x33 / 255, blue: 0x84 / 255)

    /// Trộn với trắng ra bản pastel đặc (không dùng opacity) — dùng làm nền card, giống cách Mobile
    /// web tô nền card bằng 1 màu pastel cố định thay vì border color mờ đi (opacity phụ thuộc nền
    /// phía sau, dễ ra xám/đậm khác ý muốn, nhất là dark mode).
    func pastelBackground(_ amount: CGFloat = 0.82) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func mix(_ c: CGFloat) -> CGFloat { c + (1 - c) * amount }
        return Color(red: mix(r), green: mix(g), blue: mix(b))
    }
}

// 09/11/2026: style app khách (AppDatHangIOS Theme.swift) — gradient chéo màu chủ đạo → tối cho thanh trên,
// nền xám #F5F5F5, thẻ trắng bo 18 có bóng nhẹ.
extension Color {
    /// Nền xám trung tính — cùng Theme.bg app khách (thay systemGroupedBackground ở các tab chính).
    static let appNen = Color(red: 0xF5 / 255, green: 0xF5 / 255, blue: 0xF5 / 255)
    /// Bản tối của màu chủ đạo (navy #1E4E8C → ~#15375F, khớp primaryDark app khách) — tính theo màu hiện tại để dịp
    /// lễ đổi màu thì gradient đổi theo.
    static var brandPrimaryDark: Color { brandPrimary.toiHon(0.7) }
    /// Gradient chéo sáng→tối — thanh trên (header tự vẽ + toolbarBackground) và nút chính.
    static var brandGradient: LinearGradient {
        LinearGradient(colors: [.brandPrimary, .brandPrimaryDark], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    func toiHon(_ heSo: CGFloat) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(red: r * heSo, green: g * heSo, blue: b * heSo)
    }
}

/// Nền thẻ ở các tab chính: trắng bo 18 có bóng nhẹ (cùng cardBoxStyle app khách), tuỳ chọn phủ màu nhạt (vd màu
/// phân loại đơn). Dùng trong `.background(TheNen(...))`.
struct TheNen: View {
    var phu: Color? = nil
    var vien: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
            .overlay {
                if let phu { RoundedRectangle(cornerRadius: 18, style: .continuous).fill(phu) }
            }
            .overlay {
                if let vien { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(vien, lineWidth: 1.5) }
            }
    }
}

/// Vòng loading toàn màn hình dùng chung mọi tab — mặc định ProgressView() màu xám hệ thống, kích
/// thước nhỏ, dễ tưởng app treo trên nền sáng (cùng feedback đã sửa bên AppDatHangIOS 2026-09-18:
/// "mờ lắm, cứ tưởng app bị treo"). Phóng to 1.4x + tint brandPrimary cho rõ ràng là đang tải.
func fullScreenLoading() -> some View {
    ProgressView()
        .scaleEffect(1.4)
        .tint(.brandPrimary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

enum HoaDonFormatting {
    static let moneyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        f.locale = Locale(identifier: "vi_VN")
        f.maximumFractionDigits = 0
        return f
    }()

    static func money(_ value: Double) -> String {
        (moneyFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))") + "đ"
    }

    /// Viết tắt cho footer (vd "1807k") — không cần rõ số, chỉ cần ước lượng nhanh.
    static func moneyShort(_ value: Double) -> String {
        "\(Int((value / 1000).rounded()))k"
    }

    private static let isoInFormats: [DateFormatter] = {
        ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS"].map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }
    }()

    static func time(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "--:--" }
        for f in isoInFormats {
            if let date = f.date(from: iso) {
                let hm = DateFormatter()
                hm.dateFormat = "HH:mm"
                return hm.string(from: date)
            }
        }
        guard iso.count >= 16 else { return "--:--" }
        let start = iso.index(iso.startIndex, offsetBy: 11)
        let end = iso.index(start, offsetBy: 5)
        return String(iso[start..<end])
    }

    /// Dùng cho dòng "Ghi nợ" trên tab Công nợ — chỉ cần Ngày/Tháng Giờ:Phút, không cần năm/giây.
    static func congNoTime(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "--:-- --/--" }
        for f in isoInFormats {
            if let date = f.date(from: iso) {
                let out = DateFormatter()
                out.dateFormat = "HH:mm dd/MM"
                out.locale = Locale(identifier: "vi_VN")
                return out.string(from: date)
            }
        }
        return "--:-- --/--"
    }

    /// Số phút trôi qua từ ngayGio tới hiện tại — dùng cho badge "chờ" trên card list, xem
    /// HoaDonRowView.waitingMinutes (đóng băng tại thời điểm ghi nợ/thanh toán/đi ship nếu đã xảy ra).
    static func minutesSince(_ iso: String?, now: Date = Date()) -> Int? {
        guard let date = parseIso(iso) else { return nil }
        return max(0, Int(now.timeIntervalSince(date) / 60))
    }

    /// Mốc đóng băng thời gian chờ — sau mốc đó khách không còn "chờ" nữa nên số phút phải đứng
    /// yên, không tiếp tục chạy theo `now`. Đơn chưa có mốc nào thì vẫn chạy live theo `now`.
    /// - Ship/AppDatHang: CHỈ dừng ở lúc đi ship. KHÔNG tính ngayThanhToan — đơn App Đenn khách
    ///   chuyển khoản ngay lúc đặt nên trước đây badge đứng ở "0 phút" dù món chưa giao. Chưa đi
    ///   ship mà đã ghi nợ thì dừng ở ngayNo (đơn coi như xong, tránh chạy mãi).
    /// - Loại khác (Tại chỗ/Mv/Mh/App): mốc SỚM NHẤT trong ghi nợ/thanh toán/đi ship.
    static func waitingEndDate(_ item: HoaDonListDto, now: Date) -> Date {
        if item.phanLoai == "Ship" || item.phanLoai == "AppDatHang" {
            return parseIso(item.ngayShip) ?? parseIso(item.ngayNo) ?? now
        }
        let candidates = [item.ngayNo, item.ngayThanhToan, item.ngayShip].compactMap { parseIso($0) }
        return candidates.min() ?? now
    }

    static func parseIso(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        for f in isoInFormats {
            if let date = f.date(from: iso) { return date }
        }
        return nil
    }

    /// "12 phút" nếu <1h, "1g05p" nếu >=1h.
    static func waitingText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) phút" }
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)g\(String(format: "%02d", m))p"
    }

    static func phanLoaiLabel(_ phanLoai: String?) -> String {
        switch phanLoai {
        case "Tại Chỗ": return "Tại chỗ"
        case "Mv": return "Mua về"
        case "Mh": return "Mua hộ"
        case "App": return "App"
        // AppDatHang (đơn qua app khách của quán, thêm 2026-09-06) — trước khi thêm dòng này, rơi
        // vào default và hiện SAI thành "Ship" (không phải chỉ thiếu phân biệt, mà hiện nhầm loại
        // khác hẳn — mirror đúng bug đã tìm thấy và sửa ở Desktop HoaDonTabControl.xaml).
        case "AppDatHang": return "App Đenn"
        default: return "Ship"
        }
    }

    /// Ghi chú đơn app khách mở đầu bằng emoji hình thức thanh toán (AppDatHangIOS CheckoutView /
    /// Android CheckoutScreen: "🟡 Đã thanh toán bằng Xu", "💵 Thanh toán khi nhận hàng", "📱 Chuyển
    /// khoản QR") — dữ liệu thật, app khách còn đọc lại nên không đổi ở nguồn; chỉ đổi sang SF Symbol
    /// khi hiển thị. Emoji lạ khác ở đầu cũng bỏ, dùng icon ghi chú mặc định.
    static func tachIconGhiChu(_ ghiChu: String) -> (icon: String, text: String) {
        let map: [(String, String)] = [("💵", AppIcon.tienMat), ("📱", "qrcode"), ("🟡", AppIcon.viXu)]
        for (emoji, icon) in map where ghiChu.hasPrefix(emoji) {
            return (icon, ghiChu.dropFirst(emoji.count).trimmingCharacters(in: .whitespaces))
        }
        if let first = ghiChu.unicodeScalars.first, first.properties.isEmojiPresentation {
            return ("note.text", String(ghiChu.drop { $0.unicodeScalars.first?.properties.isEmojiPresentation == true || $0 == " " }))
        }
        return ("note.text", ghiChu)
    }

    static func phanLoaiColor(_ phanLoai: String?) -> Color {
        switch phanLoai {
        case "Tại Chỗ": return .successColor
        case "Mv": return .warningColor
        case "Mh": return .pinkColor
        case "App": return .dangerColor
        // App Đenn (đơn khách đặt qua app) màu tím riêng — chủ quán 2026-11-08: "Ship và App Đenn đang bị trùng màu"
        // (trước đây cố ý dùng chung màu Ship như Desktop).
        case "AppDatHang": return .thongKePurple
        default: return .brandPrimary
        }
    }

    /// Màu CHỮ trên nền card pastel: vàng cảnh báo nhạt chìm trên nền vàng nhạt nên đậm lại thành hổ phách.
    static let amberText = Color(red: 0.60, green: 0.38, blue: 0.0)

    static func phanLoaiTextColor(_ phanLoai: String?) -> Color {
        phanLoai == "Mv" ? amberText : phanLoaiColor(phanLoai)
    }

    /// Khớp PhanLoai.NeedKhachHang (Desktop, HoaDonDomain.cs) — 4 phân loại này cần SĐT/địa chỉ giao.
    static func needKhachHang(_ phanLoai: String?) -> Bool {
        phanLoai == "Ship" || phanLoai == "Mh" || phanLoai == "App" || phanLoai == "AppDatHang"
    }

    /// Khớp PhanLoai.HasAutoDiscount (Desktop) — App/Mua hộ tự giảm 5%, làm tròn 1000 gần nhất
    /// (PricingService.RoundToNearest1000), trừ khi người dùng đã tự sửa tay giảm giá.
    static func autoGiamGia(phanLoai: String?, tongTien: Double, manual: Bool) -> Double? {
        if manual { return nil }
        guard phanLoai == "App" || phanLoai == "Mh" else { return 0 }
        let raw = tongTien * 0.05
        let remainder = raw.truncatingRemainder(dividingBy: 1000)
        return remainder < 500 ? raw - remainder : raw + (1000 - remainder)
    }

    /// Khớp FormatDiem (Desktop, HoaDonEditWindow.KhachHang.cs) — 100 điểm raw = 1.0 hiển thị.
    static func diemDisplay(_ rawDiem: Int) -> String {
        String(format: "%.1f", Double(rawDiem) / 100.0)
    }

    /// Port y hệt HoaDonSortService.GetSortOrder (Desktop) / AppMobileAndroid HoaDonTabFragment.sortPriority.
    /// Đơn Ghi nợ rớt xuống ưu tiên thấp nhất (7) BẤT KỂ phân loại — check "isNo" phải nằm TRƯỚC nhánh
    /// Ship-chưa-gán-shipper, sai thứ tự if/else ở đây từng khiến kết quả sai.
    static func sortPriority(_ item: HoaDonListDto) -> Int {
        let phanLoai = item.phanLoai
        let conLai = item.conLai
        // AppDatHang (đơn qua app khách của quán) cùng bản chất giao hàng với Ship — phải xếp CÙNG
        // mức ưu tiên, không thì đơn app khách chưa gán shipper rớt xuống ưu tiên 4 (ngang Tại Chỗ)
        // thay vì 1 (mirror đúng bug đã sửa ở Desktop HoaDonSortService.GetSortOrder).
        let laGiaoHang = phanLoai == "Ship" || phanLoai == "AppDatHang"
        let chuaCoShipper = laGiaoHang && (item.nguoiShip?.isEmpty ?? true)
        let isNo = !(item.ngayNo?.isEmpty ?? true)

        if conLai <= 0.0 && laGiaoHang && chuaCoShipper { return 1 }
        if conLai <= 0.0 { return 6 }
        if isNo { return 7 }
        if laGiaoHang && chuaCoShipper { return 1 }
        if laGiaoHang { return 5 }
        if phanLoai == "Mv" || phanLoai == "Mh" { return 2 }
        if phanLoai == "App" { return 3 }
        return 4 // Tại Chỗ
    }
}
