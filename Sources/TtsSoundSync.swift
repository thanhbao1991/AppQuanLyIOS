import Foundation

/// Tải âm báo push (backend sinh, xem TtsSoundService) vào Library/Sounds — iOS chỉ phát được âm push nếu file
/// nằm sẵn trong bundle, Library/Sounds của app, hoặc Library/Sounds của App Group.
///
/// Từ 13/11/2026 lưu ở App Group (`appGroup`) để Notification Service Extension (ThongBaoExt) đọc được các mảnh
/// tên/thao tác/chữ số và ghép thành câu có số tiền. Máy chưa có App Group (bản ký thiếu quyền) thì vẫn dùng
/// Library/Sounds của app như cũ.
enum TtsSoundSync {
    static let appGroup = "group.com.denncoffee.appquanly"
    private static var running = false

    /// Thư mục âm báo đang dùng: App Group nếu có, không thì Library/Sounds của app.
    static var soundsDir: URL? {
        let fm = FileManager.default
        if let group = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return group.appendingPathComponent("Library/Sounds", isDirectory: true)
        }
        return fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Chuyển file đã tải ở Library/Sounds của app (bản cũ) sang App Group — khỏi tải lại hơn nghìn file.
    private static func chuyenSangAppGroup(_ dir: URL) {
        let fm = FileManager.default
        guard let cu = fm.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Sounds", isDirectory: true),
              cu.standardizedFileURL != dir.standardizedFileURL else { return }
        for f in (try? fm.contentsOfDirectory(atPath: cu.path)) ?? [] where f.hasPrefix("n_") && f.hasSuffix(".wav") {
            let dich = dir.appendingPathComponent(f)
            if fm.fileExists(atPath: dich.path) {
                try? fm.removeItem(at: cu.appendingPathComponent(f))
            } else {
                try? fm.moveItem(at: cu.appendingPathComponent(f), to: dich)
            }
        }
    }

    @MainActor
    static func sync() async {
        guard !running else { return }
        running = true
        defer { running = false }

        let fm = FileManager.default
        guard let dir = soundsDir else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        chuyenSangAppGroup(dir)

        let names = await APIClient.shared.getTtsSoundNames()
        if !names.isEmpty {
            let keep = Set(names)
            for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("n_") && f.hasSuffix(".wav") && !keep.contains(f) {
                try? fm.removeItem(at: dir.appendingPathComponent(f))
            }
        }
        for name in names {
            let dest = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { continue }
            if let data = await APIClient.shared.downloadTtsSound(name) {
                try? data.write(to: dest, options: .atomic)
            }
        }
    }
}
