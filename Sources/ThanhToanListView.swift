import Combine
import SwiftUI
import UIKit

/// Danh sách chi tiết thanh toán theo ngày, GET /api/ChiTietHoaDonThanhToan?ngay=. Nhấp vào dòng để
/// mở sheet chi tiết (giống HoaDonDetailView) thay vì vuốt trái để xoá — vuốt dễ bấm nhầm với data
/// đụng tiền thật, xem ThanhToanDetailView.
struct ThanhToanListView: View {
    let notificationBell: AnyView
    @State private var currentDate = Date()
    @State private var items: [ChiTietHoaDonThanhToanDto] = []
    @State private var hasLoaded = false
    /// Xem HoaDonListView: banner thử lại khi tải lỗi (giữ danh sách cũ), chặn lượt load cũ ghi đè,
    /// và tự sang ngày mới khi app mở qua đêm.
    @State private var loadFailed = false
    @State private var loadGeneration = 0
    @State private var loadedKey = ""
    @State private var lastSeenToday = Date()
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    /// Giữ nguyên BẢN CHỤP dòng đã bấm (không tra lại theo id trong `items`) — danh sách tự tải lại
    /// lúc sheet đang mở mà dòng đó biến mất thì sheet từng thành trang trắng.
    @State private var selectedItem: ChiTietHoaDonThanhToanDto?
    @State private var activeFilter: ThanhToanQuickFilter?
    /// Tab này không có đồng hồ tick như tab Đơn — timer thưa chỉ để bắt lúc qua nửa đêm.
    private let dayRolloverTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Đã áp search nhưng CHƯA áp activeFilter — dùng để đếm số dòng theo từng filter trong menu,
    /// khớp cơ chế searchFilteredItems bên HoaDonListView.
    private var searchFilteredItems: [ChiTietHoaDonThanhToanDto] {
        items.filter { anyMatchesSearch(searchText, $0.ten, $0.ghiChu, $0.tenMonSummary, $0.loaiThanhToan) }
    }

    // filteredItems bị đọc 6 lần mỗi lần body vẽ lại (count, isEmpty, ForEach, totalText,
    // totalTienMat, totalChuyenKhoan) — computed property nên mỗi lần đọc chạy lại search+filter từ
    // đầu, khớp lỗi đã sửa bên HoaDonListView (cachedSorted). Cache lại, chỉ tính khi thực sự đổi.
    @State private var filteredItems: [ChiTietHoaDonThanhToanDto] = []
    /// Số dòng khớp từng filter (trên tập đã áp search) — tính 1 lần cùng filteredItems.
    @State private var filterCounts: [ThanhToanQuickFilter: Int] = [:]

    private func recomputeFiltered() {
        let searched = searchFilteredItems
        var counts: [ThanhToanQuickFilter: Int] = [:]
        for filter in ThanhToanQuickFilter.allCases {
            counts[filter] = searched.filter { filter.matches($0) }.count
        }
        filterCounts = counts
        filteredItems = searched.filter { activeFilter?.matches($0) ?? true }
    }

    /// Tổng thực thu = tiền mặt + chuyển khoản. KHÔNG cộng Ví Xu (xu không phải tiền thật thu trong
    /// ngày) — Ví Xu vẫn hiện riêng ở dòng phụ phía trên.
    private var totalText: String {
        HoaDonFormatting.money(totalTienMat + totalChuyenKhoan)
    }

    private var totalTienMat: Double {
        filteredItems.filter { $0.phuongThucThanhToanId?.lowercased() == PaymentMethod.tienMatId }
            .reduce(0) { $0 + $1.soTien }
    }

    private var totalViXu: Double {
        filteredItems.filter { $0.phuongThucThanhToanId?.lowercased() == PaymentMethod.viXuId }
            .reduce(0) { $0 + $1.soTien }
    }

