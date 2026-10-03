import UIKit
import UserNotifications

/// Cầu nối APNs — SwiftUI App không có hook nhận device token, phải qua UIApplicationDelegate.
/// Chỉ lo phần đăng ký/nhận token; xin quyền + gọi registerForRemoteNotifications() nằm ở
/// LoginView (sau khi đăng nhập) và ContentView (khi mở app với phiên cũ còn hiệu lực).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            _ = await APIClient.shared.registerApnsDeviceToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Đăng ký remote notification thất bại: \(error)")
    }
}

enum PushNotifications {
    /// Xin quyền (lần đầu) rồi đăng ký remote notification — gọi mỗi khi app vào trạng thái đã đăng
    /// nhập (login mới + mở app với phiên cũ còn hiệu lực), vì token APNs có thể đổi giữa các lần.
    /// Không chặn luồng gọi (fire-and-forget) — không có gì để người dùng chờ ở đây.
    static func requestAndRegister() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            guard granted else { return }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
