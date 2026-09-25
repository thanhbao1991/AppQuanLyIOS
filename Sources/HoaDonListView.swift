import Combine
import PhotosUI
import SwiftUI
import UIKit

struct HoaDonListView: View {
    @ObservedObject private var deepLink = DeepLinkRouter.shared
    @State private var currentDate = Date()
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var selectedId: String?
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showDesktopSheet = false
    @State private var creatingPending: PendingCreate?
    /// Tick định kỳ để buộc SwiftUI vẽ lại badge "chờ" trên các card — nếu không có state nào đổi,
    /// waitingMinutes chỉ tính 1 lần lúc load rồi đứng yên mãi (không tự cập nhật theo thời gian thực).
    @State private var now = Date()
    @State private var activeFilter: HoaDonQuickFilter?
    private let clockTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    /// Danh sách đã áp search nhưng CHƯA áp activeFilter — dùng để đếm số dòng theo từng filter
    /// trong menu (đếm trên tập đang xem, không phải đếm trên tập đã bị 1 filter khác thu hẹp).
    private var searchFilteredItems: [HoaDonListDto] {
        items.filter { anyMatchesSearch(searchText, $0.tenKhachHangText, $0.tenBan, $0.ghiChu, $0.ghiChuShipper, $0.tenMonSummary, $0.nguoiShip) }
    }

    /// sortedItems là computed property nên MỖI LẦN được đọc lại chạy lại toàn bộ filter+search+sort —
    /// trước đây bị đọc 3 lần riêng biệt mỗi lần body vẽ lại (ForEach + totalText + phanLoaiTotals),
    /// kể cả khi chỉ đồng hồ `now` tick 20s (không đổi items/searchText/activeFilter). Cache lại 1 lần
    /// vào cachedSorted, chỉ tính lại đúng lúc items/searchText/activeFilter thực sự đổi — đỡ giật khi
    /// danh sách dài (list hay bị coi "chậm" ở máy nhân viên là do việc này).
    @State private var cachedSorted: [HoaDonListDto] = []

    private func recomputeSorted() {
        cachedSorted = searchFilteredItems
            .filter { item in activeFilter?.matches(item) ?? true }
            .sorted {
                let p0 = HoaDonFormatting.sortPriority($0)
                let p1 = HoaDonFormatting.sortPriority($1)
                if p0 != p1 { return p0 < p1 }
                return ($0.ngayGio ?? "") > ($1.ngayGio ?? "")
            }
    }

    private var totalText: String {
        HoaDonFormatting.money(cachedSorted.reduce(0) { $0 + $1.thanhTien })
    }

    /// Tổng tiền theo từng phân loại đơn, gộp trên 1 dòng gọn — icon thay chữ để đỡ tốn ngang, khỏi
    /// bị xuống 2 dòng như bản text cũ ("Ship 203k, T.chỗ 230k...").
    private var phanLoaiTotals: [(phanLoai: String, icon: String, color: Color, text: String)] {
        // Thiếu AppDatHang ở đây thì doanh thu đơn app khách biến mất khỏi thanh tổng, dù vẫn còn
        // trong cachedSorted — mirror đúng lỗi đã sửa ở ThongKeService (Backend, thêm nhãn "Đặt qua app").
        let order: [(code: String, icon: String)] = [
            ("Ship", "🛵"), ("AppDatHang", "🛒"), ("Tại Chỗ", "🪑"), ("Mv", "🛍️"),
            ("Mh", "✋"), ("App", "📱"),
        ]
        return order.compactMap { entry in
            let total = cachedSorted.filter { $0.phanLoai == entry.code }.reduce(0) { $0 + $1.thanhTien }
            guard total > 0 else { return nil }
            let text = "\(Int((total / 1000).rounded()))"
            return (entry.code, entry.icon, HoaDonFormatting.phanLoaiColor(entry.code), text)
        }
    }

