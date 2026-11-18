import CoreLocation
import SwiftUI
import UIKit

// Bản đồ khách hàng offline (18/11/2026): lớp ĐỊA DANH LỚN để định hướng (công an, UBND, cây xăng, chuỗi bán lẻ…)
// + THẺ KHÁCH khi chạm chấm khách. Xem BanDoOfflineView.swift.

/// Loại địa danh — mã khớp backend (BanDoOsmService.LoaiDiaDanh) và script nền (build-ban-do-nen.py, k = "dd").
enum LoaiDiaDanh {
    struct Kieu {
        let icon: String
        let mau: UIColor
    }

    static let kieu: [String: Kieu] = [
        "cong-an": Kieu(icon: "shield.fill", mau: hex(0x1E3A8A)),
        "ubnd": Kieu(icon: "building.columns.fill", mau: hex(0xB91C1C)),
        "xang": Kieu(icon: "fuelpump.fill", mau: hex(0xEA580C)),
        "cho": Kieu(icon: "basket.fill", mau: hex(0x92400E)),
        "truong": Kieu(icon: "graduationcap.fill", mau: hex(0x2563EB)),
        "y-te": Kieu(icon: "cross.case.fill", mau: hex(0xDC2626)),
        "ton-giao": Kieu(icon: "bell.fill", mau: hex(0x7C3AED)),
        "ngan-hang": Kieu(icon: "banknote.fill", mau: hex(0x047857)),
        "sieu-thi": Kieu(icon: "cart.fill", mau: hex(0x15803D)),
        "dien-thoai": Kieu(icon: "iphone", mau: hex(0xCA8A04)),
        "dien-may": Kieu(icon: "tv.fill", mau: hex(0x0369A1)),
        "nha-thuoc": Kieu(icon: "pills.fill", mau: hex(0x0E7490)),
        "me-be": Kieu(icon: "figure.and.child.holdinghands", mau: hex(0xDB2777)),
        "thoi-trang": Kieu(icon: "tshirt.fill", mau: hex(0xA16207)),
        "the-thao": Kieu(icon: "sportscourt.fill", mau: hex(0x16A34A)),
        "khac": Kieu(icon: "mappin", mau: hex(0x4B5563)),
    ]

    static var tatCaMa: [String] { Array(kieu.keys) }

    /// Nút chọn nhanh khi thêm: loại + tên gợi ý (chuỗi lớn điền sẵn tên, nhân viên chỉ cần bấm Lưu).
    struct MauNhanh: Identifiable {
        let id: String
        let loai: String
        let ten: String
    }

    static let mauNhanh: [MauNhanh] = danhSachMau.map { MauNhanh(id: $0.0, loai: $0.1, ten: $0.2) }

    /// (nhãn nút, loại, tên điền sẵn) — khai kiểu rõ để Swift type-check nhanh trên CI.
    private static let danhSachMau: [(String, String, String)] = [
        ("Công an", "cong-an", "Công an "), ("UBND", "ubnd", "UBND "), ("Cây xăng", "xang", "Cây xăng "),
        ("Chợ", "cho", "Chợ "), ("Trường học", "truong", "Trường "), ("Bệnh viện / Trạm y tế", "y-te", ""),
        ("Nhà thờ / Chùa", "ton-giao", ""), ("Ngân hàng", "ngan-hang", ""), ("Sân / Công viên", "the-thao", ""),
        ("Bách Hoá Xanh", "sieu-thi", "Bách Hoá Xanh"), ("WinMart", "sieu-thi", "WinMart+"),
        ("Thế Giới Di Động", "dien-thoai", "Thế Giới Di Động"), ("FPT Shop", "dien-thoai", "FPT Shop"),
        ("Viettel Store", "dien-thoai", "Viettel Store"), ("Điện Máy Xanh", "dien-may", "Điện Máy Xanh"),
        ("Long Châu", "nha-thuoc", "Nhà thuốc Long Châu"), ("Pharmacity", "nha-thuoc", "Pharmacity"),
        ("An Khang", "nha-thuoc", "Nhà thuốc An Khang"), ("Con Cưng", "me-be", "Con Cưng"),
        ("Yody", "thoi-trang", "Yody"), ("Khác", "khac", ""),
    ]

