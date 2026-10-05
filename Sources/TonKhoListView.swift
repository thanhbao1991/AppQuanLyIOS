import SwiftUI

/// Tồn kho nguyên liệu bán hàng (Menu > Cấu hình > Tồn kho) — xem số tồn và điều chỉnh theo kiểm kê.
/// Dùng GET /api/NguyenLieuBanHang (đã có TonKho) và PUT /api/NguyenLieuBanHang/{id}/adjust.
struct TonKhoListView: View {
    @State private var items: [NguyenLieuBanHangDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var adjusting: NguyenLieuBanHangDto?

    private var filteredItems: [NguyenLieuBanHangDto] {
        let sorted = items
            .filter { $0.dangSuDung != false }
            .sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.ten.matchesSearch(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm nguyên liệu...")

            if !hasLoaded {
                fullScreenLoading()
            } else if filteredItems.isEmpty {
                Text("Chưa có nguyên liệu bán hàng")
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        Button {
                            adjusting = item
                        } label: {
                            HStack {
                                Text(item.ten)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(TonKhoFormatting.soLuong(item))
                                    .font(.body.monospacedDigit().bold())
                                    .foregroundColor(TonKhoFormatting.mau(item.tonKho))
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Tồn kho")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .sheet(item: $adjusting) { item in
            AdjustTonKhoSheet(item: item) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        items = await APIClient.shared.getNguyenLieuBanHang()
        hasLoaded = true
    }
}

/// Form điều chỉnh tồn kho theo kiểm kê — nhập số tồn thực tế, ghi đè số hiện tại.
private struct AdjustTonKhoSheet: View {
    let item: NguyenLieuBanHangDto
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var soLuongText: String
    @State private var ghiChu = ""
    @State private var saving = false
    @State private var errorMessage: String?

    init(item: NguyenLieuBanHangDto, onSaved: @escaping () -> Void) {
        self.item = item
        self.onSaved = onSaved
        _soLuongText = State(initialValue: TonKhoFormatting.soLuong(item))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tồn kho thực tế (\(item.donViTinh ?? "đơn vị"))") {
                    TextField("Số lượng", text: $soLuongText)
                        .keyboardType(.decimalPad)
                }
                Section("Ghi chú") {
                    TextField("Lý do điều chỉnh (tuỳ chọn)", text: $ghiChu)
                }
                Section {
                    Text("Hiện tại: \(TonKhoFormatting.soLuong(item)) \(item.donViTinh ?? "")")
                        .foregroundColor(.textMuted)
                }
            }
            .navigationTitle(item.ten)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { Task { await save() } }
                        .disabled(saving || parsedValue == nil)
                }
            }
            .alert("Lỗi", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var parsedValue: Double? {
        Double(soLuongText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func save() async {
        guard let value = parsedValue else { return }
        saving = true
        defer { saving = false }
        let trimmedNote = ghiChu.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = await APIClient.shared.dieuChinhTonKho(
            id: item.id,
            tonKhoThucTe: value,
            ghiChu: trimmedNote.isEmpty ? nil : trimmedNote
        )
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được tồn kho."
        }
    }
}

enum TonKhoFormatting {
    /// Số nguyên hiển thị không có phần thập phân, còn lại giữ tối đa 2 chữ số.
    static func soLuong(_ item: NguyenLieuBanHangDto) -> String {
        guard let value = item.tonKho else { return "—" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    static func mau(_ tonKho: Double?) -> Color {
        guard let tonKho else { return .textMuted }
        return tonKho < 0 ? .red : .primary
    }
}
