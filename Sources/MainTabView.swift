import SwiftUI
import UIKit

/// 6 mục: Thống kê + 4 tab dùng hàng ngày (Hoá đơn/Thanh toán/Công nợ/Chi tiêu) + 1 tab "Menu"
/// gom Công việc/Tài khoản. Dùng thanh tab TỰ VẼ (không phải SwiftUI `TabView`) vì `TabView` trên
/// iPhone kế thừa hành vi `UITabBarController`: quá 5 mục sẽ tự gộp mục thứ 5 trở đi vào 1 tab
/// "More" do hệ thống sinh ra (chỉ hiện 4 icon + "More"), không cách nào tắt được từ SwiftUI. Với
/// 6 mục cần hiện ĐỦ cùng lúc, phải tự vẽ thanh tab để né giới hạn cứng đó.
/// Không có tab "Tạo hoá đơn" (bỏ qua theo yêu cầu — làm sau cùng CreatePlus).
enum MainTab: CaseIterable {
    case thongKe, hoaDon, thanhToan, congNo, chiTieu, menu

    var label: String {
        switch self {
        case .thongKe: "Thống kê"
        case .hoaDon: "Hoá đơn"
        case .thanhToan: "Thanh toán"
        case .congNo: "Công nợ"
        case .chiTieu: "Chi tiêu"
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
        case .menu: "ellipsis.circle"
        }
    }

    /// Bản .fill cùng tên — hiện khi tab đang được chọn, để khớp cảm giác native TabView.
    var iconFilled: String { "\(icon).fill" }
}

struct MainTabView: View {
    @Binding var isLoggedIn: Bool
    @ObservedObject private var activeTab = ActiveTab.shared
    @ObservedObject private var deepLink = DeepLinkRouter.shared
    /// Mặc định Hoá đơn dù Thống kê xếp trước về vị trí hiển thị — mở app luôn vào tab Hoá đơn
    /// theo yêu cầu, thứ tự khai báo trong MainTab không nhất thiết khớp mục mặc định.
    @State private var selection: MainTab = .hoaDon

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selection {
                case .thongKe: ThongKeView()
                case .hoaDon: HoaDonListView()
                case .thanhToan: ThanhToanListView()
                case .congNo: CongNoListView()
                case .chiTieu: ChiTieuListView()
                case .menu: MoreMenuView(isLoggedIn: $isLoggedIn)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            tabBar
        }
        .onChange(of: selection) { newValue in
            switch newValue {
            case .hoaDon: activeTab.tab = .hoaDon
            case .thanhToan: activeTab.tab = .thanhToan
            case .congNo: activeTab.tab = .congNo
            case .chiTieu: activeTab.tab = .chiTieu
            default: activeTab.tab = .other
            }
        }
        // Link "trasuaapp://khachhang/{id}" bấm từ Danh bạ chỉ mang được khách đến app qua tab Hoá
        // đơn (nơi có sheet tạo đơn) — chuyển tab trước, HoaDonListView tự đọc deepLink để mở sheet.
        .onChange(of: deepLink.khachHangIdToOrder) { id in
            if id != nil { selection = .hoaDon }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == tab ? tab.iconFilled : tab.icon)
                            .font(.system(size: 20))
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
                        CongViecListView()
                    } label: {
                        EmojiLabel("Công việc", "📋")
                    }
                    NavigationLink {
                        NguyenLieuListView()
                    } label: {
                        EmojiLabel("Nguyên liệu", "🧂")
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
