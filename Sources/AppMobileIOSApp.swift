import SwiftUI

@main
struct AppMobileIOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                // ĐÃ BỎ .ignoresSafeArea(edges: .bottom) (2026-10-03) — nghi đây là nguyên nhân
                // thanh tab tự vẽ (MainTabView.tabBar) không bấm được trên iPhone 13 Pro/iOS 26: tab
                // bar nằm NGAY trong vùng safe-area đáy bị bỏ qua, có thể bị vùng gesture home-
                // indicator (to hơn ở iOS 26?) chặn touch dù nút chuông nổi (không ở đáy) vẫn bấm
                // được bình thường. Để SwiftUI tự quản safe-area đáy — MainTabView.tabBar đã bỏ
                // cộng tay bottomSafeAreaInset tương ứng, xem comment ở đó.
                // Màu nền card (pastelBackground) cố định sáng bất kể theme, nhưng chữ mặc định
                // (.primary) tự đổi trắng theo Dark Mode hệ thống — gây chữ trắng trên nền sáng,
                // mất tương phản. Khoá app luôn Light để khớp bộ màu vốn thiết kế cho nền sáng.
                .preferredColorScheme(.light)
                .onOpenURL { DeepLinkRouter.shared.handle($0) }
        }
    }
}
