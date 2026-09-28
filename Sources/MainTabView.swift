import SwiftUI
import UIKit

/// 6 mục: Thống kê + 4 tab dùng hàng ngày (Hoá đơn/Thanh toán/Công nợ/Chi tiêu) + Công việc. Dùng
/// thanh tab TỰ VẼ (không phải SwiftUI `TabView`) vì `TabView` trên iPhone kế thừa hành vi
/// `UITabBarController`: quá 5 mục sẽ tự gộp mục thứ 5 trở đi vào 1 tab "More" do hệ thống sinh ra
/// (chỉ hiện 4 icon + "More"), không cách nào tắt được từ SwiftUI. Với 6 mục cần hiện ĐỦ cùng lúc,
/// phải tự vẽ thanh tab để né giới hạn cứng đó.
/// Menu (Công cụ/Tài khoản/Danh mục quản trị) KHÔNG còn là tab — mở bằng vuốt từ cạnh phải màn
/// hình vào (xem MainTabView.body), giống drawer/side-menu, để dành 6 slot tab cho các mục dùng
/// hàng ngày.
/// Không có tab "Tạo hoá đơn" (bỏ qua theo yêu cầu — làm sau cùng CreatePlus).
enum MainTab: CaseIterable {
    case thongKe, hoaDon, thanhToan, congNo, chiTieu, congViec

