import SwiftUI

/// Tồn kho nguyên liệu bán hàng (Menu > Tồn kho) — mỗi dòng 1 MÓN BÁN (Revive, Sting, Soda…), khác màn
/// "Nguyên liệu & giá" mỗi dòng 1 MÃ NHẬP HÀNG (Revive Thùng, Revive Lốc 6…). Từng gộp 2 màn làm 1 (17/10/2026)
/// nhưng 1 món bán có nhiều mã nhập nên số tồn bị lặp/khó nhìn → tách lại, có nút qua lại giữa 2 màn.
/// Quy ước: tồn ≥ 0 = đang theo dõi thật (đã kiểm kê), −9999 = chưa theo dõi. Nhóm đang theo dõi xếp theo số ly
/// size chuẩn còn bán được tăng dần (sắp hết lên đầu).
/// GET /api/NguyenLieuBanHang (TonKho + SoLyConLai), PUT /api/NguyenLieuBanHang/{id}/adjust.
struct TonKhoListView: View {
    @State private var items: [NguyenLieuBanHangDto] = []
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var searchText = ""
    /// ⭐ đang ghim — giữ local để bấm sao đổi ngay, khớp server sau khi load lại.
    @State private var yeuThichIds: Set<String> = []

    private var hienThi: [NguyenLieuBanHangDto] {
        let dangDung = items.filter { $0.dangSuDung != false }
        guard !searchText.isEmpty else { return dangDung }
        return dangDung.filter { $0.ten.matchesSearch(searchText) }
    }

    private var dangTheoDoi: [NguyenLieuBanHangDto] {
        // 18/10/2026: xếp theo số NGÀY còn lại (món sắp hết lên đầu) thay vì số ly — món bán chậm còn ít ly
        // vẫn có thể dùng rất lâu. Chưa tính được ngày (chưa có lịch sử bán) xuống cuối, rồi tới số ly, tên.
        hienThi.filter { ($0.tonKho ?? -1) >= 0 }.sorted {
            let na = $0.soNgayConLai ?? .infinity, nb = $1.soNgayConLai ?? .infinity
            if na != nb { return na < nb }
            let a = $0.soLyConLai ?? Int.max, b = $1.soLyConLai ?? Int.max
            return a != b ? a < b : $0.ten.localizedStandardCompare($1.ten) == .orderedAscending
        }
    }

    /// 18/10/2026 (BaoCaoUI): kết luận lên đầu — món nào cần nhập (hết / dưới ngưỡng / còn < 3 ngày).
    @ViewBuilder private var theKetLuan: some View {
        let can = dangTheoDoi.filter { TonKhoFormatting.mucDo($0) != nil }
        if can.isEmpty {
            TheKetLuan(mucDo: .tot, tieuDe: "Tồn kho ổn", moTa: "\(dangTheoDoi.count) món đang theo dõi đều trên ngưỡng an toàn")
        } else {
            TheKetLuan(mucDo: can.contains { TonKhoFormatting.mucDo($0) == .xau } ? .xau : .canhBao,
                       tieuDe: "\(can.count) món cần nhập",
                       moTa: can.map { TonKhoFormatting.tenGon($0.ten) }.joined(separator: ", "))
        }
    }

