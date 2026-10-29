import SwiftUI

/// 1 thiết bị khách đang đăng nhập app đặt hàng + bản app nó đang chạy (GET /api/KhachHang/phien-ban-app).
struct KhachHangPhienBanAppDto: Decodable, Identifiable {
    let khachHangId: String
    let tenKhachHang: String?
    let soDienThoai: String?
    let nenTang: String?
    let thietBi: String?
    let phienBanApp: String?
    let lanCuoiHoatDong: String?

    var id: String { "\(khachHangId)|\(thietBi ?? "")|\(lanCuoiHoatDong ?? "")" }
    /// Nhóm thống kê: "iOS · 1.0.3 (551)". Android bản cũ chưa gửi phiên bản → "chưa rõ".
    var nhom: String { "\(nenTang ?? "?") · \(phienBanApp ?? "chưa rõ")" }
}

/// "Phiên bản app khách" (Trợ lý ảo > App Đặt Hàng, trước 28/10/2026 ở Menu > Công cụ) — khách nào đang dùng bản app nào. Dùng trước khi nâng
/// phiên bản tối thiểu (cổng chặn cập nhật) để biết còn bao nhiêu máy chạy bản cũ. Backend chỉ ghi nhận từ
/// 17/10/2026, iPhone bản cũ hiện dạng "build 546" (suy từ User-Agent).
struct PhienBanAppKhachView: View {
    @State private var items: [KhachHangPhienBanAppDto] = []
    @State private var dangTai = true
    @State private var locNhom: String?

    /// 29/10/2026 user "chia đôi iphone và android, sắp lại thứ tự": mỗi nền tảng 1 khối, bản mới nhất lên đầu.
    private func thongKe(android: Bool) -> [(nhom: String, phienBan: String, soMay: Int)] {
        Dictionary(grouping: items.filter { ($0.nenTang?.lowercased() == "android") == android }, by: \.nhom)
            .map { (nhom: $0.key, phienBan: $0.value.first?.phienBanApp ?? "chưa rõ", soMay: $0.value.count) }
            .sorted { Self.soBuild($0.phienBan) > Self.soBuild($1.phienBan) }
    }

    /// Số build để xếp: "1.0.6 (654)" → 654, "build 551" → 551, "chưa rõ" → -1 (xuống cuối).
    static func soBuild(_ s: String) -> Int {
        let so = s.split(whereSeparator: { !$0.isNumber })
        guard s.contains("(") || s.hasPrefix("build"), let cuoi = so.last else { return -1 }
        return Int(cuoi) ?? -1
    }

    private var hienThi: [KhachHangPhienBanAppDto] {
        guard let locNhom else { return items }
        return items.filter { $0.nhom == locNhom }
    }

    var body: some View {
        List {
            if dangTai && items.isEmpty {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else if items.isEmpty {
                Section { Text("Chưa có thiết bị nào được ghi nhận.").foregroundStyle(.secondary) }
            } else {
                ForEach([false, true], id: \.self) { android in
                    let dongs = thongKe(android: android)
                    if !dongs.isEmpty {
                        Section {
                            ForEach(dongs, id: \.nhom) { dong in
                                Button {
                                    locNhom = locNhom == dong.nhom ? nil : dong.nhom
                                } label: {
                                    HStack {
                                        Image(systemName: locNhom == dong.nhom ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(locNhom == dong.nhom ? Color.brandPrimary : .secondary)
                                        Text(dong.phienBan).foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(dong.soMay) máy").foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Text("\(android ? "Android" : "iPhone") · \(dongs.reduce(0) { $0 + $1.soMay }) máy · bấm để lọc")
                        }
                    }
                }

                Section(locNhom ?? "Tất cả") {
                    ForEach(hienThi) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.tenKhachHang ?? "?").font(.body.weight(.medium))
                                Spacer()
                                Text(item.phienBanApp ?? "chưa rõ")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                            Text([item.soDienThoai, item.thietBi ?? item.nenTang].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(Self.truoc(item.lanCuoiHoatDong))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Phiên bản app khách")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await tai() }
        .task { await tai() }
    }

    private func tai() async {
        dangTai = true
        items = await APIClient.shared.getPhienBanAppKhach()
        if let locNhom, !items.contains(where: { $0.nhom == locNhom }) { self.locNhom = nil }
        dangTai = false
    }

    /// "Hoạt động 5 phút trước" — backend ghi giãn nhịp 30 phút/lần nên chỉ là ước lượng.
    static func truoc(_ iso: String?) -> String {
        guard let phut = HoaDonFormatting.minutesSince(iso) else { return "" }
        if phut < 60 { return "Hoạt động \(phut) phút trước" }
        if phut < 24 * 60 { return "Hoạt động \(phut / 60) giờ trước" }
        return "Hoạt động \(phut / (24 * 60)) ngày trước"
    }
}