    /// Emoji rasterize thành UIImage, dùng riêng cho item trong `Menu` (UIMenu thật) — KHÔNG dùng
    /// Text(emoji) trực tiếp ở đây được: đã thử và UIMenu chỉ hiện đúng 1 trong 2 view lồng trong
    /// Label khi CẢ 2 closure (title/icon) đều là Text, rớt mất chữ số đếm+tên filter, chỉ còn trơ
    /// emoji to đùng (xem ảnh báo lỗi 12/9). Bản SF Symbol cũ hoạt động đúng vì title-slot LUÔN LÀ
    /// Image (coloredMenuIcon) — giữ đúng cấu trúc đó bằng cách vẽ emoji ra ảnh thay vì Text thẳng.
    private func emojiMenuIcon(_ emoji: String, size: CGFloat = 22) -> Image {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let img = renderer.image { _ in
            let font = UIFont.systemFont(ofSize: size * 0.82)
            let str = emoji as NSString
            let strSize = str.size(withAttributes: [.font: font])
            let rect = CGRect(x: (size - strSize.width) / 2, y: (size - strSize.height) / 2,
                               width: strSize.width, height: strSize.height)
            str.draw(in: rect, withAttributes: [.font: font])
        }
        return Image(uiImage: img)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DaySearchBar(
                    date: $currentDate, searchText: $searchText,
                    placeholder: "Tìm khách, món, ghi chú...",
                    trailing: AnyView(
                        Menu {
                            // Chỉ lọc 1 loại tại 1 thời điểm (không gộp OR nhiều filter như trước) —
                            // chọn lại đúng filter đang bật để tắt, chọn filter khác để thay hẳn.
                            // Chia 3 cụm theo `group`, chèn Divider giữa mỗi cụm — 4 filter Khánh /
                            // 2 filter Nhã / 5 filter theo PhanLoai (icon hệ thống thay avatar).
                            ForEach(HoaDonQuickFilter.allCases, id: \.self) { filter in
                                let count = searchFilteredItems.filter { filter.matches($0) }.count
                                if filter.isFirstInGroup {
                                    Divider()
                                }
                                Button {
                                    activeFilter = (activeFilter == filter) ? nil : filter
                                } label: {
                                    // UIMenu KHÔNG chấp nhận view lồng ghép (overlay/ZStack) trong Label —
                                    // đã thử badge overlay trên avatar, hệ thống render sai hẳn (mất chữ tên
                                    // filter, chỉ còn số). Quay lại 2 view phẳng đơn giản: avatar/icon (title) +
                                    // text số+tên gộp (icon) — bản duy nhất render đúng đã verify qua screenshot.
                                    Label {
                                        if let avatarName = filter.avatarName {
                                            ShipperAvatarView(name: avatarName, size: 20)
                                        } else if let systemIcon = filter.systemIcon {
                                            emojiMenuIcon(systemIcon)
                                        }
                                    } icon: {
                                        // Menu native iOS (UIMenu) không cho custom màu/font trên text item —
                                        // mọi style đều bị hệ thống bỏ qua, nên giữ plain text.
                                        Text(activeFilter == filter ? "✓ \(count) \(filter.label)" : "\(count) \(filter.label)")
                                    }
                                }
                            }
                            if activeFilter != nil {
                                Divider()
                                Button("Bỏ lọc", role: .destructive) { activeFilter = nil }
                            }
                        } label: {
                            // Đổi lại SF Symbol (revert 2026-09-15) — bản .fill khi đang lọc để phân
                            // biệt trạng thái, cộng badge số đếm góc trên-phải.
                            Image(systemName: activeFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.title3)
                                .foregroundColor(.white)
                                .overlay(alignment: .topTrailing) {
                                    if activeFilter != nil {
                                        Text("\(cachedSorted.count)")
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
                    ),
                    tinted: true
                ) { Task { await load() } }

                if !hasLoaded {
                    fullScreenLoading()
                } else {
                    List {
                        if cachedSorted.isEmpty {
                            Text("Không có hoá đơn nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(cachedSorted) { item in
                                HoaDonRowView(item: item, now: now)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedId = item.id }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.plain)
                    // +4pt để khớp khoảng cách header→card đầu tiên bên tab Thống kê (12pt) — mặc
                    // định List chỉ có 8pt từ listRowInsets top của dòng đầu.
                    .padding(.top, 4)
                    .refreshable { await load() }
                }

                Divider()
                HStack(spacing: 12) {
                    Button { showAddSheet = true } label: {
                        Text("➕").font(.system(size: 30))
                    }
                    .foregroundColor(.brandPrimary)

                    Button { showDesktopSheet = true } label: {
                        Text("🖥️").font(.system(size: 26))
                    }
                    .foregroundColor(.brandPrimary)

                    VStack(alignment: .trailing, spacing: 2) {
                        if !phanLoaiTotals.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(phanLoaiTotals, id: \.phanLoai) { item in
                                    Label { Text(item.text).foregroundColor(item.color) } icon: { Text(item.icon) }
                                        .font(.caption2)
                                }
                            }
                        }
                        Text(totalText).font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .task {
            await load()
            openPendingDeepLink()
        }
        .onReceive(clockTimer) { now = $0 }
        .onEntityChanged(["HoaDon"], tab: .hoaDon) { Task { await load() } }
        .onChange(of: deepLink.khachHangIdToOrder) { _ in openPendingDeepLink() }
        .onChange(of: searchText) { _ in recomputeSorted() }
        .onChange(of: activeFilter) { _ in recomputeSorted() }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiableId($0) } },
            set: { selectedId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {
                Task { await load() }
            }
        }
        .sheet(isPresented: $showDesktopSheet) {
            DesktopScreenView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddHoaDonSheet(
                onPick: { code in
                    Task {
                        // Đợi sheet "+" đóng xong hẳn rồi mới mở form thêm hoá đơn — mở đồng thời 2
                        // sheet trên cùng view dễ bị SwiftUI bỏ qua sheet thứ hai (race giữa 2 lần
                        // dismiss/present).
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        creatingPending = PendingCreate(phanLoai: code)
                    }
                },
                onPickGoiSom: { khachHangId, tenSanPham, tenBienThe in
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        creatingPending = PendingCreate(
                            phanLoai: "Ship",
                            presetKhachHangId: khachHangId,
                            presetTenSanPham: tenSanPham,
                            presetTenBienThe: tenBienThe
                        )
                    }
                },
                onPickAppOrder: { items, ghiChu, warnings, khachHangId in
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        creatingPending = PendingCreate(
                            phanLoai: "App",
                            presetKhachHangId: khachHangId,
                            presetItems: items,
                            presetGhiChu: ghiChu,
                            presetWarnings: warnings
                        )
                    }
                },
                onPickFromImage: { items, ghiChu, warnings, tenKhach, sdt, diaChi in
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        creatingPending = PendingCreate(
                            phanLoai: "Ship",
                            presetItems: items,
                            presetGhiChu: ghiChu,
                            presetWarnings: warnings,
                            presetTenKhach: tenKhach,
                            presetSdt: sdt,
                            presetDiaChi: diaChi
                        )
                    }
                }
            )
        }
        .sheet(item: $creatingPending) { pending in
            HoaDonCreateFormView(
                phanLoai: pending.phanLoai,
                presetKhachHangId: pending.presetKhachHangId,
                presetTenSanPham: pending.presetTenSanPham,
                presetTenBienThe: pending.presetTenBienThe,
                presetItems: pending.presetItems,
                presetGhiChu: pending.presetGhiChu,
                presetWarnings: pending.presetWarnings,
                presetTenKhach: pending.presetTenKhach,
                presetSdt: pending.presetSdt,
                presetDiaChi: pending.presetDiaChi
            ) { newId in
                Task {
                    await load()
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    selectedId = newId
                }
            }
        }
    }

    private func load() async {
        loading = true
        let dateIso = DateNavFormat.queryDate.string(from: currentDate)
        items = await APIClient.shared.getHoaDonListByDay(dateIso)
        loading = false
        hasLoaded = true
        recomputeSorted()
    }

    /// Mở sheet tạo đơn Ship prefill khách từ link Danh bạ (DeepLinkRouter) — bỏ qua nếu đang có
    /// sheet tạo đơn khác dở dang (creatingPending != nil) để không mất dữ liệu nhân viên đang nhập.
    private func openPendingDeepLink() {
        guard let id = deepLink.khachHangIdToOrder else { return }
        deepLink.khachHangIdToOrder = nil
        guard creatingPending == nil else { return }
        creatingPending = PendingCreate(phanLoai: "Ship", presetKhachHangId: id)
    }
}

