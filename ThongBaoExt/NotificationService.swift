import UserNotifications

/// Ghép giọng đọc push "Tên khách, Thao tác, Số tiền" (khuôn chung với Desktop — CauDocThongBao ở backend).
///
/// iOS chỉ phát 1 file âm có sẵn trên máy, không tự nối nhiều file → backend gửi `manh` = danh sách file mảnh
/// (tên, thao tác, từng chữ số; "|" = nghỉ ngắn) mà app đã tải về Library/Sounds của App Group (TtsSoundSync).
/// Extension nối PCM các mảnh thành 1 wav rồi giao cho iOS phát. Thiếu mảnh/lỗi gì cũng giữ nguyên "sound"
/// backend gửi kèm (âm "Tên, Thao tác" như trước) — không bao giờ làm mất âm báo.
final class NotificationService: UNNotificationServiceExtension {
    private static let appGroup = "group.com.denncoffee.appquanly"
    private static let nghiNgan = "|"

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent) ?? UNMutableNotificationContent()
        bestAttempt = content

        if let manh = request.content.userInfo["manh"] as? [String], !manh.isEmpty,
           let ten = Self.ghep(manh) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(ten))
        }
        contentHandler(content)
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt { contentHandler(bestAttempt) }
    }

    /// Trả tên file wav đã ghép (nằm trong Library/Sounds của App Group), nil nếu thiếu mảnh hay lỗi.
    static func ghep(_ manh: [String]) -> String? {
        let fm = FileManager.default
        guard let dir = fm.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("Library/Sounds", isDirectory: true) else { return nil }

        var dinhDang: Wav.DinhDang?
        var pcm = Data()
        for m in manh {
            if m == nghiNgan {
                // Nghỉ ~0,18 giây giữa tên / thao tác / số tiền (chỉ chèn khi đã biết định dạng).
                if let d = dinhDang { pcm.append(Data(count: Int(Double(d.byteRate) * 0.18) & ~1)) }
                continue
            }
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(m)),
                  let wav = Wav.doc(data) else { return nil }
            if let d = dinhDang, d != wav.dinhDang { return nil }   // khác định dạng thì không nối được
            dinhDang = wav.dinhDang
            pcm.append(wav.pcm)
        }
        guard let dinhDang, !pcm.isEmpty else { return nil }

        // Xếp hàng: nhiều push tới cùng lúc thì iOS phát các âm ĐÈ lên nhau → chèn lặng đầu file cho tới khi
        // giọng trước đọc xong (banner vẫn hiện ngay). iOS chỉ nhận âm < 30 giây nên chờ tối đa vừa đủ.
        let byteRate = Double(dinhDang.byteRate)
        let thoiLuong = Double(pcm.count) / byteRate
        let cho = XepHang.lay(thoiLuong: thoiLuong, toiDa: max(0, 29 - thoiLuong))
        if cho > 0 {
            let khoi = max(1, Int(dinhDang.kenh) * Int(dinhDang.bit / 8))   // giữ đúng ranh giới mẫu âm
            var lang = Data(count: Int(byteRate * cho) / khoi * khoi)
            lang.append(pcm)
            pcm = lang
        }

        // Dọn file ghép cũ (> 2 phút) — iOS đã phát xong từ lâu.
        let bayGio = Date()
        for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where f.hasPrefix("ghep_") {
            let url = dir.appendingPathComponent(f)
            if let ngay = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
               bayGio.timeIntervalSince(ngay) > 120 {
                try? fm.removeItem(at: url)
            }
        }

        let ten = "ghep_\(UUID().uuidString.prefix(8)).wav"
        do {
            try Wav.ghi(dinhDang: dinhDang, pcm: pcm).write(to: dir.appendingPathComponent(ten), options: .atomic)
            return ten
        } catch {
            return nil
        }
    }
}

/// Mốc "giọng đọc trước phát tới lúc nào", lưu ở App Group để các lần chạy extension nối tiếp nhau.
enum XepHang {
    private static let khoa = "thongBao.phatDen"
    private static let khoang = 0.4          // nghỉ giữa 2 câu
    private static let khoaLuong = NSLock()

    /// Trả số giây cần chờ trước khi đọc câu dài `thoiLuong` giây, và ghi mốc mới.
    static func lay(thoiLuong: Double, toiDa: Double) -> Double {
        khoaLuong.lock(); defer { khoaLuong.unlock() }
        let ud = UserDefaults(suiteName: "group.com.denncoffee.appquanly")
        let bayGio = Date().timeIntervalSince1970
        let phatDen = ud?.double(forKey: khoa) ?? 0
        let cho = min(max(0, phatDen + khoang - bayGio), toiDa)
        ud?.set(bayGio + cho + thoiLuong, forKey: khoa)
        return cho
    }
}

/// Đọc/ghi WAV PCM tối giản: tìm chunk "fmt " + "data", bỏ qua chunk khác (LIST…).
enum Wav {
    struct DinhDang: Equatable {
        let kenh: UInt16
        let tanSo: UInt32
        let bit: UInt16
        var byteRate: UInt32 { tanSo * UInt32(kenh) * UInt32(bit / 8) }
    }

    static func doc(_ data: Data) -> (dinhDang: DinhDang, pcm: Data)? {
        let b = [UInt8](data)
        guard b.count >= 12, String(bytes: b[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: b[8..<12], encoding: .ascii) == "WAVE" else { return nil }
        func u16(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        func u32(_ i: Int) -> UInt32 { UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 }

        var i = 12
        var dd: DinhDang?
        while i + 8 <= b.count {
            let id = String(bytes: b[i..<i + 4], encoding: .ascii) ?? ""
            let size = Int(u32(i + 4))
            let start = i + 8
            if id == "fmt ", start + 16 <= b.count {
                guard u16(start) == 1 else { return nil }   // chỉ nhận PCM
                dd = DinhDang(kenh: u16(start + 2), tanSo: u32(start + 4), bit: u16(start + 14))
            } else if id == "data", let dd {
                let end = min(start + size, b.count)
                return (dd, Data(b[start..<end]))
            }
            i = start + size + (size & 1)
        }
        return nil
    }

    static func ghi(dinhDang d: DinhDang, pcm: Data) -> Data {
        var out = Data()
        func s(_ x: String) { out.append(contentsOf: Array(x.utf8)) }
        func u32(_ x: UInt32) { withUnsafeBytes(of: x.littleEndian) { out.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { withUnsafeBytes(of: x.littleEndian) { out.append(contentsOf: $0) } }
        s("RIFF"); u32(UInt32(36 + pcm.count)); s("WAVE")
        s("fmt "); u32(16); u16(1); u16(d.kenh); u32(d.tanSo); u32(d.byteRate); u16(d.kenh * (d.bit / 8)); u16(d.bit)
        s("data"); u32(UInt32(pcm.count))
        out.append(pcm)
        return out
    }
}