    var label: String {
        switch self {
        case .thongKe: "Thống kê"
        case .hoaDon: "Hoá đơn"
        case .thanhToan: "Thanh toán"
        case .congNo: "Công nợ"
        case .chiTieu: "Chi tiêu"
        case .congViec: "Công việc"
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
    /// Mặc định Hoá đơn dù Thống kê xếp trước về vị trí hiển thị — mở app luôn vào tab Hoá đơn
    /// theo yêu cầu, thứ tự khai báo trong MainTab không nhất thiết khớp mục mặc định.
    @State private var selection: MainTab = .hoaDon
    @State private var showMenu = false

    var body: some View {
        ZStack(alignment: .trailing) {
            VStack(spacing: 0) {
                ZStack(alignment: .trailing) {
                    Group {
                        switch selection {
                        case .thongKe: ThongKeView()
                        case .hoaDon: HoaDonListView()
                        case .thanhToan: ThanhToanListView()
                        case .congNo: CongNoListView()
                        case .chiTieu: ChiTieuListView()
                        case .congViec: CongViecListView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Dải bắt vuốt mở Menu — chỉ phủ vùng nội dung (KHÔNG trùm xuống tabBar bên
                    // dưới, nếu không sẽ chặn mất nút tab cuối cùng bên phải). Ẩn khi Menu đang mở
                    // để không tranh chạm với gesture đóng của panel. Chừa trống phần header (nút
                    // lọc/nút ngày nằm sát mép phải header) — nếu không, dải 44pt đè lên đúng vùng
                    // đó và highPriorityGesture nuốt mất chạm trước khi tới Button bên dưới, làm
                    // icon lọc "bấm không phản ứng gì" (2026-09-28).
                    if !showMenu {
                        VStack(spacing: 0) {
                            // Khoảng trống KHÔNG gắn gesture, đúng bằng chiều cao header tự vẽ của
                            // mọi tab (HeaderBarMetrics) — để nút lọc/nút ngày sát mép phải header
                            // nhận chạm bình thường.
                            Color.clear.frame(height: HeaderBarMetrics.rowHeight + HeaderBarMetrics.verticalPadding * 2)
                            Color.clear
                                .contentShape(Rectangle())
                                .highPriorityGesture(openMenuGesture)
                        }
                        .frame(width: 44)
                    }
                }

                Divider()
                tabBar
            }
            .disabled(showMenu)

            if showMenu {
                // Nền mờ: Color thuần, không phải List — gắn gesture thẳng lên đây AN TOÀN, không
                // đụng chạm gì đến scroll.
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .highPriorityGesture(closeMenuGesture)
                    .transition(.opacity)

                HStack(spacing: 0) {
                    Spacer()
                    // QUAN TRỌNG: gesture đóng KHÔNG được gắn lên toàn bộ panel (từng làm vậy, thấy
                    // "vuốt vào chưa có hiệu ứng" rồi fix bằng highPriorityGesture trên cả HStack —
                    // hoá ra highPriorityGesture đó nuốt luôn drag CHIỀU DỌC, làm List bên trong
                    // (MoreMenuView) mất khả năng cuộn — "sau khi mở menu không vuốt xuống xem được
                    // các mục bị khuất", 2026-09-28). Sửa: chỉ đặt 1 dải mỏng ở MÉP TRÁI panel (khu
                    // vực người dùng tự nhiên bắt đầu vuốt để đóng, giống dải mở ở MainTabView phía
                    // trên) — List phần còn lại cuộn dọc bình thường không bị tranh chấp.
                    ZStack(alignment: .leading) {
                        MoreMenuView(isLoggedIn: $isLoggedIn)
                        Color.clear
                            .frame(width: 24)
                            .contentShape(Rectangle())
                            .highPriorityGesture(closeMenuGesture)
                    }
                    .frame(width: menuPanelWidth)
                    .background(Color(.systemBackground))
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .trailing))
            }
        }
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

    private var menuPanelWidth: CGFloat { min(340, UIScreen.main.bounds.width * 0.86) }

    private var openMenuGesture: some Gesture {
        // Ngưỡng thấp (8pt) + dải bắt rộng 44pt (đủ ngón tay, không cần chạm sát mép pixel cuối
        // như trước — 24pt quá hẹp, dễ trượt ra ngoài vùng bắt) — 2026-09-28 hạ ngưỡng sau phản
        // hồi "vuốt khó lắm" với bản đầu (18pt distance + dải 24pt + translation phải > 28pt).
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard value.translation.width < -16, abs(value.translation.height) < 80 else { return }
                withAnimation(.easeInOut(duration: 0.25)) { showMenu = true }
            }
    }

    private var closeMenuGesture: some Gesture {
        // .highPriorityGesture (không phải .gesture) — panel Menu chứa List, List có pan gesture
        // riêng dễ nuốt mất cử chỉ vuốt-đóng nếu không ưu tiên tay ta trước (2026-09-28, phản hồi
        // "vuốt vào chưa có hiệu ứng đóng").
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard value.translation.width > 16, abs(value.translation.height) < 80 else { return }
                closeMenu()
            }
    }

    private func closeMenu() {
        withAnimation(.easeInOut(duration: 0.25)) { showMenu = false }
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
        // Root view ignoresSafeArea(edges: .bottom) (AppMobileIOSApp.swift) nên tab bar không tự
        // được đẩy lên khỏi thanh vuốt home indicator — cộng tay safe area đáy vào đây.
        .padding(.bottom, max(4, Self.bottomSafeAreaInset))
        .background(.bar)
    }

    private static var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
            .first?.safeAreaInsets.bottom ?? 0
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
                        GiaNguyenLieuView(phanLoai: .nguyenLieu)
                    } label: {
                        EmojiLabel("Giá nguyên liệu", "🏷️")
                    }
                    NavigationLink {
                        GiaNguyenLieuView(phanLoai: .vatLieu)
                    } label: {
                        EmojiLabel("Giá vật liệu", "📦")
                    }
                    NavigationLink {
                        GiaNguyenLieuView(phanLoai: .vatTu)
                    } label: {
                        EmojiLabel("Giá vật tư", "🧹")
                    }
                    NavigationLink {
                        GiaNguyenLieuView(phanLoai: .chiPhiKhac)
                    } label: {
                        EmojiLabel("Giá chi phí khác", "🧾")
                    }
                    NavigationLink {
                        GioThapDiemView()
                    } label: {
                        EmojiLabel("Giờ vắng khách", "🕑")
                    }

                    if let balance = aiBalance {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                EmojiLabel("Số dư AI (OpenRouter)", "🤖")
                                Spacer()
                                Text("$\(balance.remaining, specifier: "%.2f")")
                                    .foregroundStyle(balance.remaining < 1 ? .red : .secondary)
                            }
                            ForEach(balance.modelUsages) { usage in
                                Text("\(usage.tinhNang): \(usage.model)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
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
            // Menu giờ là panel trượt từ cạnh phải (không phải tab riêng) — bỏ hẳn thanh tiêu đề
            // "Menu" phía trên, không cần vùng top màu như các tab nữa (2026-09-28, theo yêu cầu).
            .navigationBarHidden(true)
            .tint(.brandPrimary)
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
