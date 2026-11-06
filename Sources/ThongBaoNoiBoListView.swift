import SwiftUI

/// Lịch sử thông báo nghiệp vụ (icon chuông, đầu tab Hoá đơn) — thay kênh Discord cũ từ 2026-10-03.
/// Mở sheet này tự đánh dấu TẤT CẢ đã xem (xoá badge đỏ), khớp hành vi mở kênh Discord đọc hết trước đây.
struct ThongBaoNoiBoListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ThongBaoNoiBoDto] = []
    @State private var hasLoaded = false
    @State private var openHoaDonId: String?
    @State private var loadingMore = false
    @State private var hasMore = true
    @State private var searchText = ""
    /// Đang tìm thì tự tải thêm trang cũ để tìm sâu hơn, nhưng dừng ở mốc này (bấm "Tìm tiếp" để nới)
    /// — không thì 1 từ khoá không khớp gì sẽ kéo về toàn bộ lịch sử thông báo.
    @State private var searchDepth = 500

    private let pageSize = 50

    /// Lọc ngay trên các thông báo đã tải (tên khách/nội dung + tên loại như "Ghi nợ", "Tiền mặt").
    private var filteredItems: [ThongBaoNoiBoDto] {
        guard !searchText.isEmpty else { return items }
        return items.filter { anyMatchesSearch(searchText, $0.noiDung, ThongBaoNoiBoFormatting.tieuDe($0.loai)) }
    }

    private var searchDepthReached: Bool { !searchText.isEmpty && items.count >= searchDepth }

    var body: some View {
        NavigationStack {
            let rows = filteredItems
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm khách, nội dung...")
                if !hasLoaded {
                    fullScreenLoading()
                } else if items.isEmpty {
                    Text("Chưa có thông báo nào")
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Self.nhomTheoNgay(rows), id: \.ten) { nhom in
                            Section {
                                ForEach(nhom.items) { item in
                                    ThongBaoNoiBoRowView(item: item)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let id = item.hoaDonId { openHoaDonId = id }
                                        }
                                        .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                }
                            } header: {
                                Text(nhom.ten)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.textMuted)
                                    .textCase(nil)
                            }
                        }
                        if hasMore && searchDepthReached {
                            Button("Đã tìm trong \(items.count) thông báo gần nhất — Tìm tiếp") { searchDepth += 500 }
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else if hasMore {
                            // Dòng cuối: hiện ra là tải trang cũ hơn; còn nằm trên màn hình (kết quả tìm
                            // chưa đầy màn) thì tải tiếp sau mỗi trang.
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                                .task(id: items.count) { await loadMore() }
                        } else if rows.isEmpty {
                            Text("Không tìm thấy thông báo nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                    .softScrollEdgeTop()
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Thông báo")
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
            await load()
            // Mở xem là coi như đã đọc hết — khớp hành vi mở kênh Discord cũ, xoá badge đỏ ngay.
            _ = await APIClient.shared.markThongBaoSeen()
            await ThongBaoBadge.shared.refresh()
        }
        .sheet(item: Binding(
            get: { openHoaDonId.map { IdentifiableId($0) } },
            set: { openHoaDonId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {}
        }
    }

    /// Gom thông báo (đã sắp mới → cũ) theo ngày: "Hôm nay", "Hôm qua", còn lại "dd/MM/yyyy".
    private static func nhomTheoNgay(_ rows: [ThongBaoNoiBoDto]) -> [(ten: String, items: [ThongBaoNoiBoDto])] {
        var ketQua: [(ten: String, items: [ThongBaoNoiBoDto])] = []
        for r in rows {
            let ten = ThongBaoNoiBoFormatting.tenNgay(r.taoLuc)
            if let i = ketQua.indices.last, ketQua[i].ten == ten {
                ketQua[i].items.append(r)
            } else {
                ketQua.append((ten, [r]))
            }
        }
        return ketQua
    }

    private func load() async {
        let first = await APIClient.shared.getThongBaoNoiBoList(take: pageSize)
        items = first
        hasMore = first.count >= pageSize
        hasLoaded = true
    }

    private func loadMore() async {
        guard hasMore, !loadingMore, let last = items.last else { return }
        loadingMore = true
        defer { loadingMore = false }
        let page = await APIClient.shared.getThongBaoNoiBoList(take: pageSize, before: last.taoLuc)
        let known = Set(items.map(\.id))
        items.append(contentsOf: page.filter { !known.contains($0.id) })
        hasMore = page.count >= pageSize
    }
}

private struct ThongBaoNoiBoRowView: View {
    let item: ThongBaoNoiBoDto

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: ThongBaoNoiBoFormatting.icon(item.loai), color: ThongBaoNoiBoFormatting.mau(item.loai))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ThongBaoNoiBoFormatting.tieuDe(item.loai))
                        .font(.footnote.weight(.bold))
                        .foregroundColor(ThongBaoNoiBoFormatting.mau(item.loai))
                    Spacer(minLength: 8)
                    Text(ThongBaoNoiBoFormatting.gio(item.taoLuc))
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
                if item.loai == "HoaDonEdit" {
                    noiDungSua
                } else {
                    let dong = item.noiDung.components(separatedBy: "\n").filter { !$0.isEmpty }
                    ForEach(Array(dong.enumerated()), id: \.offset) { i, d in
                        Text(d)
                            .font(i == 0 ? .subheadline.weight(.semibold) : .footnote)
                            .foregroundColor(i == 0 ? .primary : .textMuted)
                    }
                }
            }

            if item.hoaDonId != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(.tertiaryLabel))
                    .padding(.top, 4)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                // 02/11/2026: cả thẻ đổ màu (đúng màu nền tròn icon cũ), đồng bộ tab Đơn.
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(ThongBaoNoiBoFormatting.mau(item.loai).opacity(0.14))
                )
        )
    }

    /// Thông báo "Sửa đơn": trên cùng là kết luận sửa gì (in đậm), rồi tóm tắt đơn, rồi chi tiết — "Nhãn: cũ → mới"
    /// (cũ gạch xám, mới đậm), "+ món" xanh, "- món" đỏ. Khớp HoaDonCrudService.UpdateAsync; thông báo cũ ghi "->"
    /// và để trống phần mới cũng đọc được. Dòng cũ = mới (vd "(trống) → (trống)" ở thông báo cũ) bỏ qua.
    @ViewBuilder private var noiDungSua: some View {
        let tatCa = item.noiDung.components(separatedBy: "\n").filter { !$0.isEmpty }
        let chiTiet = tatCa.dropFirst().filter { d in
            guard !Self.laDongMon(d), let (_, cu, moi) = Self.tachDoi(d) else { return true }
            return cu != moi
        }
        let ketLuan = Self.ketLuan(Array(chiTiet))
        // Chỉ đổi tiền: kết luận đã nói đủ, không lặp lại dòng chi tiết.
        let dong = (tatCa.first.map { [$0] } ?? []) + (ketLuan.chiDoiTien ? [] : chiTiet)
        VStack(alignment: .leading, spacing: 3) {
            if !ketLuan.text.isEmpty {
                Text(ketLuan.text).font(.subheadline.weight(.semibold))
            }
            ForEach(Array(dong.enumerated()), id: \.offset) { i, d in
                if i == 0 {
                    Text(d)
                        .font(ketLuan.text.isEmpty ? .subheadline.weight(.semibold) : .footnote)
                        .foregroundColor(ketLuan.text.isEmpty ? .primary : .textMuted)
                } else if d.hasPrefix("+ ") {
                    Text(String(d.dropFirst(2))).font(.subheadline).foregroundColor(.green)
                        .padding(.leading, 2)
                } else if d.hasPrefix("- ") {
                    Text(String(d.dropFirst(2))).font(.subheadline).foregroundColor(.red)
                        .strikethrough().padding(.leading, 2)
                } else if let (nhan, cu, moi) = Self.tachDoi(d) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(nhan).font(.caption).foregroundColor(.textMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(cu).strikethrough().foregroundColor(.textMuted)
                            Image(systemName: "arrow.right").font(.caption2).foregroundColor(.textMuted)
                            Text(moi).fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }
                } else {
                    Text(d).font(.subheadline)
                }
            }
        }
    }

    private static func tachDoi(_ d: String) -> (String, String, String)? {
        guard let mocNhan = d.range(of: ": ") else { return nil }
        let nhan = String(d[..<mocNhan.lowerBound])
        let con = String(d[mocNhan.upperBound...])
        for dau in [" → ", " -> "] {
            if let r = con.range(of: dau) {
                return (nhan, trong(String(con[..<r.lowerBound])), trong(String(con[r.upperBound...])))
            }
        }
        // Thông báo cũ để trống phần mới: "Tên khách: A ->".
        for dau in [" →", " ->"] where con.hasSuffix(dau) {
            return (nhan, trong(String(con.dropLast(dau.count))), "(trống)")
        }
        return nil
    }

    private static func trong(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).isEmpty ? "(trống)" : s
    }

    /// 1 dòng món theo HoaDonCrudService.ChiTietDiffLine: "Tên (Size) xSL (topping) [ghi chú]" — size mặc định
    /// không ghi.
    private struct MonDong {
        let ten: String
        let size: String
        let soLuong: String
        let topping: String
        let ghiChu: String
    }

    private static let monRegex = try! NSRegularExpression(
        pattern: #"^(.+?)(?: \(([^()]*)\))? x(\d+)(?: \((.*?)\))?(?: \[(.*)\])?$"#)

    private static func tachMon(_ s: String) -> MonDong? {
        let ns = s as NSString
        guard let m = monRegex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func nhom(_ i: Int) -> String {
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
        return MonDong(ten: nhom(1), size: nhom(2), soLuong: nhom(3), topping: nhom(4), ghiChu: nhom(5))
    }

    /// Câu kết luận ngắn: món nào đổi gì (ghép dòng "-"/"+" cùng tên món), thêm/bỏ món, đổi thông tin khách.
    /// Đổi tiền chỉ đưa vào kết luận khi đó là thay đổi duy nhất (thường do sửa giá/giảm giá).
    static func ketLuan(_ chiTiet: [String]) -> (text: String, chiDoiTien: Bool) {
        var them = chiTiet.filter { $0.hasPrefix("+ ") }.map { String($0.dropFirst(2)) }
        let bo = chiTiet.filter { $0.hasPrefix("- ") }.map { String($0.dropFirst(2)) }
        var cau: [String] = []

        for b in bo {
            if let mb = tachMon(b),
               let j = them.firstIndex(where: { tachMon($0)?.ten == mb.ten }),
               let mt = tachMon(them[j]) {
                them.remove(at: j)
                var doi: [String] = []
                if mb.size != mt.size { doi.append("size \(trongSize(mb.size)) → \(trongSize(mt.size))") }
                if mb.soLuong != mt.soLuong { doi.append("x\(mb.soLuong) → x\(mt.soLuong)") }
                if mb.topping != mt.topping {
                    doi.append(mt.topping.isEmpty ? "bỏ topping" : mb.topping.isEmpty ? "thêm \(mt.topping)" : "topping \(mt.topping)")
                }
                if mb.ghiChu != mt.ghiChu { doi.append(mt.ghiChu.isEmpty ? "bỏ ghi chú" : "ghi chú \"\(mt.ghiChu)\"") }
                cau.append("\(mb.ten): \(doi.joined(separator: ", "))")
            } else {
                cau.append("Bỏ \(b)")
            }
        }
        cau.append(contentsOf: them.map { "Thêm \($0)" })

        var tien: (String, String)?
        for d in chiTiet {
            guard !laDongMon(d), let (nhan, cu, moi) = tachDoi(d), cu != moi else { continue }
            switch nhan {
            case "Tiền": tien = (cu, moi)
            case "Phân loại": cau.append("Đổi \(cu) → \(moi)")
            default: cau.append("Đổi \(nhan == "SĐT" ? nhan : nhan.lowercased())")
            }
        }

        if cau.isEmpty, let (cu, moi) = tien {
            let giam = (Double(cu.dropLast()) ?? 0) > (Double(moi.dropLast()) ?? 0)
            return ("\(giam ? "Giảm" : "Tăng") tiền \(cu) → \(moi)", true)
        }
        return (cau.joined(separator: " · "), false)
    }

    private static func laDongMon(_ d: String) -> Bool { d.hasPrefix("+ ") || d.hasPrefix("- ") }

    private static func trongSize(_ s: String) -> String {
        s.isEmpty ? "chuẩn" : s.replacingOccurrences(of: "Size ", with: "")
    }
}

enum ThongBaoNoiBoFormatting {
    /// Khớp tên hiển thị MauThongBaoNoiBo.TieuDe bên Backend (giữ đồng bộ nếu đổi 1 bên).
    static func tieuDe(_ loai: String) -> String {
        switch loai {
        case "HoaDonNew": return "Đơn mới"
        case "HoaDonNewShip": return "Đơn Ship"
        case "HoaDonNewMuaVe": return "Mua về"
        case "HoaDonNewTaiCho": return "Tại chỗ"
        case "HoaDonNewApp": return "Đơn App"
        case "HoaDonNewMuaHo": return "Mua hộ"
        case "HoaDonNewAppDatHang": return "App Đenn"
        case "HoaDonEdit": return "Sửa đơn"
        case "HoaDonDel": return "Xoá đơn"
        case "DangGiaoHang": return "Đang giao"
        case "GhiNo": return "Ghi nợ"
        case "ThanhToanTienMat": return "Tiền mặt"
        case "ThanhToanChuyenKhoan": return "Chuyển khoản"
        case "ThanhToanBanking": return "Banking"
        case "ThanhToan": return "Thanh toán"
        case "DuyKhanh": return "Duy Khánh"
        case "DuyKhanhGhiNo": return "Khánh báo, khách ghi nợ"
        case "DuyKhanhTraNo": return "Khánh báo, khách trả nợ"
        case "DuyKhanhChuyenKhoan": return "Khánh báo, khách chuyển khoản"
        case "NhaGhiNo": return "Nhã báo, khách ghi nợ"
        case "NhaTraNo": return "Nhã báo, khách trả nợ"
        case "NhaChuyenKhoan": return "Nhã báo, khách chuyển khoản"
        case "Admin": return "Hệ thống"
        default: return "Thông báo"
        }
    }

    /// Icon emoji theo loại thông báo, thay cho chấm màu `mau` cũ. Loại lạ rơi về 🔔.
    static func icon(_ loai: String) -> String {
        switch loai {
        case "HoaDonNew": return "plus"
        case "HoaDonNewShip": return AppIcon.ship
        case "HoaDonNewMuaVe": return AppIcon.muaVe
        case "HoaDonNewTaiCho": return AppIcon.taiCho
        case "HoaDonNewApp": return AppIcon.app
        case "HoaDonNewMuaHo": return AppIcon.muaHo
        case "HoaDonNewAppDatHang": return AppIcon.appDatHang
        case "HoaDonEdit": return AppIcon.sua
        case "HoaDonDel": return AppIcon.xoa
        case "DangGiaoHang": return "box.truck.fill"
        case "GhiNo": return AppIcon.ghiNo
        case "ThanhToanTienMat": return AppIcon.tienMat
        case "ThanhToanChuyenKhoan": return AppIcon.chuyenKhoan
        case "ThanhToanBanking": return AppIcon.tuDong
        case "ThanhToan": return "dollarsign.circle.fill"
        case "DuyKhanh", "DuyKhanhGhiNo", "DuyKhanhTraNo", "DuyKhanhChuyenKhoan",
             "NhaGhiNo", "NhaTraNo", "NhaChuyenKhoan": return "person.fill"
        case "Admin": return "gearshape.fill"
        default: return "bell.fill"
        }
    }

    /// Màu nhấn khớp bảng màu dùng chung toàn app: đơn mới theo PhanLoai (HoaDonFormatting.phanLoaiColor),
    /// thanh toán theo EntityChangeBus (tiền mặt xanh lá, chuyển khoản/banking xanh dương), sửa dùng
    /// .warningColor (khớp nút "Sửa đơn" ở HoaDonDetailView/EntityChangeBus), xoá/nợ đỏ.
    static func mau(_ loai: String) -> Color {
        switch loai {
        case "HoaDonNewTaiCho": return HoaDonFormatting.phanLoaiColor("Tại Chỗ")
        case "HoaDonNewMuaVe": return HoaDonFormatting.phanLoaiColor("Mv")
        case "HoaDonNewMuaHo": return HoaDonFormatting.phanLoaiColor("Mh")
        case "HoaDonNewApp": return HoaDonFormatting.phanLoaiColor("App")
        case "HoaDonNewShip", "HoaDonNewAppDatHang": return HoaDonFormatting.phanLoaiColor("Ship")
        case "HoaDonEdit": return .warningColor
        case "HoaDonDel", "GhiNo": return .dangerColor
        case "ThanhToanTienMat": return .successColor
        case "ThanhToanChuyenKhoan", "ThanhToanBanking": return .brandPrimary
        case "ThanhToan": return .successColor
        case "DangGiaoHang": return Color(red: 0.45, green: 0.30, blue: 0.80)
        case "Admin": return .textMuted
        default: return .brandPrimary
        }
    }

    static func gio(_ iso: String) -> String {
        guard let date = HoaDonFormatting.parseIso(iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func tenNgay(_ iso: String) -> String {
        guard let date = HoaDonFormatting.parseIso(iso) else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Hôm nay" }
        if cal.isDateInYesterday(date) { return "Hôm qua" }
        let f = DateFormatter()
        f.dateFormat = "EEEE, dd/MM/yyyy"
        f.locale = Locale(identifier: "vi_VN")
        return f.string(from: date).capitalized
    }

    static func thoiGian(_ iso: String) -> String {
        guard let date = HoaDonFormatting.parseIso(iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm dd/MM"
        f.locale = Locale(identifier: "vi_VN")
        return f.string(from: date)
    }
}
