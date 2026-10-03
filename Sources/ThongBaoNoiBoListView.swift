import SwiftUI

/// Màu Int (0xRRGGBB, xem MauThongBaoNoiBo.For bên Backend) -> Color — chỉ dùng cho badge icon ở đây.
private extension Color {
    init(rgbHex: Int) {
        self.init(
            red: Double((rgbHex >> 16) & 0xFF) / 255,
            green: Double((rgbHex >> 8) & 0xFF) / 255,
            blue: Double(rgbHex & 0xFF) / 255
        )
    }
}

/// Lịch sử thông báo nghiệp vụ (icon chuông, đầu tab Hoá đơn) — thay kênh Discord cũ từ 2026-10-03.
/// Mở sheet này tự đánh dấu TẤT CẢ đã xem (xoá badge đỏ), khớp hành vi mở kênh Discord đọc hết trước đây.
struct ThongBaoNoiBoListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ThongBaoNoiBoDto] = []
    @State private var hasLoaded = false
    @State private var openHoaDonId: String?

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
                    List(items) { item in
                        ThongBaoNoiBoRowView(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let id = item.hoaDonId { openHoaDonId = id }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
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
        items = await APIClient.shared.getThongBaoNoiBoList()
        hasLoaded = true
    }
}

private struct ThongBaoNoiBoRowView: View {
    let item: ThongBaoNoiBoDto

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(rgbHex: item.mau))
                .frame(width: 10, height: 10)
                .padding(.top, 5)

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
        case "HoaDonNewShip": return "Đơn Ship mới"
        case "HoaDonNewMuaVe": return "Đơn mua về mới"
        case "HoaDonNewTaiCho": return "Đơn tại chỗ mới"
        case "HoaDonNewApp": return "Đơn App mới"
        case "HoaDonNewMuaHo": return "Đơn mua hộ mới"
        case "HoaDonNewAppDatHang": return "Đơn App Đenn mới"
        case "HoaDonEdit": return "Sửa hoá đơn"
        case "HoaDonDel": return "Xoá hoá đơn"
        case "DangGiaoHang": return "Đang giao hàng"
        case "GhiNo": return "Ghi nợ"
        case "ThanhToanTienMat": return "Tiền mặt"
        case "ThanhToanChuyenKhoan": return "Chuyển khoản"
        case "ThanhToanBanking": return "Banking (tự động thu)"
        case "ThanhToan": return "Thanh toán"
        case "DuyKhanh": return "Duy Khánh"
        case "Admin": return "Hệ thống"
        default: return "Thông báo"
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