    private var totalChuyenKhoan: Double {
        filteredItems.filter { $0.phuongThucThanhToanId?.lowercased() == PaymentMethod.chuyenKhoanId }
            .reduce(0) { $0 + $1.soTien }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DaySearchBar(
                    date: $currentDate, searchText: $searchText,
                    placeholder: "Tìm khách, món, ghi chú...",
                    trailing: AnyView(
                        HStack(spacing: 14) {
                        PopoverMenu {
                            // Chỉ lọc 1 loại tại 1 thời điểm — khớp cơ chế HoaDonQuickFilter bên tab
                            // Hoá đơn. 2 filter đầu (avatar Khánh) đọc GhiChu=="Shipper" — đúng cờ
                            // "Duy Khánh" mà ThongKeService dùng để tách "Tiền mặt/Trả nợ Khánh" khỏi
                            // phần thu tại quán (xem ThongKeService.GetThanhToanAsync, Backend).
                            ForEach(ThanhToanQuickFilter.allCases, id: \.self) { filter in
                                let count = filterCounts[filter] ?? 0
                                if filter.isFirstInGroup { PopoverMenuDivider() }
                                PopoverMenuItem("\(count) \(filter.label)", isSelected: activeFilter == filter,
                                                isDimmed: count == 0) {
                                    activeFilter = (activeFilter == filter) ? nil : filter
                                } icon: {
                                    QuickFilterIcon(avatarName: filter.avatarName, emoji: filter.systemIcon)
                                }
                            }
                            if activeFilter != nil {
                                PopoverMenuDivider()
                                PopoverMenuItem("Bỏ lọc", role: .destructive) { activeFilter = nil }
                            }
                        } label: {
                            // Đổi lại SF Symbol (revert 2026-09-15) — khớp HoaDonListView.
                            Image(systemName: activeFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.title3)
                                .foregroundColor(.white)
                                .overlay(alignment: .topTrailing) {
                                    if activeFilter != nil {
                                        Text("\(filteredItems.count)")
                                            .font(.caption2.bold())
                                            .foregroundColor(.brandPrimary)
                                            .padding(4)
                                            .frame(minWidth: 18, minHeight: 18)
                                            .background(Color.white)
                                            .clipShape(Circle())
                                            .offset(x: 8, y: -8)
                                    }
                                }
                        }
                        notificationBell
                        }
                    ),
                    tinted: true
                ) { Task { await load() } }

                if !hasLoaded {
                    fullScreenLoading()
                } else {
                    if loadFailed {
                        ThongKeLoadErrorBanner(text: "Chưa tải được danh sách thanh toán") { Task { await load() } }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                    List {
                        if filteredItems.isEmpty {
                            Text("Không có thanh toán nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(filteredItems) { item in
                                ThanhToanRowView(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedItem = item }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .softScrollEdgeTop()
                    .padding(.top, 4)
                    .refreshable { await load() }
                }

                Divider()
                VStack(spacing: 2) {
                    HStack {
                        Spacer()
                        Text("Tiền mặt: \(HoaDonFormatting.money(totalTienMat))")
                            .font(.caption2).foregroundColor(.successColor)
                        Text("Chuyển khoản: \(HoaDonFormatting.money(totalChuyenKhoan))")
                            .font(.caption2).foregroundColor(.brandPrimary)
                        if totalViXu > 0 {
                            Text("Ví Xu: \(HoaDonFormatting.money(totalViXu))")
                                .font(.caption2).foregroundColor(.orange)
                        }
                    }
                    HStack {
                        Spacer()
                        Text(totalText).font(.headline)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(minHeight: FooterBarMetrics.minHeight)
            }
        }
        .task { await load() }
        .onEntityChanged(["HoaDon", "ChiTietHoaDonThanhToan"], tab: .thanhToan) { Task { await load() } }
        .onChange(of: searchText) { _ in recomputeFiltered() }
        .onChange(of: activeFilter) { _ in recomputeFiltered() }
        .onReceive(dayRolloverTimer) { _ in rollOverIfNewDay() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { rollOverIfNewDay() }
        }
        .sheet(item: $selectedItem) { item in
            ThanhToanDetailView(item: item) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let dateIso = DateNavFormat.queryDate.string(from: currentDate)

        // Sang ngày khác: dòng ngày cũ không được ở lại dưới tiêu đề ngày mới. Cùng ngày (refresh /
        // EntityChanged / thử lại): giữ danh sách đang có trong lúc chờ.
        if dateIso != loadedKey {
            items = []
            recomputeFiltered()
            hasLoaded = false
        }

        let fetched = await APIClient.shared.getThanhToanByDay(dateIso)
        guard generation == loadGeneration else { return }   // đã có lượt load mới hơn — bỏ kết quả cũ

        if let fetched { items = fetched }
        loadFailed = fetched == nil
        loadedKey = dateIso
        hasLoaded = true
        recomputeFiltered()
    }

    /// Xem HoaDonListView.rollOverIfNewDay — đang xem "hôm nay" cũ thì tự nhảy sang hôm nay mới.
    private func rollOverIfNewDay() {
        let cal = Calendar.current
        let today = Date()
        guard !cal.isDate(lastSeenToday, inSameDayAs: today) else { return }
        let dangXemHomNayCu = cal.isDate(currentDate, inSameDayAs: lastSeenToday)
        lastSeenToday = today
        guard dangXemHomNayCu else { return }
        currentDate = today
        Task { await load() }
    }
}

private struct ThanhToanRowView: View {
    let item: ChiTietHoaDonThanhToanDto

    /// "Thanh toán" (mặc định) và "Trong ngày" (đa số đơn không nợ) không mang thông tin gì mới nên
    /// ẩn, chỉ hiện 2 loại liên quan nợ (Trả nợ qua ngày/Trả nợ trong ngày).
    private var loaiThanhToanText: String? {
        guard let loai = item.loaiThanhToan, !loai.isEmpty, loai != "Thanh toán", loai != "Trong ngày" else { return nil }
        return loai
    }

    /// "Thanh toán đủ" chỉ là ghi chú mặc định khi thu đủ tiền — ẩn cho gọn (khớp web mobile,
    /// xem PaymentLabels.ThanhToanDu bên Backend).
    private var ghiChuDisplay: String? {
        guard let ghiChu = item.ghiChu, !ghiChu.isEmpty, ghiChu != "Thanh toán đủ", ghiChu != "Shipper" else { return nil }
        return ghiChu
    }

    private var isShipperNote: Bool {
        item.ghiChu == "Shipper"
    }

    private var isBank: Bool {
        item.phuongThucThanhToanId?.lowercased() == PaymentMethod.chuyenKhoanId
    }

    /// SePay webhook tự thu (TuDongLuc có giá trị) vs thu tay (nil) — chỉ có ý nghĩa khi isBank.
    private var isAutoBank: Bool {
        isBank && item.tuDongLuc != nil
    }

    /// Chỉ 2 màu theo phương thức thanh toán (tiền mặt/chuyển khoản) — không còn phân biệt theo
    /// loaiThanhToan (Trả nợ qua ngày/trong ngày) như trước.
    private var isViXu: Bool {
        item.phuongThucThanhToanId?.lowercased() == PaymentMethod.viXuId
    }

    private var methodColor: Color {
        isViXu ? .orange : (isBank ? .brandPrimary : .successColor)
    }

    private var borderColor: Color { methodColor }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(borderColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                    if let loaiThanhToanText {
                        Text(loaiThanhToanText).font(.caption.bold()).foregroundColor(borderColor)
                    }
                    if isShipperNote {
                        ShipperAvatarView(name: "Khánh", size: 16)
                    } else if let ghiChuDisplay {
                        Text(ghiChuDisplay).font(.caption).foregroundColor(.textMuted).lineLimit(1)
                    }
                }
                Text(item.ten).font(.subheadline.bold())
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
                if let tk = item.tenTaiKhoan, !tk.isEmpty {
                    Text("Thu bởi: \(tk)").font(.caption2).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(HoaDonFormatting.money(item.soTien)).font(.subheadline.bold())
                HStack(spacing: 3) {
                    if isAutoBank {
                        Text("🤖").font(.caption2)
                    }
                    Text(isViXu ? "Ví Xu" : (isBank ? "Chuyển khoản" : "Tiền mặt")).font(.caption2.bold())
                }
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(methodColor.opacity(0.15))
                .foregroundColor(methodColor)
                .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(borderColor.pastelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

/// Lọc nhanh trên tab Thanh toán — chỉ chọn được 1 filter tại 1 thời điểm, nil = không lọc gì.
/// Khớp đúng cách "Thống kê" tách bạch tiền mặt (xem ThongKeService.GetThanhToanAsync, Backend):
/// GhiChu=="Shipper" là cờ đánh dấu khoản Duy Khánh thu hộ qua app riêng của shipper, LoaiThanhToan
/// text lấy thẳng từ bảng lookup LoaiThanhToans (1=Trong ngày, 2=Thanh toán, 3=Trả nợ qua ngày,
/// 4=Trả nợ trong ngày — xem AppDbContext, Share).
enum ThanhToanQuickFilter: CaseIterable, Hashable {
    case tienMatDuyKhanh, traNoDuyKhanh
    case tienMat, chuyenKhoan, viXu

    /// Nhóm để chèn Divider giữa 2 cụm: theo Duy Khánh (avatar) / theo phương thức thanh toán (icon).
    var group: Int {
        switch self {
        case .tienMatDuyKhanh, .traNoDuyKhanh: return 0
        case .tienMat, .chuyenKhoan, .viXu: return 1
        }
    }

    var isFirstInGroup: Bool {
        guard group > 0 else { return false }
        let index = Self.allCases.firstIndex(of: self)!
        return Self.allCases[Self.allCases.index(before: index)].group != group
    }

    var label: String {
        switch self {
        case .tienMatDuyKhanh: return "Tiền mặt Duy Khánh"
        case .traNoDuyKhanh: return "Trả nợ Duy Khánh"
        case .tienMat: return "Tiền mặt"
        case .chuyenKhoan: return "Chuyển khoản"
        case .viXu: return "Ví Xu"
        }
    }

    var avatarName: String? {
        switch self {
        case .tienMatDuyKhanh, .traNoDuyKhanh: return "Khánh"
        case .tienMat, .chuyenKhoan, .viXu: return nil
        }
    }

    /// Emoji (đổi từ SF Symbol 2026-09-12, khớp F1/F4 bên HoaDonDetailView + phong cách AppDatHangIOS).
    var systemIcon: String? {
        switch self {
        case .tienMat: return "💵"
        case .chuyenKhoan: return "💳"
        case .viXu: return "🪙"
        default: return nil
        }
    }

    func matches(_ item: ChiTietHoaDonThanhToanDto) -> Bool {
        let isTienMat = item.phuongThucThanhToanId?.lowercased() == PaymentMethod.tienMatId
        let isBank = item.phuongThucThanhToanId?.lowercased() == PaymentMethod.chuyenKhoanId
        let isDuyKhanh = item.ghiChu == "Shipper"
        switch self {
        case .tienMatDuyKhanh:
            return isTienMat && isDuyKhanh && item.loaiThanhToan == "Trong ngày"
        case .traNoDuyKhanh:
            return isTienMat && isDuyKhanh
                && (item.loaiThanhToan == "Trả nợ qua ngày" || item.loaiThanhToan == "Trả nợ trong ngày")
        case .tienMat:
            return isTienMat
        case .chuyenKhoan:
            return isBank
        case .viXu:
            return item.phuongThucThanhToanId?.lowercased() == PaymentMethod.viXuId
        }
    }
}
