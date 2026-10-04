import SwiftUI
import UIKit

/// 7 mục: Thống kê + 4 tab dùng hàng ngày (Hoá đơn/Thanh toán/Công nợ/Chi tiêu) + Công việc + Menu.
/// Dùng thanh tab TỰ VẼ (không phải SwiftUI `TabView`) vì `TabView` trên iPhone kế thừa hành vi
/// `UITabBarController`: quá 5 mục sẽ tự gộp mục thứ 5 trở đi vào 1 tab "More" do hệ thống sinh ra
/// (chỉ hiện 4 icon + "More"), không cách nào tắt được từ SwiftUI. Với 7 mục cần hiện ĐỦ cùng lúc,
/// phải tự vẽ thanh tab để né giới hạn cứng đó.
/// Menu (Công cụ/Tài khoản/Danh mục quản trị) là tab thứ 7 — trước đây mở bằng vuốt từ cạnh phải
/// (drawer/side-menu), đã bỏ vuốt (khó phát hiện, hay đụng gesture khác) và chuyển hẳn thành tab
/// bình thường (2026-09-30).
/// Không có tab "Tạo hoá đơn" (bỏ qua theo yêu cầu — làm sau cùng CreatePlus).
enum MainTab: CaseIterable {
    case thongKe, hoaDon, thanhToan, congNo, chiTieu, congViec, menu

    /// Rút ngắn còn 1 từ mỗi tab (2026-09-30) — 7 tab chen thanh tab tự vẽ, tên dài 2 từ bị chật/xuống dòng.
    var label: String {
        switch self {
        case .thongKe: "Kê"
        case .hoaDon: "Đơn"
        case .thanhToan: "Tiền"
        case .congNo: "Nợ"
        case .chiTieu: "Chi"
        case .congViec: "Việc"
        case .menu: "Menu"
        }
    }

    /// Đổi lại SF Symbol (revert 2026-09-15, đợt đổi sang emoji 2026-09-13 chỉ áp dụng phần còn lại
    /// của app) — cho phép tint theo .foregroundColor để đánh dấu tab đang chọn (xem tabBar).
    var icon: String {
        switch self {
        case .thongKe: "chart.pie"
        case .hoaDon: "doc.text"
        case .thanhToan: "creditcard"
        case .congNo: "exclamationmark.circle"
        case .chiTieu: "banknote"
        // "checklist" (không có ".fill") từng làm icon BIẾN MẤT khi chọn tab — iconFilled tự nối
        // ".fill" nhưng symbol đó không tồn tại nên Image render rỗng. checkmark.square/.fill có
        // từ iOS 13, chắc chắn có cả 2 biến thể.
        case .congViec: "checkmark.square"
        case .menu: "line.3.horizontal.circle"
        }
    }

    /// Bản .fill cùng tên — hiện khi tab đang được chọn, để khớp cảm giác native TabView.
    var iconFilled: String { "\(icon).fill" }
}

