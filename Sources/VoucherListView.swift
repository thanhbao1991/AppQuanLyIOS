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
            loaiGiam: item.loaiGiam, phanTramGiam: item.phanTramGiam, donToiThieu: item.donToiThieu,
            dieuKien: item.dieuKien, dangHoatDong: !item.dangHoatDong))
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
                    Text(nhanUuDai(item)).font(.caption).fontWeight(.bold).foregroundColor(.dangerColor)
                }
                if let moTa = item.moTa, !moTa.isEmpty {
                    Text(moTa).font(.caption).foregroundColor(.textMuted).lineLimit(2)
                }
                Text(nhanDieuKien(item.dieuKien)).font(.caption2).foregroundColor(.brandPrimary)
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

    private func nhanDieuKien(_ dieuKien: String) -> String {
        switch dieuKien {
        case "DonDauTien": return "Điều kiện: đơn app đầu tiên của khách"
        case "SinhNhat": return "Điều kiện: trong tháng sinh nhật, 1 lần/năm"
        case "DonToiThieu": return "Điều kiện: đơn tối thiểu, không giới hạn số lần"
        default: return "Điều kiện: \(dieuKien)"
        }
    }

    private func nhanUuDai(_ item: VoucherDto) -> String {
        if item.loaiGiam == "PhanTram" {
            return "-\(Int(item.phanTramGiam ?? 0))%"
        }
        return "-\(Int(item.soTienGiam).formatted())đ"
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
    @State private var donToiThieu: Double
    @State private var dieuKien: String
    @State private var dangHoatDong: Bool
    @State private var saving = false
    @State private var errorMessage: String?

    // Khớp VoucherDieuKien bên Backend — thêm điều kiện mới thì thêm 1 dòng ở đây.
    private let dieuKienOptions = [
        ("DonDauTien", "Đơn app đầu tiên"),
        ("SinhNhat", "Sinh nhật (1 lần/năm)"),
        ("DonToiThieu", "Đơn tối thiểu (không giới hạn)"),
    ]
    // Khớp VoucherLoaiGiam bên Backend.
    private let loaiGiamOptions = [
        ("SoTien", "Giảm số tiền cố định"),
        ("PhanTram", "Giảm theo %"),
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
        _donToiThieu = State(initialValue: existing?.donToiThieu ?? 100000)
        _dieuKien = State(initialValue: existing?.dieuKien ?? "DonDauTien")
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
                } else {
                    Section("Số tiền giảm") {
                        HStack {
                            TextField("0", value: $soTienGiam, format: .number)
                                .keyboardType(.numberPad)
                            Text("đ").foregroundColor(.textMuted)
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
                    || (loaiGiam == "PhanTram" ? (phanTramGiam <= 0 || phanTramGiam > 100) : soTienGiam <= 0)
                    || (dieuKien == "DonToiThieu" && donToiThieu <= 0)
                    || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
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
            donToiThieu: dieuKien == "DonToiThieu" ? donToiThieu : nil,
            dieuKien: dieuKien,
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
