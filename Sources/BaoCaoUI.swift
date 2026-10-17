import Charts
import SwiftUI

// Bộ thành phần trình bày số liệu dùng chung (18/10/2026) — rút từ màn Trợ lý ảo, user khen "trình bày rất
// chuyên nghiệp" rồi yêu cầu áp sang Phân tích bão hoà, Giờ vắng khách, Tồn kho, tab Kê. Nguyên tắc:
// 1. Kết luận trước (thẻ kết luận / con số lớn), chi tiết sau.
// 2. Số luôn kèm so sánh có mốc (nhãn ↑/↓ "so với hôm qua cùng giờ").
// 3. Màu theo MucDo thống nhất cả app: đỏ = xấu/hết, cam = cảnh báo, xanh = tốt.
// 4. Số canh phải + monospacedDigit, trục biểu đồ rút gọn (5tr, 750k).
// 5. Chi tiết dài thu gọn, chạm mới mở.

/// Mức độ của 1 chỉ số — quyết định màu + icon ở mọi màn báo cáo.
enum MucDo {
    case tot, canhBao, xau, trungTinh

    var mau: Color {
        switch self {
        case .tot: return .green
        case .canhBao: return .orange
        case .xau: return .red
        case .trungTinh: return .brandPrimary
        }
    }

    var icon: String {
        switch self {
        case .tot: return "checkmark.seal.fill"
        case .canhBao: return "exclamationmark.triangle.fill"
        case .xau: return "xmark.octagon.fill"
        case .trungTinh: return "info.circle.fill"
        }
    }
}

enum BaoCaoSo {
    /// 4.991.000 → "5tr", 1.250.000 → "1.3tr", 750.000 → "750k" (trục biểu đồ, chỗ chật).
    static func rutGon(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1_000_000 {
            let tr = v / 1_000_000
            return (tr.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", tr) : String(format: "%.1f", tr)) + "tr"
        }
        if a >= 1_000 { return String(format: "%.0fk", v / 1_000) }
        return String(format: "%.0f", v)
    }

    /// % thay đổi so với kỳ trước, nil khi kỳ trước = 0.
    static func phanTram(_ nay: Double, _ truoc: Double) -> Double? {
        truoc > 0 ? (nay - truoc) / truoc * 100 : nil
    }
}

/// Nhãn so sánh ↑/↓ xanh/đỏ, nền viên thuốc.
struct NhanSoSanh: View {
    let text: String
    let tang: Bool
    /// true: tăng là tốt (doanh thu). false: tăng là xấu (chi tiêu, nợ).
    var tangLaTot = true

    var body: some View {
        let mau: Color = tang == tangLaTot ? .green : .red
        Label(text, systemImage: tang ? "arrow.up.right" : "arrow.down.right")
            .font(.footnote.weight(.semibold))
            .foregroundColor(mau)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(mau.opacity(0.12)))
    }
}

/// Con số chính cỡ lớn + dòng mô tả + nhãn so sánh.
struct SoLon: View {
    let giaTri: String
    var moTa: String?
    var soSanh: String?
    var tang: Bool?
    var tangLaTot = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(giaTri)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let moTa {
                Text(moTa).font(.subheadline).foregroundColor(.textMuted)
            }
            if let soSanh, let tang {
                NhanSoSanh(text: soSanh, tang: tang, tangLaTot: tangLaTot).padding(.top, 2)
            }
        }
    }
}

