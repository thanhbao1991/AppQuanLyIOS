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

    private let pageSize = 50

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    fullScreenLoading()
                } else if items.isEmpty {
                    Text("Chưa có thông báo nào")
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(items) { item in
                            ThongBaoNoiBoRowView(item: item)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if let id = item.hoaDonId { openHoaDonId = id }
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowSeparator(.hidden)
                                .onAppear {
                                    if item.id == items.last?.id { Task { await loadMore() } }
                                }
                        }
                        if loadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
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
        HStack(alignment: .top, spacing: 10) {
            Text(ThongBaoNoiBoFormatting.emoji(item.loai))
                .font(.body)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(ThongBaoNoiBoFormatting.tieuDe(item.loai))
                    .font(.subheadline.bold())
                Text(item.noiDung)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Text(ThongBaoNoiBoFormatting.thoiGian(item.taoLuc))
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }

            Spacer(minLength: 0)

            if item.hoaDonId != nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.vertical, 4)
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

    static func thoiGian(_ iso: String) -> String {
        guard let date = HoaDonFormatting.parseIso(iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm dd/MM"
        f.locale = Locale(identifier: "vi_VN")
        return f.string(from: date)
    }
}