    private var chuaTheoDoi: [NguyenLieuBanHangDto] {
        hienThi.filter { ($0.tonKho ?? -1) < 0 }.sorted { a, b in
            let fa = yeuThichIds.contains(a.id), fb = yeuThichIds.contains(b.id)
            if fa != fb { return fa }
            return a.ten.localizedStandardCompare(b.ten) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm món tồn kho...")

            if !hasLoaded {
                fullScreenLoading()
            } else if hienThi.isEmpty && loadFailed {
                ThongKeLoadErrorBanner(text: "Chưa tải được tồn kho") { Task { await load() } }
                    .padding(12)
                Spacer()
            } else {
                List {
                    if loadFailed {
                        ThongKeLoadErrorBanner(text: "Chưa tải được tồn kho") { Task { await load() } }
                            .listRowSeparator(.hidden)
                    }
                    if !dangTheoDoi.isEmpty && searchText.isEmpty {
                        Section { theKetLuan }
                    }
                    if !dangTheoDoi.isEmpty {
                        Section("Đang theo dõi") {
                            ForEach(dangTheoDoi) { row($0) }
                        }
                    }
                    if !chuaTheoDoi.isEmpty {
                        Section("Chưa theo dõi — chạm để kiểm kê") {
                            ForEach(chuaTheoDoi) { row($0) }
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
        .toolbar {
            // Nhảy thẳng sang màn mua hàng/giá, khỏi quay ra Menu.
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { GiaNguyenLieuView() } label: {
                    Image(systemName: "leaf").foregroundColor(.white)
                }
            }
        }
        .task { await load() }
    }

    private func row(_ item: NguyenLieuBanHangDto) -> some View {
        let theoDoi = (item.tonKho ?? -1) >= 0
        return HStack(spacing: 12) {
            Button {
                toggleYeuThich(item)
            } label: {
                Image(systemName: yeuThichIds.contains(item.id) ? "star.fill" : "star")
                    .foregroundColor(yeuThichIds.contains(item.id) ? .yellow : .textMuted)
            }
            .buttonStyle(.borderless)

            NavigationLink {
                TonKhoChiTietView(nguyenLieuBanHangId: item.id) { await load() }
            } label: {
                HStack {
                    if theoDoi {
                        Circle().fill(TonKhoFormatting.mucDo(item)?.mau ?? .green).frame(width: 8, height: 8)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TonKhoFormatting.tenGon(item.ten))
                            .foregroundColor(theoDoi ? .primary : .textMuted)
                        if theoDoi, let phu = TonKhoFormatting.dongPhu(item) {
                            Text(phu).font(.caption).foregroundColor(TonKhoFormatting.mucDo(item)?.mau ?? .textMuted)
                        }
                    }
                    Spacer()
                    if theoDoi {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(TonKhoFormatting.nhan(item))
                                .font(.body.monospacedDigit().bold())
                                .foregroundColor(TonKhoFormatting.mau(item))
                            if item.soLyConLai != nil {
                                Text(TonKhoFormatting.soLuongDonVi(item))
                                    .font(.caption2).foregroundColor(.textMuted)
                            }
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        let fresh = await APIClient.shared.getNguyenLieuBanHangOrNil()
        if let fresh {
            items = fresh
            yeuThichIds = Set(fresh.filter { $0.yeuThich == true }.map(\.id))
        }
        loadFailed = fresh == nil
        hasLoaded = true
    }

    /// Bấm sao: đổi local ngay, gọi server; lỗi thì hoàn lại trạng thái cũ.
    private func toggleYeuThich(_ item: NguyenLieuBanHangDto) {
        let newValue = !yeuThichIds.contains(item.id)
        if newValue { yeuThichIds.insert(item.id) } else { yeuThichIds.remove(item.id) }
        Task {
            let ok = await APIClient.shared.setNguyenLieuBanHangYeuThich(id: item.id, value: newValue)
            if !ok { await load() }
        }
    }
}

/// Chi tiết 1 món tồn kho: số tồn/số ly + Kiểm kê + các MÃ NHẬP HÀNG nối vào (chạm → xem giá/lịch sử mua bên
/// "Nguyên liệu & giá"). Mở từ màn Tồn kho hoặc từ dòng "Tồn kho" trong chi tiết nguyên liệu.
struct TonKhoChiTietView: View {
    let nguyenLieuBanHangId: String
    var onChanged: (() async -> Void)? = nil

    @State private var item: NguyenLieuBanHangDto?
    @State private var maNhap: [NguyenLieuDto] = []
    @State private var loading = true
    @State private var showKiemKe = false

    var body: some View {
        List {
            if let item {
                Section {
                    HStack {
                        Text("Tồn kho")
                        Spacer()
                        if (item.tonKho ?? -1) >= 0 {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(TonKhoFormatting.nhan(item))
                                    .font(.title3.monospacedDigit().bold())
                                    .foregroundColor(TonKhoFormatting.mau(item))
                                if item.soLyConLai != nil {
                                    Text(TonKhoFormatting.soLuongDonVi(item)).font(.caption).foregroundColor(.textMuted)
                                }
                            }
                        } else {
                            Text("Chưa theo dõi").foregroundColor(.textMuted)
                        }
                    }
                    Button {
                        showKiemKe = true
                    } label: {
                        Label("Kiểm kê (nhập số đếm thực tế)", systemImage: "checklist")
                    }
                } footer: {
                    Text("Bán theo công thức tự trừ, nhập Chi tiêu tự cộng. Món chưa theo dõi để −9999 — kiểm kê để bắt đầu theo dõi.")
                }

                Section("Mã nhập hàng") {
                    if maNhap.isEmpty {
                        Text("Chưa có mã nhập hàng nào nối vào món này.").foregroundColor(.textMuted)
                    }
                    ForEach(maNhap) { nl in
                        NavigationLink {
                            GiaNguyenLieuDetailView(nguyenLieu: nl) { await load() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(nl.ten)
                                    if let h = nl.heSoQuyDoiBanHang, h > 0 {
                                        Text("1 \(nl.donViTinh ?? "") = \(TonKhoNguyenLieu.so(h)) \(item.donViTinh ?? "")")
                                            .font(.caption).foregroundColor(.textMuted)
                                    }
                                }
                                Spacer()
                                Text(HoaDonFormatting.money(nl.giaNhap))
                                    .font(.subheadline).foregroundColor(.brandPrimary)
                            }
                        }
                    }
                }
            } else if loading {
                Section { ProgressView().frame(maxWidth: .infinity) }
            } else {
                Section { Text("Không tìm thấy món tồn kho.").foregroundColor(.textMuted) }
            }
        }
        .navigationTitle(item.map { TonKhoFormatting.tenGon($0.ten) } ?? "Tồn kho")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showKiemKe) {
            if let item {
                AdjustTonKhoSheet(item: item) {
                    Task {
                        await load()
                        await onChanged?()
                    }
                }
            }
        }
    }

    private func load() async {
        async let bhTask = APIClient.shared.getNguyenLieuBanHangOrNil()
        async let nlTask = APIClient.shared.getNguyenLieuOrNil()
        if let bh = await bhTask {
            item = bh.first { $0.id == nguyenLieuBanHangId }
        }
        if let nl = await nlTask {
            maNhap = nl.filter { $0.nguyenLieuBanHangId == nguyenLieuBanHangId && !$0.ngungSuDung }
                .sorted { ($0.heSoQuyDoiBanHang ?? 0) < ($1.heSoQuyDoiBanHang ?? 0) }
        }
        loading = false
    }
}

/// Form điều chỉnh tồn kho theo kiểm kê — nhập số tồn thực tế (đơn vị bán), ghi đè số hiện tại.
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
        // Chưa theo dõi (âm) thì để trống cho nhập số đếm, khỏi phải xoá "-9999".
        _soLuongText = State(initialValue: (item.tonKho ?? -1) >= 0 ? TonKhoFormatting.soLuong(item) : "")
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
                    Text("Hiện tại: \((item.tonKho ?? -1) >= 0 ? "\(TonKhoFormatting.soLuong(item)) \(item.donViTinh ?? "")" : "chưa theo dõi")")
                        .foregroundColor(.textMuted)
                }
            }
            .navigationTitle(TonKhoFormatting.tenGon(item.ten))
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

    /// "Revive Chai (Lon)" → "Revive Chai", "Soda (G)" → "Soda" — đơn vị đã hiện ở số bên phải.
    static func tenGon(_ ten: String) -> String {
        guard ten.hasSuffix(")"), let mo = ten.lastIndex(of: "(") else { return ten }
        let gon = ten[..<mo].trimmingCharacters(in: .whitespaces)
        return gon.isEmpty ? ten : gon
    }

    /// "5 Lon" / "1600 G".
    static func soLuongDonVi(_ item: NguyenLieuBanHangDto) -> String {
        "\(soLuong(item)) \(item.donViTinh ?? "")".trimmingCharacters(in: .whitespaces)
    }

    /// Nhãn chính: "5 ly" khi biết số ly size chuẩn, không thì số tồn kèm đơn vị.
    static func nhan(_ item: NguyenLieuBanHangDto) -> String {
        if let ly = item.soLyConLai { return "\(ly) ly" }
        return soLuongDonVi(item)
    }

    static func mau(_ item: NguyenLieuBanHangDto) -> Color {
        guard let tonKho = item.tonKho else { return .textMuted }
        if tonKho < 0 { return .red }
        if tonKho == 0 || (item.soLyConLai ?? 99) <= 2 { return .orange }
        return mucDo(item)?.mau ?? .primary
    }

    /// Mức độ món đang theo dõi, khớp Trợ lý ảo: hết → xấu; dưới ngưỡng an toàn hoặc còn < 3 ngày → cảnh
    /// báo; nil = ổn (hoặc chưa theo dõi).
    static func mucDo(_ item: NguyenLieuBanHangDto) -> MucDo? {
        guard let ton = item.tonKho, ton >= 0 else { return nil }
        if ton == 0 { return .xau }
        if let n = item.canhBaoDuoi, n > 0, ton < n { return .canhBao }
        if let ngay = item.soNgayConLai, ngay < 3 { return .canhBao }
        return nil
    }

    /// "còn ~10 ngày · dưới ngưỡng 12" — nil khi chưa có gì để nói.
    static func dongPhu(_ item: NguyenLieuBanHangDto) -> String? {
        guard let ton = item.tonKho, ton >= 0 else { return nil }
        if ton == 0 { return "Hết hàng" }
        var phan: [String] = []
        if let ngay = item.soNgayConLai { phan.append(ngay < 1 ? "còn dưới 1 ngày" : "còn ~\(Int(ngay.rounded())) ngày") }
        if let n = item.canhBaoDuoi, n > 0, ton < n { phan.append("dưới ngưỡng \(TonKhoNguyenLieu.so(n))") }
        return phan.isEmpty ? nil : phan.joined(separator: " · ")
    }
}