    private static func hex(_ v: Int) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func kieuCua(_ loai: String) -> Kieu { kieu[loai] ?? kieu["khac"]! }

    /// Biểu tượng trên bản đồ: vòng tròn màu viền trắng + SF Symbol trắng (MapLibre cần UIImage).
    static func bieuTuong(_ loai: String) -> UIImage {
        let k = kieuCua(loai)
        let co: CGFloat = 24
        return UIGraphicsImageRenderer(size: CGSize(width: co, height: co)).image { _ in
            let vong = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: co - 2, height: co - 2))
            k.mau.setFill()
            vong.fill()
            UIColor.white.setStroke()
            vong.lineWidth = 1.5
            vong.stroke()
            let cfg = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
            let anh = (UIImage(systemName: k.icon, withConfiguration: cfg) ?? UIImage(systemName: "mappin", withConfiguration: cfg))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            if let anh {
                anh.draw(in: CGRect(x: (co - anh.size.width) / 2, y: (co - anh.size.height) / 2,
                                    width: anh.size.width, height: anh.size.height))
            }
        }
    }
}

/// Thêm / sửa địa danh tại điểm vừa nhấn giữ (hoặc vị trí đang đứng).
struct ThemDiaDanhSheet: View {
    let nhap: DiaDanhNhap
    @ObservedObject var viTri: ViTriHienTai
    let onLuu: (_ ten: String, _ loai: String, _ toaDo: CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten = ""
    @State private var loai = "khac"
    @State private var mauChon: String?
    @State private var dungViTriDangDung = false

    private let cot = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Chọn nhanh") {
                    LazyVGrid(columns: cot, alignment: .leading, spacing: 8) {
                        ForEach(LoaiDiaDanh.mauNhanh) { mn in
                            Button { chon(mn) } label: { nhan(mn) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section("Tên hiện trên bản đồ") {
                    TextField("VD: Công an xã Ea Phê", text: $ten)
                }
                Section {
                    Toggle("Dùng vị trí tôi đang đứng", isOn: $dungViTriDangDung)
                        .tint(.brandPrimary)
                        .disabled(viTri.hienTai == nil)
                } footer: {
                    Text(dungViTriDangDung
                         ? "Lấy GPS (sai số ~\(Int(viTri.hienTai?.horizontalAccuracy.rounded() ?? 0))m)."
                         : (nhap.id == nil ? "Đặt tại điểm vừa nhấn giữ trên bản đồ." : "Giữ nguyên vị trí cũ."))
                }
            }
            .navigationTitle(nhap.id == nil ? "Thêm địa danh" : "Sửa địa danh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        let toaDo = dungViTriDangDung ? (viTri.hienTai?.coordinate ?? nhap.toaDo) : nhap.toaDo
                        onLuu(ten.trimmingCharacters(in: .whitespaces), loai, toaDo)
                        dismiss()
                    }
                    .bold()
                    .disabled(ten.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                ten = nhap.ten
                loai = nhap.loai ?? "khac"
                mauChon = LoaiDiaDanh.mauNhanh.first { $0.loai == loai && (!$0.ten.isEmpty && nhap.ten.hasPrefix($0.ten.trimmingCharacters(in: .whitespaces))) }?.id
            }
        }
        .presentationDetents([.large])
    }

    private func chon(_ mn: LoaiDiaDanh.MauNhanh) {
        // Đổi tên theo mẫu nếu ô tên đang trống hoặc vẫn là tên mẫu trước đó (không đè tên đã gõ tay).
        let tenMauCu = LoaiDiaDanh.mauNhanh.first { $0.id == mauChon }?.ten ?? ""
        if ten.trimmingCharacters(in: .whitespaces).isEmpty || ten == tenMauCu {
            ten = mn.ten
        }
        loai = mn.loai
        mauChon = mn.id
    }

    private func nhan(_ mn: LoaiDiaDanh.MauNhanh) -> some View {
        let dangChon = mauChon == mn.id
        let k = LoaiDiaDanh.kieuCua(mn.loai)
        return HStack(spacing: 5) {
            Image(uiImage: LoaiDiaDanh.bieuTuong(mn.loai)).resizable().frame(width: 18, height: 18)
            Text(mn.id).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(dangChon ? Color(uiColor: k.mau).opacity(0.15) : Color.textMuted.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(dangChon ? Color(uiColor: k.mau) : .clear, lineWidth: 1.2))
    }
}

// MARK: - Khách trên bản đồ

enum KhachTrenBanDo {
    /// Nhãn trên bản đồ: tên gọn ≤ 18 ký tự.
    static func tenNgan(_ k: MapCustomerDto) -> String {
        let t = (k.ten ?? "").trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return k.soDienThoai ?? "Khách" }
        return t.count > 18 ? String(t.prefix(17)) + "…" : t
    }

    static func nguon(_ ma: String?) -> String? {
        switch ma {
        case "Store": return "App Shipping Store"
        case "Quay": return "Quầy"
        case "App": return "App Đenn"
        case "Shipper": return "Shipper"
        default: return nil
        }
    }

    /// "2026-11-18T14:08:58" → "18/11/2026".
    static func ngay(_ iso: String?) -> String? {
        guard let iso, iso.count >= 10 else { return nil }
        let p = iso.prefix(10).split(separator: "-")
        guard p.count == 3 else { return nil }
        return "\(p[2])/\(p[1])/\(p[0])"
    }
}

/// Chạm chấm khách: 1 người → thẻ khách; nhiều người cùng chỗ → danh sách rồi chọn.
struct KhachTrenBanDoSheet: View {
    let ds: [MapCustomerDto]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if ds.count == 1, let k = ds.first {
                    TheKhachBanDo(k: k)
                } else {
                    List(Array(ds.enumerated()), id: \.offset) { _, k in
                        NavigationLink { TheKhachBanDo(k: k) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(k.ten ?? "Khách").font(.body.weight(.semibold))
                                Text([k.soDienThoai, KhachTrenBanDo.ngay(k.muaGanNhat).map { "mua \($0)" }]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundColor(.textMuted)
                            }
                        }
                    }
                    .navigationTitle("\(ds.count) khách cùng địa chỉ")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct TheKhachBanDo: View {
    let k: MapCustomerDto

    var body: some View {
        List {
            Section {
                if let sdt = k.soDienThoai, !sdt.isEmpty {
                    HStack {
                        Label(sdt, systemImage: "phone.fill")
                        Spacer()
                        if let url = URL(string: "tel:\(sdt)") {
                            Link("Gọi", destination: url).bold().foregroundColor(.brandPrimary)
                        }
                    }
                    .contextMenu { Button("Sao chép số") { UIPasteboard.general.string = sdt } }
                }
                if let dc = k.diaChi, !dc.isEmpty {
                    Label(dc, systemImage: "house.fill")
                        .textSelection(.enabled)
                }
            }
            Section("Mua hàng") {
                if k.nguonKhach == "Store" && (k.soDon ?? 0) == 0 {
                    Text("Đặt qua App Shipping Store — đơn store gắn theo shipper nên không đếm được ở đây.")
                        .font(.footnote).foregroundColor(.textMuted)
                } else {
                    HStack {
                        Text("Số đơn")
                        Spacer()
                        Text("\(k.soDon ?? 0)").bold()
                    }
                    if let ngay = KhachTrenBanDo.ngay(k.muaGanNhat) {
                        HStack {
                            Text("Mua gần nhất")
                            Spacer()
                            Text(ngay).bold()
                        }
                    }
                }
                if let nguon = KhachTrenBanDo.nguon(k.nguonKhach) {
                    HStack {
                        Text("Nguồn khách")
                        Spacer()
                        Text(nguon).foregroundColor(.textMuted)
                    }
                }
            }
        }
        .navigationTitle(k.ten ?? "Khách")
    }
}
