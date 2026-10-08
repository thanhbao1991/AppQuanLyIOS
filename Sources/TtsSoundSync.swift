import Foundation

/// Tải âm báo push "tiêu đề + tên khách" (backend sinh, xem TtsSoundService) vào Library/Sounds —
/// iOS chỉ phát được âm push nếu file nằm sẵn trong bundle hoặc thư mục này.
enum TtsSoundSync {
    private static var running = false

    @MainActor
    static func sync() async {
        guard !running else { return }
        running = true
        defer { running = false }

        let fm = FileManager.default
        guard let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let dir = lib.appendingPathComponent("Sounds", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        for name in await APIClient.shared.getTtsSoundNames() {
            let dest = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { continue }
            if let data = await APIClient.shared.downloadTtsSound(name) {
                try? data.write(to: dest, options: .atomic)
            }
        }
    }
}
