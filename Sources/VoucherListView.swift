import SwiftUI

/// Quản trị voucher app khách (AppDatHangIOS) — GET/POST/PUT/DELETE /api/Voucher. Áp dụng thật (kiểm
/// tra điều kiện, trừ giá trị đơn) nằm bên Backend (DatHangService), màn này chỉ tạo/sửa/bật-tắt.
struct VoucherListView: View {
    @State private var items: [VoucherDto] = []
    @State private var hasLoaded = false
    @State private var showAdd = false
    @State private var editing: VoucherDto?

    var body: some View {
        Group {
            if !hasLoaded {
                VStack { Spacer(); ProgressView(); Spacer() }
            } else {
                List {
                    if items.isEmpty {
                        Text("Chưa có voucher nào")
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(items) { item in
                            VoucherRowView(item: item) {
                                Task { await toggle(item) }
                            } onEdit: {
                                editing = item
                            } onDelete: {
                                Task { await delete(item) }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            .listRowSeparator(.hidden)
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("Voucher")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: { Text("➕") }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            VoucherEditSheet(existing: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            VoucherEditSheet(existing: item) { Task { await load() } }
        }
    }

    private func load() async {
        items = await APIClient.shared.getVoucherList()
        hasLoaded = true
    }

    private func toggle(_ item: VoucherDto) async {
        _ = await APIClient.shared.updateVoucher(id: item.id, VoucherRequest(
            ma: item.ma, ten: item.ten, moTa: item.moTa, soTienGiam: item.soTienGiam,
            loaiGiam: item.loaiGiam, phanTramGiam: item.phanTramGiam, giamToiDa: item.giamToiDa,
            donToiThieu: item.donToiThieu,
            dieuKien: item.dieuKien, soDonApDung: item.soDonApDung,
            gioBatDau: item.gioBatDau, gioKetThuc: item.gioKetThuc, thuTrongTuan: item.thuTrongTuan,
            bacThang: item.bacThang, soLuongToiThieu: item.soLuongToiThieu,
            yeuCauSizeL: item.yeuCauSizeL,
            mucDich: item.mucDich,
            hangToiThieu: item.hangToiThieu, dangHoatDong: !item.dangHoatDong))
        await load()
    }

    private func delete(_ item: VoucherDto) async {
        _ = await APIClient.shared.deleteVoucher(id: item.id)
        await load()
    }
}

private struct VoucherRowView: View {
    let item: VoucherDto
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.ten)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                    if item.mucDich == "TangDoanhThu" {
                        Text("📈").font(.caption)
                    } else if item.mucDich == "GiuChan" {
                        Text("🛡️").font(.caption)
                    }
                    Spacer()
                    Text(item.dangHoatDong ? "Đang hoạt động" : "Đã tắt")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(item.dangHoatDong ? Color.successColor : Color.textMuted)
                        .clipShape(Capsule())
                }
                HStack {
                    Text("Mã \(item.ma)").font(.caption).foregroundColor(.textMuted)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(nhanUuDai(item)).font(.caption).fontWeight(.bold).foregroundColor(.dangerColor)
                        if let giamToiDa = item.giamToiDa, giamToiDa > 0 {
                            Text("Tối đa \(Int(giamToiDa).formatted())đ").font(.caption2).foregroundColor(.textMuted)
                        }
                    }
                }
                if let moTa = item.moTa, !moTa.isEmpty {
                    Text(moTa).font(.caption).foregroundColor(.textMuted).lineLimit(2)
                }
                Text(nhanDieuKien(item)).font(.caption2).foregroundColor(.brandPrimary)
                if let hangToiThieu = item.hangToiThieu, !hangToiThieu.isEmpty {
                    Text("Chỉ hạng \(hangToiThieu) trở lên").font(.caption2).foregroundColor(.dangerColor)
                }
                if item.yeuCauSizeL {
                    Text("Chỉ áp dụng khi đơn có Size L").font(.caption2).foregroundColor(.dangerColor)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.brandPrimary.pastelBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onDelete) {
                EmojiLabel("Xoá", "🗑️")
            }
            Button(action: onToggle) {
                Label(item.dangHoatDong ? "Tắt" : "Bật", systemImage: item.dangHoatDong ? "pause.circle" : "play.circle")
            }
            .tint(.brandPrimary)
        }
    }

    private func nhanDieuKien(_ item: VoucherDto) -> String {
        switch item.dieuKien {
        case "DonDauTien": return "Điều kiện: đơn app đầu tiên của khách"
        case "SinhNhat": return "Điều kiện: trong tháng sinh nhật, 1 lần/năm"
        case "DonToiThieu": return "Điều kiện: đơn tối thiểu, không giới hạn số lần"
        case "KhongDieuKien": return "Điều kiện: không có, dùng cho dịp/lễ — tự bật tắt"
        case "DonThuN": return "Điều kiện: đúng đơn thứ \(item.soDonApDung ?? 0) của khách"
        case "QuayLai": return "Điều kiện: đơn quay lại sau ≥30 ngày không mua, không dùng liên tiếp 2 lần"
        case "KhungGioThapDiem":
            let thuText = (item.thuTrongTuan ?? "").split(separator: ",").compactMap { Int($0) }.sorted()
                .compactMap { tenThuNganGon[$0] }.joined(separator: "/")
            return "Điều kiện: khung \(item.gioBatDau ?? 0)h-\(item.gioKetThuc ?? 0)h\(thuText.isEmpty ? "" : " (\(thuText))")"
        case "DonToiThieuBac":
            let bacText = BacThangRow.parse(item.bacThang).map { "\(Int($0.nguong).formatted())đ→-\(Int($0.giam).formatted())đ" }.joined(separator: ", ")
            return "Điều kiện: bậc thang — \(bacText.isEmpty ? "chưa cấu hình" : bacText)"
        case "SoLuongToiThieu":
            return "Điều kiện: đơn từ \(item.soLuongToiThieu ?? 0) ly, chỉ khách CHƯA TỪNG tự mua đủ số lượng này (dùng được 1 lần)"
        case "UpsizeMonMoi":
            return "Điều kiện: tặng Size L miễn phí cho SẢN PHẨM khách chưa từng upsize (mỗi món 1 lần, không giới hạn tổng số lần)"
        default: return "Điều kiện: \(item.dieuKien)"
        }
    }

    private func nhanUuDai(_ item: VoucherDto) -> String {
        if item.dieuKien == "DonToiThieuBac" {
            let max = BacThangRow.parse(item.bacThang).map(\.giam).max() ?? 0
            return max > 0 ? "-\(Int(max).formatted())đ" : "—"
        }
        if item.loaiGiam == "PhanTram" {
            return "-\(Int(item.phanTramGiam ?? 0))%"
        }
        return "-\(Int(item.soTienGiam).formatted())đ"
    }
}

/// 1 bậc trong voucher "Bậc thang theo giá trị đơn" — encode/decode khớp Voucher.BacThang bên
/// Backend ("nguong1:giam1,nguong2:giam2,..."). id riêng (không phải nguong) để SwiftUI ForEach có
/// định danh ổn định khi staff đang gõ dở giá trị trùng nhau giữa 2 hàng.
private struct BacThangRow: Identifiable {
    let id = UUID()
    var nguong: Double
    var giam: Double

