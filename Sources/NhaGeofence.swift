import CoreLocation
import UIKit
import UserNotifications

/// Tự bật Nút 2 Phòng Khách khi vào vòng 100m quanh nhà (20/11/2026). iOS theo dõi "vùng" (region monitoring) ngay cả khi
/// app đã tắt — chạm vòng thì đánh thức app vài chục giây, app gọi backend /api/cong-tac/dieu-khien. Chỉ BẬT, không tự tắt.
///
/// Giới hạn của iOS cần biết: vòng nhỏ hơn ~100m không chính xác, thực tế báo "đã vào" thường trễ vài chục mét; cần quyền
/// Vị trí "Luôn luôn". Khoảng nghỉ 30 phút giữa hai lần chạy để không bật lặp khi đứng lưng chừng ranh vòng.
/// Cài đặt (bật/tắt + toạ độ nhà) nằm riêng từng máy, lưu UserDefaults — chỉ máy của chủ quán bật thì chỉ máy đó chạy.
final class NhaGeofence: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NhaGeofence()

    static let banKinh: CLLocationDistance = 100
    static let tenNut = "Nút 2 Phòng Khách"
    private static let deviceId = "ebc27f151d021907b6n6zw" // Phòng Khách (khớp Tuya:DeviceIds ở backend)
    private static let maNut = "switch_2"
    private static let regionId = "nha-bat-cong-tac"
    private static let nghiGiay: TimeInterval = 30 * 60

    private enum Key {
        static let bat = "nha_geofence_bat"
        static let lat = "nha_geofence_lat"
        static let lon = "nha_geofence_lon"
        static let lanCuoi = "nha_geofence_lan_cuoi"
    }

    private let manager: CLLocationManager
    private let defaults: UserDefaults
    private var cho: CheckedContinuation<CLLocation?, Never>?

    @Published private(set) var quyen: CLAuthorizationStatus
    @Published private(set) var bat: Bool
    @Published private(set) var viTriNha: CLLocationCoordinate2D?

    private override init() {
        let m = CLLocationManager()
        let d = UserDefaults.standard
        manager = m
        defaults = d
        quyen = m.authorizationStatus
        bat = d.bool(forKey: Key.bat)
        if d.object(forKey: Key.lat) != nil {
            viTriNha = CLLocationCoordinate2D(latitude: d.double(forKey: Key.lat), longitude: d.double(forKey: Key.lon))
        } else {
            viTriNha = nil
        }
        super.init()
        m.delegate = self
    }

    /// Gọi ngay lúc mở app (AppDelegate) — iOS đánh thức app đã tắt vì vùng này thì cũng phải có delegate sẵn để nhận.
    func khoiDong() { capNhatGiamSat() }

    var duQuyen: Bool { quyen == .authorizedAlways }

    func datBat(_ moi: Bool) {
        guard moi != bat else { return }
        if moi && viTriNha == nil { return } // chưa đặt nhà thì không bật được
        bat = moi
        defaults.set(moi, forKey: Key.bat)
        if moi && quyen != .authorizedAlways { manager.requestAlwaysAuthorization() }
        capNhatGiamSat()
    }

    /// Lấy vị trí hiện tại làm nhà (đứng tại nhà bấm). false = không lấy được vị trí.
    func datNhaTaiViTriHienTai() async -> Bool {
        if quyen == .notDetermined { manager.requestAlwaysAuthorization() }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        guard let vt = await layViTriMotLan() else { return false }
        datNha(vt.coordinate)
        return true
    }

    /// Dùng toạ độ nhà do máy chủ giữ (không cần đứng tại nhà). false = máy chủ chưa cài hoặc không có mạng.
    func datNhaTuMayChu() async -> Bool {
        guard let vt = await APIClient.shared.getViTriNha() else { return false }
        datNha(CLLocationCoordinate2D(latitude: vt.lat, longitude: vt.long))
        return true
    }

    private func datNha(_ c: CLLocationCoordinate2D) {
        viTriNha = c
        defaults.set(c.latitude, forKey: Key.lat)
        defaults.set(c.longitude, forKey: Key.lon)
        capNhatGiamSat()
    }

    private func layViTriMotLan() async -> CLLocation? {
        await withCheckedContinuation { c in
            cho?.resume(returning: nil)
            cho = c
            manager.requestLocation()
        }
    }

    private func capNhatGiamSat() {
        for r in manager.monitoredRegions where r.identifier == Self.regionId { manager.stopMonitoring(for: r) }
        guard bat, let nha = viTriNha, quyen == .authorizedAlways, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let vung = CLCircularRegion(center: nha, radius: Self.banKinh, identifier: Self.regionId)
        vung.notifyOnEntry = true
        vung.notifyOnExit = false
        manager.startMonitoring(for: vung)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let moi = manager.authorizationStatus
        DispatchQueue.main.async {
            self.quyen = moi
            self.capNhatGiamSat()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        cho?.resume(returning: locations.last)
        cho = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        cho?.resume(returning: nil)
        cho = nil
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.regionId, bat else { return }
        let truoc = defaults.double(forKey: Key.lanCuoi)
        if Date().timeIntervalSince1970 - truoc < Self.nghiGiay { return }

        // Xin thêm thời gian nền để kịp gọi backend (app vừa được đánh thức, chỉ có vài giây).
        var tacVu = UIBackgroundTaskIdentifier.invalid
        tacVu = UIApplication.shared.beginBackgroundTask(withName: "nha-bat-cong-tac") {
            UIApplication.shared.endBackgroundTask(tacVu)
        }
        Task {
            var kq = await APIClient.shared.dieuKhienCongTac(deviceId: Self.deviceId, ma: Self.maNut, bat: true)
            if !kq.success {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                kq = await APIClient.shared.dieuKhienCongTac(deviceId: Self.deviceId, ma: Self.maNut, bat: true)
            }
            if kq.success { self.defaults.set(Date().timeIntervalSince1970, forKey: Key.lanCuoi) }
            await Self.baoNguoiDung(thanhCong: kq.success, loi: kq.message)
            await MainActor.run { UIApplication.shared.endBackgroundTask(tacVu) }
        }
    }

    private static func baoNguoiDung(thanhCong: Bool, loi: String?) async {
        let nd = UNMutableNotificationContent()
        nd.title = thanhCong ? "Sắp tới nhà" : "Không bật được công tắc"
        nd.body = thanhCong ? "Đã bật \(tenNut)." : "\(tenNut): \(loi ?? "lỗi không rõ")"
        nd.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "nha-bat-cong-tac", content: nd, trigger: nil))
    }
}
