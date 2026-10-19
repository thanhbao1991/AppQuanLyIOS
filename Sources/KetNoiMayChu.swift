import Foundation
import Network
import SwiftUI

/// Theo dõi kết nối tới Backend để hiện thanh "Không kết nối được máy chủ" (2026-10-19, sau vụ VPS Contabo
/// bị reboot host 18:17-18:49: app chỉ trống trơn, không ai biết là máy chủ sập). Mọi request đi qua
/// APIClient.send() báo kết quả vào đây; lỗi 2 lần liên tiếp mới hiện (tránh nháy vì 1 request rớt lẻ), có
/// 1 request thành công là tắt. Lúc đang hiện thì tự gọi /health mỗi 15s để tự tắt khi máy chủ lên lại,
/// không bắt người dùng kéo làm mới. Phân biệt điện thoại mất mạng (NWPathMonitor) với máy chủ sập.
@MainActor
final class KetNoiMayChu: ObservableObject {
    static let shared = KetNoiMayChu()

    enum TrangThai: Equatable {
        case ok
        case matMang
        case mayChuLoi
    }

    @Published private(set) var trangThai: TrangThai = .ok
    @Published private(set) var dangKiemTra = false

    private var soLanLoi = 0
    private var coMang = true
    private let monitor = NWPathMonitor()
    private var pollTask: Task<Void, Never>?

    private init() {
        monitor.pathUpdateHandler = { path in
            let ok = path.status == .satisfied
            Task { @MainActor in KetNoiMayChu.shared.capNhatMang(ok) }
        }
        monitor.start(queue: DispatchQueue(label: "ket-noi-may-chu"))
    }

    /// Gọi từ APIClient.send() (actor khác) — có phản hồi HTTP bình thường (kể cả 4xx: máy chủ vẫn sống).
    nonisolated static func baoThanhCong() {
        Task { @MainActor in KetNoiMayChu.shared.thanhCong() }
    }

    /// Không tới được máy chủ: lỗi mạng/timeout, hoặc 502/503/504/52x (Cloudflare không tới được VPS).
    nonisolated static func baoThatBai() {
        Task { @MainActor in KetNoiMayChu.shared.thatBai() }
    }

    /// Phân loại kết quả 1 request: nil = không tính (request bị huỷ do màn hình đóng), true/false = sống/chết.
    nonisolated static func phanLoai(status: Int?, error: Error?) -> Bool? {
        if let error {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return nil }
            return false
        }
        guard let status else { return false }
        return !(status == 502 || status == 503 || status == 504 || (520...530).contains(status))
    }

    /// Bấm vào thanh → kiểm tra lại ngay.
    func kiemTraNgay() {
        Task { await kiemTraHealth() }
    }

    private func thanhCong() {
        soLanLoi = 0
        guard trangThai != .ok else { return }
        trangThai = .ok
        pollTask?.cancel()
        pollTask = nil
    }

    private func thatBai() {
        soLanLoi += 1
        guard soLanLoi >= 2 else { return }
        trangThai = coMang ? .mayChuLoi : .matMang
        batDauPoll()
    }

    private func capNhatMang(_ ok: Bool) {
        coMang = ok
        if !ok {
            trangThai = .matMang
            batDauPoll()
        } else if trangThai != .ok {
            // Có mạng lại: chưa chắc máy chủ sống — kiểm tra rồi mới tắt thanh.
            trangThai = .mayChuLoi
            kiemTraNgay()
        }
    }

    private func batDauPoll() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.kiemTraHealth()
            }
        }
    }

    private func kiemTraHealth() async {
        guard coMang else { return }
        dangKiemTra = true
        defer { dangKiemTra = false }
        var req = URLRequest(url: URL(string: Prefs.apiBase + "/health")!)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode == 200 { thanhCong() }
        } catch {}
    }
}

/// Thanh đỏ mỏng ở đầu màn khi mất kết nối máy chủ — gắn bằng safeAreaInset(edge: .top) ở ContentView để
/// đẩy nội dung xuống chứ không che ô tìm kiếm.
struct KetNoiMayChuBanner: View {
    @ObservedObject private var ketNoi = KetNoiMayChu.shared

    var body: some View {
        if ketNoi.trangThai != .ok {
            Button { ketNoi.kiemTraNgay() } label: {
                HStack(spacing: 8) {
                    Image(systemName: ketNoi.trangThai == .matMang ? "wifi.slash" : "exclamationmark.icloud.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(ketNoi.trangThai == .matMang
                         ? "Điện thoại đang mất mạng"
                         : "Không kết nối được máy chủ — số liệu có thể chưa cập nhật")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if ketNoi.dangKiemTra {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.dangerColor)
            }
            .buttonStyle(.plain)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