struct MainTabView: View {
    @Binding var isLoggedIn: Bool
    @ObservedObject private var activeTab = ActiveTab.shared
    @ObservedObject private var deepLink = DeepLinkRouter.shared
    @ObservedObject private var congViecBadge = CongViecBadge.shared
    @ObservedObject private var thongBaoBadge = ThongBaoBadge.shared
    @State private var showThongBaoSheet = false
    /// Mặc định Hoá đơn dù Thống kê xếp trước về vị trí hiển thị — mở app luôn vào tab Hoá đơn
    /// theo yêu cầu, thứ tự khai báo trong MainTab không nhất thiết khớp mục mặc định.
    @State private var selection: MainTab = .hoaDon

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selection {
                case .thongKe: ThongKeView(notificationBell: AnyView(notificationBell))
                case .hoaDon: HoaDonListView(notificationBell: AnyView(notificationBell))
                case .thanhToan: ThanhToanListView(notificationBell: AnyView(notificationBell))
                case .congNo: CongNoListView(notificationBell: AnyView(notificationBell))
                case .chiTieu: ChiTieuListView(notificationBell: AnyView(notificationBell))
                case .congViec: CongViecListView(notificationBell: AnyView(notificationBell))
                case .menu: MoreMenuView(isLoggedIn: $isLoggedIn)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            tabBar
        }
        .sheet(isPresented: $showThongBaoSheet) {
            ThongBaoNoiBoListView()
        }
        .task { await thongBaoBadge.refresh() }
        .onChange(of: selection) { newValue in
            switch newValue {
            case .hoaDon: activeTab.tab = .hoaDon
            case .thanhToan: activeTab.tab = .thanhToan
            case .congNo: activeTab.tab = .congNo
            case .chiTieu: activeTab.tab = .chiTieu
            case .congViec: activeTab.tab = .congViec
            default: activeTab.tab = .other
            }
            // Rời tab Công việc (vừa tick/thêm xong) hoặc mở lại app — làm mới số badge luôn khớp,
            // không chỉ dựa vào CongViecListView.load() (không mở tab đó lần nào sau khi mở app
            // thì vẫn cần 1 lần tải để có số ban đầu).
            Task { await congViecBadge.refresh() }
        }
        // Link "trasuaapp://khachhang/{id}" bấm từ Danh bạ chỉ mang được khách đến app qua tab Hoá
        // đơn (nơi có sheet tạo đơn) — chuyển tab trước, HoaDonListView tự đọc deepLink để mở sheet.
        .onChange(of: deepLink.khachHangIdToOrder) { id in
            if id != nil { selection = .hoaDon }
        }
        .task { await congViecBadge.refresh() }
    }

    /// Icon chuông đặt làm trailing TRONG header riêng của 6 tab (Thống kê/Hoá đơn/Thanh toán/Công
    /// nợ/Chi tiêu/Công việc — khớp pattern AppDatHangIOS/MainTabView.swift, notificationBell truyền
    /// AnyView xuống qua init) — thay cho bản nổi cố định .overlay(alignment: .topTrailing) trên
    /// toàn màn hình trước đây (2026-10-03). Overlay nổi tự nó vẫn bấm được (verify qua test tay),
    /// nhưng không cần thiết: AppDatHangIOS chưa bao giờ cần nổi, và tự tính padding theo chiều cao
    /// header (topSafeAreaInset + HeaderBarMetrics...) dễ lệch mỗi khi 1 tab đổi layout header — đặt
    /// thẳng vào HStack header của từng tab (view con tự layout, không phải tính tay) bền hơn. Icon
    /// trắng không cần nền tròn riêng vì 6 tab này đều có header tinted brandPrimary. Riêng tab Menu
    /// (thứ 7) KHÔNG có chuông — không có header riêng, theo yêu cầu không cần thêm cho tab đó.
    private var notificationBell: some View {
        Button { showThongBaoSheet = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                if thongBaoBadge.unreadCount > 0 {
                    Text(thongBaoBadge.unreadCount > 99 ? "99+" : "\(thongBaoBadge.unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.dangerColor)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.2))
                        .offset(x: 6, y: -4)
                }
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        // Khung cố định 22x22 cho icon — ZStack không có frame rõ ràng khiến badge
                        // (đặt lệch ra ngoài bằng .offset) trồi hẳn lên khỏi hàng tab, đè lên vùng
                        // nội dung phía trên (2026-09-28, phản hồi "layout vỡ trận"). Có frame cố
                        // định thì badge dù lệch ra ngoài vẫn tính từ đúng góc icon, không bay lung tung.
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: selection == tab ? tab.iconFilled : tab.icon)
                                .font(.system(size: 20))
                                .frame(width: 22, height: 22)
                            if tab == .congViec, congViecBadge.pendingCount > 0 {
                                Text(congViecBadge.pendingCount > 99 ? "99+" : "\(congViecBadge.pendingCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.dangerColor)
                                    .clipShape(Capsule())
                                    .offset(x: 6, y: -4)
                            }
                        }
                        .frame(width: 22, height: 22)
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(selection == tab ? .brandPrimary : .textMuted)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        // Trước 2026-10-03 root ignoresSafeArea(edges: .bottom) nên phải tự cộng tay safe area đáy
        // vào đây (xem AppMobileIOSApp.swift) — đã bỏ, giờ để SwiftUI tự đẩy VStack lên khỏi vùng
        // safe area đáy/home indicator, chỉ cần padding nhỏ cho thoáng.
        .padding(.bottom, 4)
        .background(.bar)
    }
}

private struct MoreMenuView: View {
    @Binding var isLoggedIn: Bool
    @State private var isSyncingContacts = false
    @State private var syncResultMessage: String?
    @State private var showAccessDeniedAlert = false
    @State private var aiBalance: AiBalanceDto?

