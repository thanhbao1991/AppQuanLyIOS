import SwiftUI

/// Chỉnh ngưỡng/số tiền các tính năng giữ chân khách trong app khách (AppDatHangIOS) — Ly Bí Mật,
/// giới thiệu bạn bè, sinh nhật, vòng quay may mắn, thẻ sưu tập ly — và phí ship (không thuộc
/// gamification nhưng dùng chung API/màn hình config app khách này cho gọn). GET/PUT
/// api/GamificationConfig.
struct GamificationConfigView: View {
    @State private var config: GamificationConfigDto?
    @State private var hasLoaded = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?

    var body: some View {
        Group {
            if !hasLoaded {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else if let configBinding = Binding($config) {
                GamificationConfigForm(config: configBinding, errorMessage: errorMessage, savedMessage: savedMessage)
            }
        }
        .navigationTitle("Cấu hình App khách")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(saving ? "Đang lưu..." : "Lưu") {
                    Task { await save() }
                }
                .disabled(saving || config == nil)
            }
        }
        .task { await load() }
    }

    private func load() async {
        config = await APIClient.shared.getGamificationConfig()
        hasLoaded = true
    }

    private func save() async {
        guard let cfg = config else { return }
        saving = true
        errorMessage = nil
        savedMessage = nil
        let result = await APIClient.shared.updateGamificationConfig(cfg)
        saving = false
        if result.success {
            savedMessage = result.message ?? "Đã lưu."
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}

private struct GamificationConfigForm: View {
    @Binding var config: GamificationConfigDto
    let errorMessage: String?
    let savedMessage: String?

    var body: some View {
        Form {
            Section {
                moneyRow("Giá khách trả", value: $config.lyBiMatGiaTraTien)
                moneyRow("Ngưỡng giá thật tối đa", value: $config.lyBiMatNguongGiaThat)
            } header: {
                Text("Ly Bí Mật 🎁")
            } footer: {
                Text("Chỉ món có giá thật ≤ ngưỡng mới được đưa vào bốc ngẫu nhiên.")
            }

            Section {
                moneyRow("Thưởng mỗi bên", value: $config.gioiThieuThuong)
            } header: {
                Text("Giới thiệu bạn bè 👥")
            } footer: {
                Text("Cả người giới thiệu và người được giới thiệu đều nhận số tiền này vào ví.")
            }

            Section("Sinh nhật 🎂") {
                moneyRow("Quà sinh nhật (1 lần/năm)", value: $config.sinhNhatThuong)
            }

            Section {
                HStack {
                    Text("Số km đầu miễn phí")
                    Spacer()
                    TextField("3", value: $config.shipKmMienPhi, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("km").foregroundColor(.textMuted)
                }
                moneyRow("Phí mỗi km tiếp theo", value: $config.shipPhiMoiKm)
                moneyRow("Đơn từ giá trị này thì luôn miễn phí ship", value: $config.shipDonGiaMienPhi)
            } header: {
                Text("Phí ship 🛵")
            } footer: {
                Text("Mặc định MIỄN PHÍ ship. Chỉ tính phí khi đơn CHƯA đạt mốc giá trị ở trên VÀ ở ngoài \(config.shipKmMienPhi, format: .number)km đầu — lúc đó mới cộng thêm theo km vượt, làm tròn lên 1.000đ. Đơn đạt mốc giá trị thì luôn miễn phí dù xa bao nhiêu.")
            }

            Section("Thẻ sưu tập ly 🧋") {
                HStack {
                    Text("Số đơn / lần đổi thưởng")
                    Spacer()
                    TextField("10", value: $config.stampMocThuong, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section {
                ForEach($config.vongQuayPhanThuong) { $item in
                    VongQuayRowEditor(item: $item, phanTramText: phanTram(item, in: config.vongQuayPhanThuong))
                }
                .onDelete { offsets in
                    config.vongQuayPhanThuong.remove(atOffsets: offsets)
                }

                Button {
                    config.vongQuayPhanThuong.append(VongQuayPhanThuongDto(label: "Ô thưởng mới", trongSo: 10, thuong: 0))
                } label: {
                    Label("Thêm ô thưởng", systemImage: "plus.circle")
                }
            } header: {
                Text("Vòng quay may mắn 🎡")
            } footer: {
                Text("Trọng số càng cao thì % trúng càng lớn. Tiền thưởng = 0 nghĩa là \"không trúng\".")
            }

            if let errorMessage {
                Text(errorMessage).foregroundColor(.dangerColor)
            }
            if let savedMessage {
                Text(savedMessage).foregroundColor(.successColor)
            }
        }
        .tint(.brandPrimary)
    }

    private func moneyRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
            Text("đ").foregroundColor(.textMuted)
        }
    }

    private func phanTram(_ item: VongQuayPhanThuongDto, in list: [VongQuayPhanThuongDto]) -> String {
        let tong = list.reduce(0) { $0 + $1.trongSo }
        guard tong > 0 else { return "0%" }
        let pct = Double(item.trongSo) / Double(tong) * 100
        return String(format: "%.0f%%", pct)
    }
}

private struct VongQuayRowEditor: View {
    @Binding var item: VongQuayPhanThuongDto
    let phanTramText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Nhãn hiển thị", text: $item.label)
                .font(.subheadline).fontWeight(.semibold)
            Stepper("Trọng số: \(item.trongSo) (\(phanTramText))", value: $item.trongSo, in: 1...1000)
                .font(.caption)
            HStack {
                Text("Tiền thưởng")
                    .font(.caption)
                    .foregroundColor(.textMuted)
                Spacer()
                TextField("0", value: $item.thuong, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("đ").font(.caption).foregroundColor(.textMuted)
            }
        }
        .padding(.vertical, 4)
    }
}