/// Avatar tròn khớp HoaDonTabControl.xaml bên Desktop (2 shipper cố định Khánh/Nhã có ảnh thật,
/// tên khác dùng ảnh "ship" chung — Desktop chỉ có 2 DataTrigger này, chưa có shipper thứ 3 nào).
struct ShipperAvatarView: View {
    let name: String
    var size: CGFloat = 36

    private var assetName: String {
        switch name {
        case "Khánh": return "shipper_khanh"
        case "Nhã": return "shipper_nha"
        default: return "shipper_generic"
        }
    }

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

/// Lọc nhanh trên tab Hoá đơn — chỉ chọn được 1 filter tại 1 thời điểm, nil = không lọc gì. Thứ tự
/// khai báo = thứ tự hiện trong menu, chia 3 nhóm cách nhau bằng Divider (xem `group`).
/// - 4 filter đầu (avatar Khánh) port 1:1 từ ShipperDuyKhanhAndroid (statusOf/HoaDonStatus trong
///   HoaDonAdapter.kt + check "trả nợ" riêng trong MainActivity.renderList) — chỉ áp dụng đơn Ship
///   của Khánh, đọc tiền tố GhiChuShipper y hệt app đó.
/// - 2 filter kế (avatar Nhã) là filter chung của quán (không riêng shipper nào, không port từ
///   app nào) — dùng ConLai/NgayNo trực tiếp trên HoaDon, khác hẳn logic đọc GhiChuShipper ở trên.
/// - 5 filter cuối lọc theo PhanLoai (icon hệ thống, không phải avatar) — khớp bộ icon dùng ở
///   AddHoaDonSheet.categories, để nhân viên lọc nhanh theo loại đơn không cần mở phần thống kê.
enum HoaDonQuickFilter: CaseIterable, Hashable {
    case tiNuaChuyenKhoan, ghiNo, traNo, chuaChon
    case chuaThanhToan, daGhiNo
    case ship, taiCho, muaVe, muaHo, app

    /// Nhóm để chèn Divider giữa các cụm filter trong menu — đổi giá trị này thì đổi luôn vị trí
    /// đường phân cách, không cần sửa view.
    var group: Int {
        switch self {
        case .tiNuaChuyenKhoan, .ghiNo, .traNo, .chuaChon: return 0
        case .chuaThanhToan, .daGhiNo: return 1
        case .taiCho, .ship, .muaVe, .muaHo, .app: return 2
        }
    }

    /// True cho case đầu tiên của mỗi cụm (group > 0) — dùng để chèn Divider trước case đó trong menu.
    var isFirstInGroup: Bool {
        guard group > 0 else { return false }
        let index = Self.allCases.firstIndex(of: self)!
        return Self.allCases[Self.allCases.index(before: index)].group != group
    }

    var label: String {
        switch self {
        case .tiNuaChuyenKhoan: return "Tí nữa chuyển khoản"
        case .ghiNo: return "Ghi nợ"
        case .traNo: return "Trả nợ"
        case .chuaChon: return "Chưa chọn"
        case .chuaThanhToan: return "Chưa thanh toán"
        case .daGhiNo: return "Đã ghi nợ"
        case .taiCho: return "Tại chỗ"
        case .ship: return "Ship"
        case .muaVe: return "Mua về"
        case .muaHo: return "Mua hộ"
        case .app: return "App"
        }
    }

