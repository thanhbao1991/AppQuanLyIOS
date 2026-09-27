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
        case .congViec: "checklist"
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
                    // để không tranh chạm với gesture đóng của panel.
                    if !showMenu {
                        Color.clear
                            .frame(width: 24)
                            .contentShape(Rectangle())
                            .gesture(openMenuGesture)
                    }
                }

                Divider()
                tabBar
            }
            .disabled(showMenu)

            if showMenu {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { closeMenu() }
                    .transition(.opacity)

                HStack(spacing: 0) {
                    Spacer()
                    MoreMenuView(isLoggedIn: $isLoggedIn)
                        .frame(width: menuPanelWidth)
                        .background(Color(.systemBackground))
                }
                .ignoresSafeArea(edges: .bottom)
                .gesture(closeMenuGesture)
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
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard value.translation.width < -28, abs(value.translation.height) < 50 else { return }
                withAnimation(.easeInOut(duration: 0.25)) { showMenu = true }
            }
    }

    private var closeMenuGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard value.translation.width > 40 else { return }
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
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: selection == tab ? tab.iconFilled : tab.icon)
                                .font(.system(size: 20))
                            if tab == .congViec, congViecBadge.pendingCount > 0 {
                                Text(congViecBadge.pendingCount > 99 ? "99+" : "\(congViecBadge.pendingCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.dangerColor)
                                    .clipShape(Capsule())
                                    .offset(x: 12, y: -8)
                            }
                        }
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
                Section {
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
                } footer: {
                    Text("Đưa tên khách hàng vào Danh bạ iPhone theo số điện thoại, để hiện tên khi khách gọi đến.")
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
                    Button(role: .destructive) {
                        Prefs.clear()
                        Prefs.manualLogout = true
                        isLoggedIn = false
                    } label: {
                        EmojiLabel("Đăng xuất", "🚪")
                    }
                } footer: {
                    Text("Phiên bản \(appVersionString)")
                }
            }
            // Trước đây ẩn hẳn nav bar khiến tab Menu thiếu vùng top màu như 5 tab kia — đổi sang
            // nav bar thường (tiêu đề "Menu") tô brandPrimary, khớp mọi màn hình con đã chuẩn hoá.
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
