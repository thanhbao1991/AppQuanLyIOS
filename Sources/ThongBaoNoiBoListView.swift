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
            Text(ThongBaoNoiBoFormatting.emoji(item.loai))
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
                .background(Circle().fill(ThongBaoNoiBoFormatting.mau(item.loai).opacity(0.14)))

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
        )
    }

    /// Thông báo "Sửa đơn": dòng đầu là tóm tắt đơn (in đậm), các dòng sau là thay đổi — "Nhãn: cũ → mới" (cũ gạch
    /// xám, mới đậm), "+ món" xanh, "- món" đỏ. Khớp HoaDonCrudService.UpdateAsync; thông báo cũ ghi "->" và để
    /// trống phần mới cũng đọc được.
    @ViewBuilder private var noiDungSua: some View {
        let dong = item.noiDung.components(separatedBy: "\n").filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(dong.enumerated()), id: \.offset) { i, d in
                if i == 0 {
                    Text(d).font(.subheadline.weight(.semibold))
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
        case "Admin": return "Hệ thống"
        default: return "Thông báo"
        }
    }

    /// Icon emoji theo loại thông báo, thay cho chấm màu `mau` cũ. Loại lạ rơi về 🔔.
    static func emoji(_ loai: String) -> String {
        switch loai {
        case "HoaDonNew": return "➕"
        case "HoaDonNewShip": return "🛵"
        case "HoaDonNewMuaVe": return "🛍️"
        case "HoaDonNewTaiCho": return "🪑"
        case "HoaDonNewApp": return "📱"
        case "HoaDonNewMuaHo": return "✋"
        case "HoaDonNewAppDatHang": return "🛒"
        case "HoaDonEdit": return "✏️"
        case "HoaDonDel": return "🗑️"
        case "DangGiaoHang": return "🚚"
        case "GhiNo": return "⚠️"
        case "ThanhToanTienMat": return "💵"
        case "ThanhToanChuyenKhoan": return "💳"
        case "ThanhToanBanking": return "🤖"
        case "ThanhToan": return "💰"
        case "DuyKhanh", "DuyKhanhGhiNo", "DuyKhanhTraNo", "DuyKhanhChuyenKhoan": return "👤"
        case "Admin": return "⚙️"
        default: return "🔔"
        }
    }

    /// Màu nhấn theo nhóm: đơn mới xanh dương, sửa cam, xoá/nợ đỏ, tiền xanh lá.
    static func mau(_ loai: String) -> Color {
        switch loai {
        case "HoaDonEdit": return Color(red: 0.90, green: 0.50, blue: 0.05)
        case "HoaDonDel", "GhiNo": return .dangerColor
        case "ThanhToanTienMat", "ThanhToanChuyenKhoan", "ThanhToanBanking", "ThanhToan": return .successColor
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