    var body: some View {
        NavigationStack {
            List {
                Section("Cấu hình") {
                    NavigationLink {
                        NguyenLieuListView()
                    } label: {
                        EmojiLabel("Nguyên liệu", "🧂")
                    }
                    NavigationLink {
                        SanPhamListView()
                    } label: {
                        EmojiLabel("Sản phẩm", "🍹")
                    }
                    NavigationLink {
                        ToppingListView()
                    } label: {
                        EmojiLabel("Topping", "🧁")
                    }
                    NavigationLink {
                        CongThucListView()
                    } label: {
                        EmojiLabel("Công thức", "📋")
                    }
                    NavigationLink {
                        TenDuongListView()
                    } label: {
                        EmojiLabel("Tên đường", "🛣️")
                    }
                    NavigationLink {
                        GiaRiengListView()
                    } label: {
                        EmojiLabel("Giá riêng", "🏷️")
                    }
                    NavigationLink {
                        KhachHangListView()
                    } label: {
                        EmojiLabel("Khách hàng", "👥")
                    }
                    NavigationLink {
                        SanPhamHinhAnhListView()
                    } label: {
                        EmojiLabel("Ảnh menu", "🖼️")
                    }
                    NavigationLink {
                        ThongBaoQuanListView()
                    } label: {
                        EmojiLabel("Thông báo/Khuyến mãi", "📣")
                    }
                    NavigationLink {
                        GamificationConfigView()
                    } label: {
                        EmojiLabel("Cấu hình App khách", "🎁")
                    }
                    NavigationLink {
                        VoucherListView()
                    } label: {
                        EmojiLabel("Voucher", "🎟️")
                    }
                }

                Section("Công cụ") {
                    NavigationLink {
                        BanDoKhachHangView()
                    } label: {
                        EmojiLabel("Bản đồ khách hàng", "🗺️")
                    }
                    NavigationLink {
                        BaoHoaView()
                    } label: {
                        EmojiLabel("Phân tích bão hoà", "📈")
                    }
                    NavigationLink {
                        TinhLuongView(shipperTen: "Khánh")
                    } label: {
                        EmojiLabel("Tính lương Khánh", "⛽")
                    }
                    NavigationLink {
                        TinhLuongView(shipperTen: "Nhã")
                    } label: {
                        EmojiLabel("Tính lương Nhã", "⛽")
                    }
                    NavigationLink {
                        GiaNguyenLieuView()
                    } label: {
                        EmojiLabel("Giá cả", "🏷️")
                    }
                    NavigationLink {
                        GioThapDiemView()
                    } label: {
                        EmojiLabel("Giờ vắng khách", "🕑")
                    }

                    if let balance = aiBalance {
                        HStack {
                            EmojiLabel("Số dư AI (OpenRouter)", "🤖")
                            Spacer()
                            Text("$\(balance.remaining, specifier: "%.2f")")
                                .foregroundStyle(balance.remaining < 1 ? .red : .secondary)
                        }
                    }
                }

                Section {
                    if let name = Prefs.displayName, !name.isEmpty {
                        EmojiLabel(name, "👤")
                    }
                    NavigationLink {
                        DeviceSessionsView()
                    } label: {
                        EmojiLabel("Thiết bị đăng nhập", "📱")
                    }
                    Button {
                        Task { await syncContacts() }
                    } label: {
                        HStack {
                            EmojiLabel("Đồng bộ danh bạ", "📇")
                            Spacer()
                            if isSyncingContacts {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isSyncingContacts)
                    Button(role: .destructive) {
                        Prefs.clear()
                        Prefs.manualLogout = true
                        isLoggedIn = false
                    } label: {
                        EmojiLabel("Đăng xuất", "🚪")
                    }
                } footer: {
                    Text("Đồng bộ danh bạ: đưa tên khách hàng vào Danh bạ iPhone theo số điện thoại, để hiện tên khi khách gọi đến.\nPhiên bản \(appVersionString)")
                }
            }
            // Bỏ hẳn thanh tiêu đề "Menu" phía trên (không cần vùng top màu như các tab khác, và
            // không cần chuông thông báo ở đây theo yêu cầu) — tabBar bên dưới đã tự có nhãn "Menu"
            // rồi (2026-09-28).
            .navigationBarHidden(true)
            .tint(.brandPrimary)
            .popupHost { host in
                host
                    .alert("Đồng bộ danh bạ", isPresented: Binding(get: { syncResultMessage != nil }, set: { if !$0 { syncResultMessage = nil } })) {
                        Button("OK") { syncResultMessage = nil }
                    } message: {
                        Text(syncResultMessage ?? "")
                    }
                    .alert("Chưa cấp quyền Danh bạ", isPresented: $showAccessDeniedAlert) {
                        Button("Mở Cài đặt") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        Button("Huỷ", role: .cancel) {}
                    } message: {
                        Text("Vào Cài đặt > ĐENN > Danh bạ để bật quyền truy cập trước khi đồng bộ.")
                    }
            }
            .task {
                aiBalance = await APIClient.shared.getAiBalance()
            }
        }
    }

    // CI stamp gitSha vào CFBundleShortVersionString + build time (UTC) vào CFBundleVersion (xem
    // .github/workflows/build-ios.yml) — hiện ra đây để biết chắc điện thoại đang chạy bản build
    // nào, tránh nhầm "chưa cài bản mới" khi test tính năng vừa sửa.
    private var appVersionString: String {
        let sha = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildTime = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(sha) (\(buildTime))"
    }

    private func syncContacts() async {
        isSyncingContacts = true
        defer { isSyncingContacts = false }

        let khachHangs = await APIClient.shared.getAllKhachHang()
        do {
            let result = try await ContactSyncService.sync(khachHangs: khachHangs)
            syncResultMessage = result.summary
        } catch ContactSyncService.SyncError.accessDenied {
            showAccessDeniedAlert = true
        } catch {
            syncResultMessage = "Đồng bộ thất bại: \(error.localizedDescription)"
        }
    }
}
