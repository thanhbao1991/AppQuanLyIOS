import SwiftUI

/// Bộ đàm quầy (29/10/2026) — nút ở thanh dưới tab Đơn, cạnh nút xem màn hình Desktop. Bấm 1 lần là gọi máy quầy
/// (Desktop bật Bộ đàm, tự nhận) và 2 bên nói tự do; bấm lần nữa là gác — giống hệt quầy gọi lên (bấm 📻 / giữ
/// Space). Từ 2/11/2026 là cuộc gọi đi CallKit + WebRTC native (CuocGoiQuay.goiRa) như đang gọi Zalo: sang app khác
/// xem camera, khoá màn hình vẫn nói được (trước đây là WKWebView ẩn nên ra nền là tắt). Rung báo khi nói được.
struct BoDamButton: View {
    @StateObject private var model = BoDamModel()

    var body: some View {
        Image(systemName: bieuTuong)
            .font(.system(size: 26, weight: .semibold))
            .foregroundColor(mau)
            .symbolEffectPulse(model.dangChay && !model.daNoi)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            // Gọi phải nhấn giữ 1 giây (tránh chạm nhầm gọi quầy); đang gọi thì chạm 1 lần để gác.
            .onTapGesture {
                guard model.dangChay else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                model.bam()
            }
            .onLongPressGesture(minimumDuration: 1) {
                guard !model.dangChay else { return }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                model.bam()
            }
            .overlay(alignment: .top) {
                if model.dangChay || model.loi != nil {
                    Text(model.moTa)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(model.mauMoTa))
                        .offset(y: -44)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.dangChay)
            .animation(.easeOut(duration: 0.15), value: model.daNoi)
            .onReceive(NotificationCenter.default.publisher(for: .cuocGoiQuayDoi)) { _ in
                model.capNhat()
            }
            .accessibilityLabel(model.dangChay ? "Bộ đàm quầy — bấm để gác máy" : "Bộ đàm quầy — nhấn giữ 1 giây để gọi quầy")
    }

    private var bieuTuong: String {
        model.daNoi ? "waveform.circle.fill" : "antenna.radiowaves.left.and.right"
    }

    private var mau: Color {
        if model.daNoi { return .red }
        if model.dangChay { return .orange }
        return .brandPrimary
    }
}

private extension View {
    /// Nhấp nháy lúc đang nối (bấm rồi nhưng chưa nói được).
    @ViewBuilder func symbolEffectPulse(_ on: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, isActive: on)
        } else {
            self.opacity(on ? 0.6 : 1)
        }
    }
}

@MainActor
final class BoDamModel: ObservableObject {
    @Published private(set) var dangChay = false
    @Published private(set) var daNoi = false
    @Published var loi: String?
    private var henXoaLoi: Task<Void, Never>?

    var moTa: String {
        if let loi { return loi }
        return daNoi ? "Đang nói với quầy" : "Đang nối quầy…"
    }

    var mauMoTa: Color {
        if loi != nil { return .red }
        return daNoi ? .red : .gray
    }

    /// Bấm nút: đang tắt thì gọi quầy, đang gọi thì gác máy.
    func bam() {
        let quay = CuocGoiQuay.shared
        if dangChay { quay.gacMay(); return }
        loi = nil
        if quay.dangCo {
            baoLoi("Đang có cuộc gọi với quầy")
            return
        }
        quay.goiRa()
    }

    /// Cuộc gọi đi đổi trạng thái (CuocGoiQuay phát .cuocGoiQuayDoi).
    func capNhat() {
        let quay = CuocGoiQuay.shared
        let chayMoi = quay.dangCo && quay.laGoiRa
        let noiMoi = chayMoi && quay.daNoiQuay
        if noiMoi, !daNoi { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        dangChay = chayMoi
        daNoi = noiMoi
        if !chayMoi, let l = quay.loiGoiRa {
            quay.loiGoiRa = nil
            baoLoi(l)
        }
    }

    private func baoLoi(_ text: String) {
        loi = text
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        henXoaLoi?.cancel()
        henXoaLoi = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.loi = nil
        }
    }
}
