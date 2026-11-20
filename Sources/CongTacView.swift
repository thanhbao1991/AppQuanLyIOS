import SwiftUI

/// Công tắc thông minh (Tuya/Smart Life) — mỗi bảng 1 thẻ, mỗi nút 1 ô ON/OFF, nút nguồn tròn bật/tắt cả bảng
/// (giống màn Favorites của Smart Life, 20/11/2026). Backend giữ khoá Tuya, app chỉ gọi /api/cong-tac.
///
/// Không tự làm mới theo chu kỳ: mỗi lần tải backend gọi Tuya 1 lần cho mỗi bảng (hạn mức gói miễn phí có hạn).
/// Tải khi mở màn, kéo xuống để làm mới, và 2 giây sau mỗi lần bấm (Tuya cập nhật trạng thái hơi trễ).
struct CongTacView: View {
    @State private var thietBis: [CongTacThietBiDto] = []
    @State private var dangTai = true
    @State private var loi: String?
    /// Khoá "deviceId|ma" (ma rỗng = cả bảng) đang chờ Tuya phản hồi — chặn bấm dồn.
    @State private var dangGui: Set<String> = []
    @State private var baoLoi: String?

    private static let mauNut: [Color] = [
        Color(red: 0.31, green: 0.76, blue: 0.97), // xanh dương
        Color(red: 0.30, green: 0.80, blue: 0.40), // xanh lá
        Color(red: 1.00, green: 0.62, blue: 0.45), // cam
        Color(red: 1.00, green: 0.82, blue: 0.25), // vàng
    ]
    private static let mauNguon = Color(red: 0.13, green: 0.82, blue: 0.62)

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let loi, thietBis.isEmpty {
                    Text(loi).font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.top, 60).padding(.horizontal, 24)
                } else if dangTai && thietBis.isEmpty {
                    ProgressView().padding(.top, 60)
                }
                ForEach(thietBis) { tb in card(tb) }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .refreshable { await tai() }
        .navigationTitle("Công tắc")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Không điều khiển được", isPresented: Binding(get: { baoLoi != nil }, set: { if !$0 { baoLoi = nil } })) {
            Button("Đóng", role: .cancel) {}
        } message: { Text(baoLoi ?? "") }
        .task { await tai() }
    }

    // MARK: - Thẻ 1 bảng

    private func card(_ tb: CongTacThietBiDto) -> some View {
        let conBat = tb.nuts.contains { $0.bat }
        let khoaCaBang = !tb.online || dangGui.contains(khoa(tb.id, nil))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tb.ten).font(.headline)
                    if !tb.online { Text("Ngoại tuyến").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button {
                    Task { await dieuKhien(tb, nut: nil, bat: !conBat) }
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(conBat && tb.online ? Self.mauNguon : Color(.systemGray3)))
                }
                .buttonStyle(.plain)
                .disabled(khoaCaBang)
            }
            HStack(alignment: .top, spacing: 0) {
                ForEach(tb.nuts, id: \.ma) { nut in
                    nutView(tb, nut)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        .opacity(tb.online ? 1 : 0.55)
    }

    private func nutView(_ tb: CongTacThietBiDto, _ nut: CongTacNutDto) -> some View {
        let mau = Self.mauNut[(max(nut.so, 1) - 1) % Self.mauNut.count]
        return Button {
            Task { await dieuKhien(tb, nut: nut, bat: !nut.bat) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(nut.bat ? mau : Color(.systemGray3))
                Text("Nút \(nut.so)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(nut.bat ? "BẬT" : "TẮT").font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tb.online || dangGui.contains(khoa(tb.id, nut.ma)) || dangGui.contains(khoa(tb.id, nil)))
    }

    // MARK: - Dữ liệu

    private func khoa(_ id: String, _ ma: String?) -> String { "\(id)|\(ma ?? "")" }

    private func tai() async {
        let kq = await APIClient.shared.getCongTac()
        dangTai = false
        if let d = kq.data { thietBis = d; loi = nil } else { loi = kq.loi }
    }

    /// Cập nhật ngay trên màn hình (lạc quan), gửi Tuya, lỗi thì trả lại như cũ và báo.
    private func dieuKhien(_ tb: CongTacThietBiDto, nut: CongTacNutDto?, bat: Bool) async {
        let k = khoa(tb.id, nut?.ma)
        guard !dangGui.contains(k), let i = thietBis.firstIndex(where: { $0.id == tb.id }) else { return }
        let cu = thietBis[i].nuts
        dangGui.insert(k)
        if let nut {
            if let j = thietBis[i].nuts.firstIndex(where: { $0.ma == nut.ma }) { thietBis[i].nuts[j].bat = bat }
        } else {
            for j in thietBis[i].nuts.indices { thietBis[i].nuts[j].bat = bat }
        }
        let kq = await APIClient.shared.dieuKhienCongTac(deviceId: tb.id, ma: nut?.ma, bat: bat)
        dangGui.remove(k)
        if kq.success {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await tai()
        } else {
            if let i2 = thietBis.firstIndex(where: { $0.id == tb.id }) { thietBis[i2].nuts = cu }
            baoLoi = kq.message ?? "Tuya không phản hồi."
        }
    }
}