    static func parse(_ raw: String?) -> [BacThangRow] {
        (raw ?? "").split(separator: ",").compactMap { phan in
            let parts = phan.split(separator: ":")
            guard parts.count == 2, let n = Double(parts[0]), let g = Double(parts[1]) else { return nil }
            return BacThangRow(nguong: n, giam: g)
        }
    }

    /// Sắp tăng dần theo nguong trước khi encode — khớp yêu cầu backend (bậc sau phải cao hơn bậc
    /// trước), staff không cần tự nhập đúng thứ tự.
    static func encode(_ rows: [BacThangRow]) -> String? {
        let valid = rows.filter { $0.nguong > 0 && $0.giam > 0 }.sorted { $0.nguong < $1.nguong }
        guard !valid.isEmpty else { return nil }
        return valid.map { "\(Int($0.nguong)):\(Int($0.giam))" }.joined(separator: ",")
    }
}

private struct VoucherEditSheet: View {
    let existing: VoucherDto?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ma: String
    @State private var ten: String
    @State private var moTa: String
    @State private var soTienGiam: Double
    @State private var loaiGiam: String
    @State private var phanTramGiam: Double
    @State private var giamToiDa: Double
    @State private var donToiThieu: Double
    @State private var dieuKien: String
    @State private var soDonApDung: Int
    @State private var gioBatDau: Int
    @State private var gioKetThuc: Int
    /// Rỗng = áp dụng MỌI thứ trong tuần. Khớp Voucher.ThuTrongTuan ("1,3,5" = T2/T4/T6).
    @State private var thuChon: Set<Int>
    @State private var showGioThapDiem = false
    /// Chỉ có ý nghĩa khi dieuKien == "DonToiThieuBac". Xem BacThangRow.
    @State private var bacThangRows: [BacThangRow]
    /// Chỉ có ý nghĩa khi dieuKien == "SoLuongToiThieu".
    @State private var soLuongToiThieu: Int
    /// Điều kiện PHỤ, áp được cho bất kỳ dieuKien nào (KhungGioThapDiem/DonThuN/DonDauTien...).
    @State private var yeuCauSizeL: Bool
    @State private var hangToiThieu: String
    @State private var mucDich: String
    @State private var dangHoatDong: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    // Khớp VoucherDieuKien bên Backend — thêm điều kiện mới thì thêm 1 dòng ở đây.
    private let dieuKienOptions = [
        ("DonDauTien", "Đơn app đầu tiên"),
        ("SinhNhat", "Sinh nhật (1 lần/năm)"),
        ("DonToiThieu", "Đơn tối thiểu (không giới hạn)"),
        ("KhongDieuKien", "Không điều kiện (dịp/lễ — tự bật tắt)"),
        ("DonThuN", "Đơn thứ N (tự nhập)"),
        ("QuayLai", "Khách lâu không mua quay lại (không dùng liên tiếp)"),
        ("KhungGioThapDiem", "Khung giờ thấp điểm"),
        ("DonToiThieuBac", "Bậc thang theo giá trị đơn"),
        ("SoLuongToiThieu", "Số lượng ly tối thiểu"),
        ("UpsizeMonMoi", "Tặng Size L món mới (dùng thử)"),
    ]
    // Khớp VoucherLoaiGiam bên Backend.
    private let loaiGiamOptions = [
        ("SoTien", "Giảm số tiền cố định"),
        ("PhanTram", "Giảm theo %"),
    ]
    // "" = không giới hạn hạng. Khớp HangKhachHang bên Backend (Kim Cương cao nhất).
    private let hangOptions = [
        ("", "Không giới hạn hạng"),
        ("Bạc", "Bạc trở lên"),
        ("Vàng", "Vàng trở lên"),
        ("Kim Cương", "Chỉ Kim Cương"),
    ]
    // "" = chưa gắn nhãn. Khớp VoucherMucDich bên Backend.
    private let mucDichOptions = [
        ("", "Chưa gắn nhãn"),
        ("TangDoanhThu", "📈 Tăng doanh thu"),
        ("GiuChan", "🛡️ Giữ chân"),
    ]

