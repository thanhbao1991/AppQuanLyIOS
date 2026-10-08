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