    /// Avatar hiện trong menu — 4 filter theo shipper Khánh dùng ảnh Khánh, 2 filter chung quán
    /// dùng ảnh Nhã (chỉ để phân biệt nhóm bằng hình, không có nghĩa 2 filter đó thuộc về Nhã).
    /// nil cho nhóm PhanLoai (dùng `systemIcon` thay avatar).
    var avatarName: String? {
        switch self {
        case .tiNuaChuyenKhoan, .ghiNo, .traNo, .chuaChon: return "Khánh"
        case .chuaThanhToan, .daGhiNo: return "Nhã"
        case .taiCho, .ship, .muaVe, .muaHo, .app: return nil
        }
    }

    /// Emoji cho nhóm PhanLoai — khớp bộ emoji AddHoaDonSheet.categories/phanLoaiTotals để nhất
    /// quán trong app (đổi từ SF Symbol 2026-09-12, khớp phong cách AppDatHangIOS).
    var systemIcon: String? {
        switch self {
        case .taiCho: return "🪑"
        case .ship: return "🛵"
        case .muaVe: return "🛍️"
        case .muaHo: return "✋"
        case .app: return "📱"
        default: return nil
        }
    }

    private var phanLoaiCode: String? {
        switch self {
        case .taiCho: return "Tại Chỗ"
        case .ship: return "Ship"
        case .muaVe: return "Mv"
        case .muaHo: return "Mh"
        case .app: return "App"
        default: return nil
        }
    }

    func matches(_ item: HoaDonListDto) -> Bool {
        switch self {
        case .tiNuaChuyenKhoan, .ghiNo, .traNo, .chuaChon:
            // AppDatHang cùng bản chất giao hàng với Ship — ShipperQueryService (Backend) giờ trả cả
            // 2 loại cho app shipper (fix 2026-09-06), nên bộ lọc ghi chú shipper ở đây cũng phải
            // khớp cả AppDatHang, không chỉ Ship.
            guard item.phanLoai == "Ship" || item.phanLoai == "AppDatHang", item.nguoiShip == "Khánh" else { return false }
            let note = (item.ghiChuShipper ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            switch self {
            case .tiNuaChuyenKhoan:
                // Khớp nhánh TI_NUA trong renderList (Android): thêm 2 điều kiện conLai>0 + chưa
                // ghi nợ ngoài prefix — đơn đã thu đủ/đã chuyển ghi nợ thì không còn "chờ CK" nữa.
                let chuaGhiNo = item.ngayNo?.isEmpty ?? true
                return note.hasPrefix("tí nữa") && item.conLai > 0 && chuaGhiNo
            case .ghiNo:
                return note.hasPrefix("ghi nợ")
            case .traNo:
                return note.contains("trả nợ")
            default: // .chuaChon
                let knownPrefixes = ["tiền mặt", "chuyển khoản", "ghi nợ", "tí nữa"]
                return !knownPrefixes.contains { note.hasPrefix($0) }
            }
        case .chuaThanhToan, .daGhiNo:
            // conLai<=0 loại trừ trước — khớp logic statusText ở HoaDonRowView (ngayNo cũ vẫn còn
            // giá trị dù đã thu đủ, không tự xoá). .chuaThanhToan KHÔNG gồm đơn đã ghi nợ.
            let daGhiNoFlag = !(item.ngayNo?.isEmpty ?? true)
            return self == .daGhiNo
                ? item.conLai > 0 && daGhiNoFlag
                : item.conLai > 0 && !daGhiNoFlag
        case .taiCho, .ship, .muaVe, .muaHo, .app:
            return item.phanLoai == phanLoaiCode
        }
    }
}

struct IdentifiableId: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}

/// Tham số mở HoaDonCreateFormView — "Đơn 7h" chốt sẵn phanLoai=Ship + preset khách/món.
private struct PendingCreate: Identifiable {
    let phanLoai: String
    var presetKhachHangId: String? = nil
    var presetTenSanPham: String? = nil
    var presetTenBienThe: String? = nil
    var presetItems: [DraftChiTiet] = []
    var presetGhiChu: String? = nil
    var presetWarnings: [String] = []
    /// "Bắt đơn từ ảnh" — điền sẵn vào Ô NHẬP TAY (khác presetKhachHangId là 1 KhachHang CÓ SẴN),
    /// vì AI chỉ đọc được text thô từ ảnh chat, không tự khớp/tạo KhachHang — HoaDonKhachHangService
    /// tự lo khớp SĐT/tạo mới lúc lưu đơn y hệt khi nhân viên gõ tay.
    var presetTenKhach: String? = nil
    var presetSdt: String? = nil
    var presetDiaChi: String? = nil
    var id: String { phanLoai + (presetKhachHangId ?? "") + String(presetItems.count) }
}

private struct HoaDonRowView: View {
    let item: HoaDonListDto
    let now: Date

    /// Chỉ 3 trạng thái đã-xử-lý — "Chưa thu" bị bỏ hẳn (không mang thông tin gì mới, phần lớn đơn
    /// đang ở trạng thái này nên hiện lên toàn màn hình đầy badge xám vô nghĩa).
    /// conLai<=0 phải check TRƯỚC ngayNo: khách ghi nợ rồi trả xong, ngayNo vẫn còn giá trị cũ
    /// (backend không xoá), nên nếu check ngayNo trước sẽ hiện "Ghi nợ" sai dù đã thu đủ.
    private var statusText: String? {
        if item.conLai <= 0.0 { return (item.isBank == true) ? "Chuyển khoản" : "Tiền mặt" }
        if !(item.ngayNo?.isEmpty ?? true) { return "Ghi nợ" }
        return nil
    }