    init(existing: VoucherDto?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _ma = State(initialValue: existing?.ma ?? "")
        _ten = State(initialValue: existing?.ten ?? "")
        _moTa = State(initialValue: existing?.moTa ?? "")
        _soTienGiam = State(initialValue: existing?.soTienGiam ?? 5000)
        _loaiGiam = State(initialValue: existing?.loaiGiam ?? "SoTien")
        _phanTramGiam = State(initialValue: existing?.phanTramGiam ?? 10)
        _giamToiDa = State(initialValue: existing?.giamToiDa ?? 0)
        _donToiThieu = State(initialValue: existing?.donToiThieu ?? 100000)
        _dieuKien = State(initialValue: existing?.dieuKien ?? "DonDauTien")
        _soDonApDung = State(initialValue: existing?.soDonApDung ?? 2)
        _gioBatDau = State(initialValue: existing?.gioBatDau ?? 14)
        _gioKetThuc = State(initialValue: existing?.gioKetThuc ?? 16)
        _thuChon = State(initialValue: Set((existing?.thuTrongTuan ?? "").split(separator: ",").compactMap { Int($0) }))
        let parsedBacThang = BacThangRow.parse(existing?.bacThang)
        _bacThangRows = State(initialValue: parsedBacThang.isEmpty ? [BacThangRow(nguong: 0, giam: 0)] : parsedBacThang)
        _soLuongToiThieu = State(initialValue: existing?.soLuongToiThieu ?? 2)
        _yeuCauSizeL = State(initialValue: existing?.yeuCauSizeL ?? false)
        _hangToiThieu = State(initialValue: existing?.hangToiThieu ?? "")
        _mucDich = State(initialValue: existing?.mucDich ?? "")
        _dangHoatDong = State(initialValue: existing?.dangHoatDong ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mã voucher") {
                    TextField("Vd: APPFIRST", text: $ma)
                        .autocapitalization(.allCharacters)
                        .disableAutocorrection(true)
                }
                Section("Tên hiển thị") {
                    TextField("Vd: Đơn App Đầu Tiên", text: $ten)
                }
                Section("Mô tả (không bắt buộc)") {
                    TextField("Hiện cho khách khi chọn voucher", text: $moTa, axis: .vertical)
                        .lineLimit(2...4)
                }
                if dieuKien != "DonToiThieuBac" {
                    Section("Loại giảm") {
                        Picker("Loại giảm", selection: $loaiGiam) {
                            ForEach(loaiGiamOptions, id: \.0) { value, label in
                                Text(label).tag(value)
                            }
                        }
                    }
                    if loaiGiam == "PhanTram" {
                        Section("Phần trăm giảm") {
                            HStack {
                                TextField("0", value: $phanTramGiam, format: .number)
                                    .keyboardType(.numberPad)
                                Text("%").foregroundColor(.textMuted)
                            }
                        }
                        Section("Trần giảm tối đa (0 = không giới hạn)") {
                            HStack {
                                TextField("0", value: $giamToiDa, format: .number)
                                    .keyboardType(.numberPad)
                                Text("đ").foregroundColor(.textMuted)
                            }
                        }
                    } else {
                        Section("Số tiền giảm") {
                            HStack {
                                TextField("0", value: $soTienGiam, format: .number)
                                    .keyboardType(.numberPad)
                                Text("đ").foregroundColor(.textMuted)
                            }
                        }
                    }
                }
                Section("Điều kiện áp dụng") {
                    Picker("Điều kiện", selection: $dieuKien) {
                        ForEach(dieuKienOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                }
                if dieuKien == "DonToiThieu" {
                    Section("Ngưỡng giá trị đơn tối thiểu") {
                        HStack {
                            TextField("0", value: $donToiThieu, format: .number)
                                .keyboardType(.numberPad)
                            Text("đ").foregroundColor(.textMuted)
                        }
                    }
                }
                if dieuKien == "DonThuN" {
                    Section("Áp dụng đúng đơn thứ") {
                        HStack {
                            TextField("2", value: $soDonApDung, format: .number)
                                .keyboardType(.numberPad)
                            Text("của khách (N ≥ 2)").foregroundColor(.textMuted)
                        }
                    }
                }
                if dieuKien == "KhungGioThapDiem" {
                    Section("Khung giờ áp dụng") {
                        Stepper("Bắt đầu: \(gioBatDau)h", value: $gioBatDau, in: 0...22)
                        Stepper("Kết thúc: \(gioKetThuc)h", value: $gioKetThuc, in: (gioBatDau + 1)...23)
                        Text("Áp dụng cho MỌI đơn trong khung giờ này (không giới hạn đơn thứ mấy trong ngày) — nên đặt % giảm nhỏ + trần tối đa thấp để hạn chế rủi ro khách trì hoãn đơn để chờ giờ rẻ.")
                            .font(.caption2).foregroundColor(.textMuted)
                    }
                    Section {
                        thuChonRow
                        Button {
                            showGioThapDiem = true
                        } label: {
                            Label("Xem giờ vắng khách của quán", systemImage: "chart.bar")
                        }
                    } header: {
                        Text("Thứ trong tuần áp dụng")
                    } footer: {
                        Text(thuChon.isEmpty ? "Đang áp dụng mọi ngày trong tuần." : "Chỉ áp dụng vào: \(thuChon.sorted().compactMap { tenThuTrongTuan[$0] }.joined(separator: ", "))")
                    }
                }
                if dieuKien == "DonToiThieuBac" {
                    Section {
                        ForEach($bacThangRows) { $row in
                            HStack {
                                TextField("Ngưỡng đơn", value: $row.nguong, format: .number)
                                    .keyboardType(.numberPad)
                                Text("đ →").foregroundColor(.textMuted)
                                TextField("Giảm", value: $row.giam, format: .number)
                                    .keyboardType(.numberPad)
                                Text("đ").foregroundColor(.textMuted)
                            }
                        }
                        .onDelete { bacThangRows.remove(atOffsets: $0) }
                        Button {
                            bacThangRows.append(BacThangRow(nguong: 0, giam: 0))
                        } label: {
                            Label("Thêm bậc", systemImage: "plus.circle")
                        }
                    } header: {
                        Text("Các bậc giảm giá")
                    } footer: {
                        Text("Đơn đạt ngưỡng CAO NHẤT nào thì giảm đúng số tiền của bậc đó (không cộng dồn nhiều bậc). Mốc nên cao hơn giá trị đơn trung bình hiện tại, số tiền giảm nên nhỏ hơn giá trị phần khách cần mua thêm để đạt mốc — nếu không quán lỗ dù doanh thu tăng.")
                    }
                }
                if dieuKien == "SoLuongToiThieu" {
                    Section {
                        Stepper("Từ \(soLuongToiThieu) ly trở lên", value: $soLuongToiThieu, in: 2...10)
                    } header: {
                        Text("Số lượng áp dụng")
                    } footer: {
                        Text("Chỉ áp dụng cho khách CHƯA TỪNG có đơn nào (kể cả không dùng voucher) đạt đủ số lượng này — nếu khách đã tự mua đủ ít nhất 1 lần trước đây, voucher không tạo hành vi mới nên không hiện nữa. Vì vậy mỗi khách chỉ dùng được ĐÚNG 1 LẦN trong đời.")
                    }
                }
                if dieuKien != "UpsizeMonMoi" {
                    Section {
                        Toggle("Chỉ áp dụng khi đơn có Size L", isOn: $yeuCauSizeL)
                    } footer: {
                        Text("Điều kiện phụ cộng thêm vào điều kiện trên — bắt khách phải thật sự chọn Size L mới được giảm, thay vì lấy tiền giảm mà vẫn giữ size chuẩn.")
                    }
                }
                Section("Hạng khách yêu cầu (cộng thêm vào điều kiện trên)") {
                    Picker("Hạng tối thiểu", selection: $hangToiThieu) {
                        ForEach(hangOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                }
                Section("Mục đích (chỉ để phân loại, không ảnh hưởng cách áp dụng)") {
                    Picker("Mục đích", selection: $mucDich) {
                        ForEach(mucDichOptions, id: \.0) { value, label in
                            Text(label).tag(value)
                        }
                    }
                }
                Section {
                    Toggle("Đang hoạt động (hiện cho khách)", isOn: $dangHoatDong)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm voucher" : "Sửa voucher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showGioThapDiem) {
                GioThapDiemView { batDau, ketThuc, thu in
                    gioBatDau = batDau
                    gioKetThuc = ketThuc
                    thuChon = thu
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "Đang lưu..." : "Lưu")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)
                .disabled(ma.trimmingCharacters(in: .whitespaces).isEmpty
                    || ten.trimmingCharacters(in: .whitespaces).isEmpty
                    || (dieuKien != "DonToiThieuBac" && (loaiGiam == "PhanTram" ? (phanTramGiam <= 0 || phanTramGiam > 100) : soTienGiam <= 0))
                    || (dieuKien == "DonToiThieu" && donToiThieu <= 0)
                    || (dieuKien == "DonThuN" && soDonApDung < 2)
                    || (dieuKien == "KhungGioThapDiem" && gioBatDau >= gioKetThuc)
                    || (dieuKien == "DonToiThieuBac" && BacThangRow.encode(bacThangRows) == nil)
                    || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
        }
    }

    /// 7 chip bật/tắt T2..CN — rỗng = mọi thứ (không phải "không thứ nào", tránh voucher vô nghĩa
    /// không bao giờ áp dụng được).
    private var thuChonRow: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { thu in
                let daChon = thuChon.contains(thu)
                Button {
                    if daChon { thuChon.remove(thu) } else { thuChon.insert(thu) }
                } label: {
                    Text(tenThuNganGon[thu] ?? "?")
                        .font(.caption).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(daChon ? Color.brandPrimary : Color.brandPrimary.pastelBackground())
                        .foregroundColor(daChon ? .white : .brandPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        let req = VoucherRequest(
            ma: ma.trimmingCharacters(in: .whitespaces),
            ten: ten.trimmingCharacters(in: .whitespaces),
            moTa: moTa.trimmingCharacters(in: .whitespaces).isEmpty ? nil : moTa.trimmingCharacters(in: .whitespaces),
            soTienGiam: soTienGiam,
            loaiGiam: loaiGiam,
            phanTramGiam: loaiGiam == "PhanTram" ? phanTramGiam : nil,
            giamToiDa: loaiGiam == "PhanTram" && giamToiDa > 0 ? giamToiDa : nil,
            donToiThieu: dieuKien == "DonToiThieu" ? donToiThieu : nil,
            dieuKien: dieuKien,
            soDonApDung: dieuKien == "DonThuN" ? soDonApDung : nil,
            gioBatDau: dieuKien == "KhungGioThapDiem" ? gioBatDau : nil,
            gioKetThuc: dieuKien == "KhungGioThapDiem" ? gioKetThuc : nil,
            thuTrongTuan: dieuKien == "KhungGioThapDiem" && !thuChon.isEmpty ? thuChon.sorted().map(String.init).joined(separator: ",") : nil,
            bacThang: dieuKien == "DonToiThieuBac" ? BacThangRow.encode(bacThangRows) : nil,
            soLuongToiThieu: dieuKien == "SoLuongToiThieu" ? soLuongToiThieu : nil,
            yeuCauSizeL: dieuKien != "UpsizeMonMoi" && yeuCauSizeL,
            mucDich: mucDich.isEmpty ? nil : mucDich,
            hangToiThieu: hangToiThieu.isEmpty ? nil : hangToiThieu,
            dangHoatDong: dangHoatDong)
        let result: ActionResult
        if let existing {
            result = await APIClient.shared.updateVoucher(id: existing.id, req)
        } else {
            result = await APIClient.shared.createVoucher(req)
        }
        saving = false
        if result.success {
            onSaved()
            dismiss()
        } else {
            errorMessage = result.message ?? "Không lưu được."
        }
    }
}