/// Thẻ kết luận đầu màn: icon lớn theo mức độ + tiêu đề + mô tả.
struct TheKetLuan: View {
    let mucDo: MucDo
    let tieuDe: String
    var moTa: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: mucDo.icon)
                .font(.system(size: 30))
                .foregroundColor(mucDo.mau)
            VStack(alignment: .leading, spacing: 2) {
                Text(tieuDe).font(.headline)
                if let moTa {
                    Text(moTa).font(.subheadline).foregroundColor(.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Khối 1 chỉ số thu gọn: icon · tên + kết luận 1 dòng (màu mức độ) · giá trị canh phải · chevron. Chạm
/// để mở phần chi tiết (biểu đồ, giải thích).
struct KhoiChiSo<Content: View>: View {
    let icon: String
    let tieuDe: String
    let ketLuan: String
    let mucDo: MucDo
    var giaTri: String?
    let moRa: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundColor(mucDo.mau)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tieuDe).font(.body.weight(.medium)).foregroundColor(.primary)
                        Text(ketLuan).font(.caption.weight(.semibold)).foregroundColor(mucDo.mau)
                    }
                    Spacer(minLength: 8)
                    if let giaTri {
                        Text(giaTri).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundColor(.primary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.textMuted)
                        .rotationEffect(.degrees(moRa ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if moRa {
                content
            }
        }
        .padding(.vertical, 4)
    }
}

/// 1 điểm của biểu đồ cộng dồn.
struct DiemCongDon: Identifiable {
    let x: Int
    let giaTri: Double
    let laKyNay: Bool
    var id: String { "\(laKyNay)|\(x)" }
}

/// Đường cộng dồn kỳ này (màu chính, có nền, chấm ở mốc cuối) so với kỳ trước (xám, nét đứt).
struct BieuDoCongDon: View {
    let diem: [DiemCongDon]
    var nhanNay = "Hôm nay"
    var nhanTruoc = "Hôm qua"
    var mau: Color = .brandPrimary
    /// Nhãn trục X: giờ → "7h", ngày → "15".
    var nhanX: (Int) -> String = { "\($0)h" }
    var buocX = 3
    var chieuCao: CGFloat = 180

    private var kyNay: [DiemCongDon] { diem.filter(\.laKyNay) }

    var body: some View {
        Chart {
            ForEach(kyNay) { d in
                AreaMark(x: .value("X", d.x), y: .value("Giá trị", d.giaTri))
                    .foregroundStyle(LinearGradient(colors: [mau.opacity(0.25), mau.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
            }
            ForEach(diem) { d in
                LineMark(x: .value("X", d.x), y: .value("Giá trị", d.giaTri),
                         series: .value("Kỳ", d.laKyNay ? nhanNay : nhanTruoc))
                    .foregroundStyle(by: .value("Kỳ", d.laKyNay ? nhanNay : nhanTruoc))
                    .lineStyle(StrokeStyle(lineWidth: d.laKyNay ? 2.5 : 1.5, dash: d.laKyNay ? [] : [4, 3]))
                    .interpolationMethod(.monotone)
            }
            if let cuoi = kyNay.last {
                PointMark(x: .value("X", cuoi.x), y: .value("Giá trị", cuoi.giaTri))
                    .foregroundStyle(mau)
            }
        }
        .chartForegroundStyleScale([nhanNay: mau, nhanTruoc: Color.gray.opacity(0.6)])
        .chartXAxis {
            AxisMarks(values: .stride(by: Double(buocX))) { v in
                AxisGridLine()
                AxisValueLabel { if let x = v.as(Int.self) { Text(nhanX(x)) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine()
                AxisValueLabel { if let y = v.as(Double.self) { Text(BaoCaoSo.rutGon(y)) } }
            }
        }
        .chartLegend(position: .top, alignment: .trailing)
        .frame(height: chieuCao)
    }
}

/// Khối tổng quan doanh thu đầu tab Kê (ngày/tháng): số lớn + nhãn so với kỳ trước + đường nhịp bán.
struct TongQuanDoanhThuCard: View {
    let nhip: NhipDoanhThuDto
    /// true: kỳ ngày (trục giờ). false: kỳ tháng (trục ngày).
    let theoNgay: Bool

    private var diem: [DiemCongDon] {
        nhip.diem.map { DiemCongDon(x: $0.x, giaTri: $0.giaTri, laKyNay: $0.nhom == "nay") }
    }

    var body: some View {
        let pt = BaoCaoSo.phanTram(nhip.tong, nhip.tongKyTruoc)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Doanh thu", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.thongKeGreen)
                Spacer()
            }
            SoLon(
                giaTri: HoaDonFormatting.money(nhip.tong),
                moTa: "\(nhip.soDon) đơn",
                soSanh: pt.map { "\($0 >= 0 ? "+" : "−")\(Int(abs($0).rounded()))% so với \(nhip.nhanKyTruoc) (\(HoaDonFormatting.money(nhip.tongKyTruoc)))" },
                tang: pt.map { $0 >= 0 }
            )
            if diem.contains(where: { $0.giaTri > 0 }) {
                BieuDoCongDon(
                    diem: diem,
                    nhanNay: theoNgay ? "Ngày này" : "Tháng này",
                    nhanTruoc: theoNgay ? "Hôm trước" : "Tháng trước",
                    mau: .thongKeGreen,
                    nhanX: theoNgay ? { "\($0)h" } : { "\($0)" },
                    buocX: theoNgay ? 3 : 5,
                    chieuCao: 160
                )
            }
        }
        .padding(14)
        .background(Color.thongKeGreen.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}