    private var statusColor: Color {
        if item.conLai <= 0.0 { return (item.isBank == true) ? .brandPrimary : .successColor }
        return .dangerColor
    }

    /// Đóng băng thời gian chờ tại thời điểm sự kiện xảy ra SỚM NHẤT trong 3 mốc ghi nợ/thanh
    /// toán/đi ship (nếu đã xảy ra) — sau mốc đó khách không còn "chờ" nữa nên số phút phải đứng
    /// yên, không tiếp tục chạy theo `now`. Đơn chưa có mốc nào thì vẫn chạy live theo `now`.
    private var waitingEndDate: Date {
        let candidates = [item.ngayNo, item.ngayThanhToan, item.ngayShip]
            .compactMap { HoaDonFormatting.parseIso($0) }
        return candidates.min() ?? now
    }

    private var waitingMinutes: Int? {
        HoaDonFormatting.minutesSince(item.ngayGio, now: waitingEndDate)
    }

    private var waitingColor: Color {
        guard let waitingMinutes else { return .textMuted }
        if waitingMinutes >= 30 { return .dangerColor }
        if waitingMinutes >= 15 { return .warningColor }
        return .textMuted
    }

    /// Shipper đánh dấu "Tí nữa chuyển khoản" (GhiChuShipper == chuỗi cố định, xem
    /// ShipperActionService.TiNuaChuyenKhoanAsync) — set được cho Ship/AppDatHang (ShipperQueryService
    /// trả cả 2 loại cho app shipper từ 2026-09-06), Mv không bao giờ có giá trị này.
    private var shipTiNuaChuyenKhoan: Bool {
        (item.phanLoai == "Ship" || item.phanLoai == "AppDatHang") && item.ghiChuShipper == "Tí nữa chuyển khoản" && item.conLai > 0
    }

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(HoaDonFormatting.phanLoaiColor(item.phanLoai))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(HoaDonFormatting.time(item.ngayGio)).font(.caption).foregroundColor(.textMuted)
                    Text(HoaDonFormatting.phanLoaiLabel(item.phanLoai))
                        .font(.caption.bold())
                        .foregroundColor(HoaDonFormatting.phanLoaiColor(item.phanLoai))
                    if (item.phanLoai == "Ship" || item.phanLoai == "AppDatHang"), let nguoiShip = item.nguoiShip, !nguoiShip.isEmpty {
                        ShipperAvatarView(name: nguoiShip, size: 16)
                    }
                    Spacer()
                    if let waitingMinutes {
                        HStack(spacing: 3) {
                            Text("🕐").font(.caption2)
                            Text(HoaDonFormatting.waitingText(waitingMinutes)).font(.caption2.bold())
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(waitingColor)
                        .clipShape(Capsule())
                    }
                }
                Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                    .font(.subheadline.bold())
                if (item.phanLoai == "Ship" || item.phanLoai == "AppDatHang"), let diaChi = item.diaChiText, !diaChi.isEmpty {
                    HStack(spacing: 4) {
                        Text("📍").font(.caption2).foregroundColor(.textMuted)
                        Text(diaChi).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                    }
                }
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon).font(.footnote).foregroundColor(.textMuted).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if shipTiNuaChuyenKhoan {
                    HStack(spacing: 3) {
                        Text("🔔").font(.caption2)
                        Text("Tí nữa CK").font(.caption2.bold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.warningColor)
                    .clipShape(Capsule())
                }
                Text(HoaDonFormatting.money(item.thanhTien)).font(.subheadline.bold())
                if let statusText {
                    HStack(spacing: 3) {
                        if item.isBank == true, item.isAutoBank == true {
                            Text("🤖").font(.caption2)
                        }
                        Text(statusText).font(.caption2.bold())
                    }
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(statusColor.opacity(0.15))
                    .foregroundColor(statusColor)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(12)
        .background(HoaDonFormatting.phanLoaiBgColor(item.phanLoai))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // Shadow nhẹ để mỗi dòng nổi thành "card" giống khung form ở LoginView, thay vì phẳng dán
        // liền nền list như trước.
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

/// Khung chọn phân loại đơn khi bấm "+" — chọn xong đóng sheet này và mở HoaDonCreateFormView
/// (form đầy đủ: món/khách/giảm giá, xem HoaDonCreateFormView.swift). Phân loại chốt tại đây,
/// không đổi được nữa trong form (khớp yêu cầu "không cần" phần đổi phân loại/bàn giữa chừng).
private struct AddHoaDonSheet: View {
    let onPick: (String) -> Void
    let onPickGoiSom: (String, String, String) -> Void
    /// (items, ghiChu, warnings, khachHangId) — đơn đã map sẵn món từ store, xem AppOrderPickerSheet.
    let onPickAppOrder: ([DraftChiTiet], String, [String], String?) -> Void
    /// (items, ghiChu, warnings, tenKhach, sdt, diaChi) — xem ImageOrderPickerSheet.
    let onPickFromImage: ([DraftChiTiet], String, [String], String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showGoiSom = false
    @State private var showAppOrder = false
    @State private var showImageOrder = false
    @State private var showTextOrder = false

    // Không có "App" ở đây: đơn App chỉ được tạo qua "Bắt đơn App" (nút riêng bên dưới, lấy từ store).
    private let categories: [(code: String, icon: String)] = [
        ("Ship", "🛵"),
        ("Tại Chỗ", "🪑"),
        ("Mv", "🛍️"),
        ("Mh", "✋"),
    ]

    var body: some View {
        NavigationStack {
            Group {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        ForEach(categories, id: \.code) { cat in
                            Button { dismiss(); onPick(cat.code) } label: {
                                HStack {
                                    Text(cat.icon)
                                    Text(HoaDonFormatting.phanLoaiLabel(cat.code))
                                    Spacer()
                                }
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.roundedRectangle(radius: 12))
                            .tint(HoaDonFormatting.phanLoaiColor(cat.code))
                        }
                    }

                    Button { showGoiSom = true } label: {
                        HStack {
                            Text("🕐")
                            Text("Đơn 7h — khách hay gọi sớm")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(.brandPrimary)

                    Button { showAppOrder = true } label: {
                        HStack {
                            Text("✅")
                            Text("Bắt đơn App — lấy đơn từ store")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(.dangerColor)

                    Button { showImageOrder = true } label: {
                        HStack {
                            Text("📸")
                            Text("Bắt đơn từ ảnh — chat khách đặt món")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(.brandPrimary)

                    Button { showTextOrder = true } label: {
                        HStack {
                            Text("📋")
                            Text("Bắt đơn từ tin nhắn — dán từ clipboard")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 12))
                    .tint(.brandPrimary)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Thêm hoá đơn")
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
        .sheet(isPresented: $showGoiSom) {
            KhachGoiSomSheet { khachHangId, tenSanPham, tenBienThe in
                showGoiSom = false
                dismiss()
                onPickGoiSom(khachHangId, tenSanPham, tenBienThe)
            }
        }
        .sheet(isPresented: $showAppOrder) {
            AppOrderPickerSheet { items, ghiChu, warnings, khachHangId in
                showAppOrder = false
                dismiss()
                onPickAppOrder(items, ghiChu, warnings, khachHangId)
            }
        }
        .sheet(isPresented: $showImageOrder) {
            ImageOrderPickerSheet { items, ghiChu, warnings, tenKhach, sdt, diaChi in
                showImageOrder = false
                dismiss()
                onPickFromImage(items, ghiChu, warnings, tenKhach, sdt, diaChi)
            }
        }
        .sheet(isPresented: $showTextOrder) {
            TextOrderPickerSheet { items, ghiChu, warnings, tenKhach, sdt, diaChi in
                showTextOrder = false
                dismiss()
                onPickFromImage(items, ghiChu, warnings, tenKhach, sdt, diaChi)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// "Bắt đơn từ ảnh" — chọn/chụp 1-nhiều ảnh màn hình chat khách đặt món, gửi AI đọc (xem
/// OrderFromImageService, Backend). Chỉ những món khớp được SanPhamBienThe thật mới đưa vào draft —
/// món không khớp bị bỏ (giữ nguyên convention của "Bắt đơn App"), chỉ còn lại trong warnings để nhân
/// viên tự thêm tay bên form tạo đơn. tenKhach/sdt/diaChi chỉ là gợi ý điền sẵn ô nhập tay, KHÔNG tự
/// tạo/khớp KhachHang ở đây.
private struct ImageOrderPickerSheet: View {
    /// (items, ghiChu, warnings, tenKhach, sdt, diaChi)
    let onPick: ([DraftChiTiet], String, [String], String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var images: [Data] = []
    @State private var loading = false
    @State private var loadError: String?
    // Mở thẳng picker ảnh ngay khi sheet hiện ra, khỏi bắt bấm thêm 1 lần "Chọn ảnh" thừa.
    @State private var pickerPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if loading {
                    Spacer()
                    ProgressView("Đang đọc ảnh bằng AI...")
                    Spacer()
                } else if images.isEmpty {
                    Text("Chọn 1-nhiều ảnh chụp màn hình tin nhắn khách đặt món (cuộn xuống tin mới nhất nếu chat dài).")
                        .font(.subheadline)
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(images.indices, id: \.self) { i in
                                if let ui = UIImage(data: images[i]) {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: ui).resizable().scaledToFill()
                                            .frame(width: 90, height: 90).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Button { images.remove(at: i) } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.black.opacity(0.6)))
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 100)
                }

                if !loading {
                    Button { pickerPresented = true } label: {
                        Label("Chọn ảnh", systemImage: "photo.on.rectangle")
                    }

                    if let loadError {
                        Text(loadError).foregroundColor(.dangerColor).font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()

                    // Nút dự phòng khi AI đọc lỗi (loadError khác nil) — bấm chọn xong TỰ ĐỘNG xử lý
                    // luôn (xem loadPicked), nút này chỉ cần khi muốn thử lại đúng bộ ảnh đã chọn mà
                    // không chọn lại.
                    if !images.isEmpty {
                        Button {
                            Task { await process() }
                        } label: {
                            Text("Xử lý lại (\(images.count) ảnh)")
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                        .controlSize(.large)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.top)
            .navigationTitle("Bắt đơn từ ảnh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }.disabled(loading)
                }
            }
            .photosPicker(isPresented: $pickerPresented, selection: $pickerItems, maxSelectionCount: 6, matching: .images)
            .onChange(of: pickerItems) { items in
                Task { await loadPicked(items) }
            }
            .onAppear {
                if images.isEmpty { pickerPresented = true }
            }
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            // Thư viện ảnh trả nguyên định dạng gốc (thường PNG cho screenshot) nhưng ta luôn khai
            // "image/jpeg" khi upload (APIClient.parseOrderImages) — Claude (khác gpt-5-nano) kiểm
            // tra khớp media type/byte thật rất chặt, lệch là 400 luôn. Ép về JPEG thật ngay khi
            // nạp, khỏi phải dò định dạng lúc build multipart.
            if let raw = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: raw), let jpeg = ui.jpegData(compressionQuality: 0.9) {
                images.append(jpeg)
            }
        }
        pickerItems = []

        // Chọn xong là xử lý luôn, khỏi bắt bấm thêm nút "Xử lý" — user chỉ cần thao tác đúng 1 lần
        // "Bắt đơn từ ảnh" → chọn ảnh xong tự chạy AI.
        if !images.isEmpty {
            await process()
        }
    }

    private func process() async {
        loading = true
        loadError = nil
        defer { loading = false }
        let (result, message) = await APIClient.shared.parseOrderImages(images: images)
        guard let result, !result.items.isEmpty else {
            loadError = message ?? "Không đọc được đơn nào từ ảnh."
            return
        }

        // Chỉ món đã khớp SanPhamBienThe thật mới đưa vào draft — cùng convention "Bắt đơn App"
        // (buildDraftItems): món không khớp giữ lại trong warnings, nhân viên tự thêm tay.
        let draftItems = result.items.compactMap { line -> DraftChiTiet? in
            guard let btId = line.sanPhamBienTheId else { return nil }
            return DraftChiTiet(
                sanPhamBienTheId: btId,
                tenSanPham: line.tenSanPham ?? line.rawText,
                tenBienThe: line.tenBienThe ?? "",
                soLuong: line.soLuong,
                donGia: line.donGia,
                noteText: line.noteText ?? ""
            )
        }

        if draftItems.isEmpty {
            loadError = "Không khớp được món nào với thực đơn — thử ảnh rõ hơn hoặc thêm tay."
            return
        }

        dismiss()
        onPick(draftItems, result.ghiChu ?? "", result.warnings, result.tenKhach, result.soDienThoai, result.diaChi)
    }
}

/// "Bắt đơn từ tin nhắn" — text nhân viên đã copy sẵn từ Messenger/Zalo nằm trong clipboard hệ
/// thống (UIPasteboard), gửi thẳng AI đọc (xem OrderFromImageService.ParseFromTextAsync, Backend) mà
/// không cần chụp/chọn ảnh. Tự đọc clipboard + xử lý ngay khi sheet hiện ra — cùng 1 thao tác như
/// ImageOrderPickerSheet (bấm nút → xong).
private struct TextOrderPickerSheet: View {
    /// (items, ghiChu, warnings, tenKhach, sdt, diaChi)
    let onPick: ([DraftChiTiet], String, [String], String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loading = false
    @State private var loadError: String?
    @State private var hasClipboardText = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if loading {
                    Spacer()
                    ProgressView("Đang đọc tin nhắn bằng AI...")
                    Spacer()
                } else {
                    Spacer()
                    Text(hasClipboardText
                         ? "Không đọc được đơn nào từ tin nhắn đã copy."
                         : "Clipboard trống — copy đoạn chat khách đặt món (Messenger/Zalo) rồi bấm \"Thử lại\".")
                        .font(.subheadline)
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                        .padding()

                    if let loadError {
                        Text(loadError).foregroundColor(.dangerColor).font(.footnote)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await process() }
                    } label: {
                        Text("Thử lại")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .controlSize(.large)
                    .padding(.horizontal)
                    Spacer()
                }
            }
            .padding(.top)
            .navigationTitle("Bắt đơn từ tin nhắn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }.disabled(loading)
                }
            }
            .task { await process() }
        }
    }

    private func process() async {
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasClipboardText = !text.isEmpty
        guard !text.isEmpty else { return }

        loading = true
        loadError = nil
        defer { loading = false }
        let (result, message) = await APIClient.shared.parseOrderText(text)
        guard let result, !result.items.isEmpty else {
            loadError = message ?? "Không đọc được đơn nào từ tin nhắn."
            return
        }

        // Cùng convention "Bắt đơn từ ảnh"/"Bắt đơn App": chỉ món đã khớp SanPhamBienThe thật mới
        // đưa vào draft, món không khớp giữ lại trong warnings để nhân viên tự thêm tay.
        let draftItems = result.items.compactMap { line -> DraftChiTiet? in
            guard let btId = line.sanPhamBienTheId else { return nil }
            return DraftChiTiet(
                sanPhamBienTheId: btId,
                tenSanPham: line.tenSanPham ?? line.rawText,
                tenBienThe: line.tenBienThe ?? "",
                soLuong: line.soLuong,
                donGia: line.donGia,
                noteText: line.noteText ?? ""
            )
        }

        if draftItems.isEmpty {
            loadError = "Không khớp được món nào với thực đơn — thử thêm tay."
            return
        }

        dismiss()
        onPick(draftItems, result.ghiChu ?? "", result.warnings, result.tenKhach, result.soDienThoai, result.diaChi)
    }
}

/// "Bắt đơn App" — danh sách đơn đang chờ từ store (shippershipping), chọn 1 đơn để tải chi tiết
/// (món đã map sẵn SanPhamBienTheId thật) rồi mở form tạo đơn App đã điền sẵn. Khớp GetDonAsync
/// (Desktop, HoaDonTabControl.Board.cs).
private struct AppOrderPickerSheet: View {
    /// (items, ghiChu, warnings, khachHangId)
    let onPick: ([DraftChiTiet], String, [String], String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var orders: [AppOrderSummaryDto] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var fetchingId: String?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    fullScreenLoading()
                } else if let loadError {
                    Text(loadError).foregroundColor(.dangerColor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if orders.isEmpty {
                    Text("Không tìm thấy đơn nào.").foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(orders) { order in
                        Button { Task { await pick(order) } } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(order.customerName.isEmpty ? order.code : order.customerName)
                                        .font(.subheadline.bold())
                                    if order.isImported {
                                        Text("Đã bắt đơn")
                                            .font(.caption2.bold())
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.successColor)
                                            .clipShape(Capsule())
                                    }
                                    Spacer()
                                    Text(HoaDonFormatting.money(order.total))
                                        .font(.subheadline.bold()).foregroundColor(.primary)
                                }
                                if !order.address.isEmpty {
                                    Text(order.address).font(.caption).foregroundColor(.textMuted).lineLimit(1)
                                }
                                HStack {
                                    Text(order.displayTime).font(.caption2).foregroundColor(.textMuted)
                                    Spacer()
                                    if let shipperName = order.shipperName, !shipperName.isEmpty {
                                        Text(shipperName).font(.caption.bold()).foregroundColor(.brandPrimary)
                                    }
                                    if fetchingId == order.id { ProgressView().scaleEffect(0.7) }
                                }
                            }
                        }
                        .disabled(fetchingId != nil)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Bắt đơn App")
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
            let result = await APIClient.shared.getAppOrderList()
            orders = result.orders
            loadError = result.message
            loading = false
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func pick(_ order: AppOrderSummaryDto) async {
        fetchingId = order.id
        let result = await APIClient.shared.getAppOrderDetail(order.id)
        fetchingId = nil
        guard let detail = result.detail else {
            loadError = result.message ?? "Không lấy được chi tiết đơn."
            return
        }
        onPick(buildDraftItems(from: detail), detail.ghiChu ?? "", result.warnings, detail.khachHangId)
    }

    /// Guid rỗng = server không khớp được topping theo tên (MapBienThe/ToppingDtos phía server) —
    /// bỏ qua, không gửi lên vì backend AddAsync sẽ insert ToppingId rỗng gây lỗi FK.
    private func buildDraftItems(from detail: AppOrderDetailDto) -> [DraftChiTiet] {
        (detail.chiTietHoaDons ?? []).map { ct in
            let toppings = (ct.toppingDtos ?? [])
                .filter { $0.soLuong > 0 && $0.id != "00000000-0000-0000-0000-000000000000" }
                .map { DraftTopping(toppingId: $0.id, ten: $0.ten, gia: $0.gia, soLuong: $0.soLuong) }
            return DraftChiTiet(
                sanPhamBienTheId: ct.sanPhamBienTheId, tenSanPham: ct.tenSanPham, tenBienThe: ct.tenBienThe,
                soLuong: ct.soLuong, donGia: ct.donGia, toppings: toppings
            )
        }
    }
}

/// "Đơn 7h" — danh sách khách hay gọi trước 7h sáng, chọn 1 khách để mở form tạo đơn Ship đã
/// điền sẵn khách + món cuối họ từng gọi. Khớp KhachGoiSomAsync/OpenKhachGoiSom (Desktop,
/// HoaDonTabControl.Board.cs) — server đã gộp sẵn 70% khách quen/30% khách mới, sort theo SoLan.
private struct KhachGoiSomSheet: View {
    /// (khachHangId, tenSanPham, tenBienThe)
    let onPick: (String, String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [KhachHangGoiSomDto] = []
    @State private var loading = true

    private var regulars: [KhachHangGoiSomDto] { items.filter { !$0.laKhachMoi } }
    private var moi: [KhachHangGoiSomDto] { items.filter { $0.laKhachMoi } }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    fullScreenLoading()
                } else if items.isEmpty {
                    Text("Chưa có dữ liệu khách hay gọi trước 7h.")
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !regulars.isEmpty {
                            Section {
                                ForEach(regulars) { row($0) }
                            }
                        }
                        if !moi.isEmpty {
                            Section("Khách mới") {
                                ForEach(moi) { row($0) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Khách hay gọi trước 7h")
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
            items = await APIClient.shared.getKhachHangHayGoiSom()
            loading = false
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ item: KhachHangGoiSomDto) -> some View {
        Button {
            onPick(item.khachHangId, item.tenSanPham, item.tenBienThe)
        } label: {
            HStack {
                Text(item.ten).font(.subheadline.bold())
                Spacer()
                Text(monText(item)).font(.caption).foregroundColor(.textMuted).lineLimit(1)
            }
        }
    }

    private func monText(_ item: KhachHangGoiSomDto) -> String {
        guard !item.tenSanPham.isEmpty else { return "" }
        if item.tenBienThe.isEmpty || item.tenBienThe == "Mặc định" || item.tenBienThe == "Size Chuẩn" {
            return item.tenSanPham
        }
        return "\(item.tenSanPham) (\(item.tenBienThe))"
    }
}
