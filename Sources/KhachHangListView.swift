import Foundation
import SwiftUI

/// Quản trị Khách hàng (Menu > Khách hàng) — thêm/sửa/xoá, gộp khách trùng, xem Ví/lịch sử mua
/// hàng, thay cho phải mở Desktop (KhachHangWindow + KhachHangLichSuWindow). GET/POST/PUT/DELETE
/// /api/KhachHang (Create/Update tái dùng APIClient.createKhachHang/updateKhachHang đã có sẵn cho
/// flow sửa khách trong HoaDonCreateFormView).
struct KhachHangListView: View {
    @State private var items: [KhachHangDto] = []
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editing: KhachHangDto?
    @State private var viTienFor: KhachHangDto?
    @State private var lichSuFor: KhachHangDto?

    @State private var isMergeMode = false
    @State private var mergeSelection: [KhachHangDto] = []
    @State private var showMergeReview = false

    private var filteredItems: [KhachHangDto] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            anyMatchesSearch(searchText, $0.ten,
                              $0.phones.map(\.soDienThoai).joined(separator: " "),
                              $0.addresses.map(\.diaChi).joined(separator: " "))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm khách theo tên/SĐT...")

            if isMergeMode {
                mergeBanner
            }

            if !hasLoaded {
                fullScreenLoading()
            } else {
                List {
                    ForEach(filteredItems) { item in
                        KhachHangRowView(
                            item: item,
                            isMergeMode: isMergeMode,
                            isSelected: mergeSelection.contains(where: { $0.id == item.id }),
                            onTap: { handleRowTap(item) },
                            onDelete: { Task { await delete(item) } },
                            onViTien: { viTienFor = item },
                            onLichSu: { lichSuFor = item }
                        )
                    }
                }
                .listStyle(.plain)
                .softScrollEdgeTop()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Khách hàng")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        isMergeMode.toggle()
                        mergeSelection = []
                    } label: {
                        Image(systemName: isMergeMode ? "person.2.slash" : "person.2")
                    }
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .disabled(isMergeMode)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            KhachHangEditSheet(existing: nil) { Task { await load() } }
        }
        .sheet(item: $editing) { item in
            KhachHangEditSheet(existing: item) { Task { await load() } }
        }
        .sheet(item: $viTienFor) { item in
            ViTienHistoryView(khach: item)
        }
        .sheet(item: $lichSuFor) { item in
            KhachHangLichSuView(khach: item)
        }
        .sheet(isPresented: $showMergeReview) {
            MergeReviewSheet(selection: mergeSelection) {
                isMergeMode = false
                mergeSelection = []
                Task { await load() }
            }
        }
    }

    private var mergeBanner: some View {
        HStack {
            Text(mergeSelection.isEmpty ? "Chọn ít nhất 2 khách để gộp" : "Đã chọn \(mergeSelection.count) khách")
                .font(.caption).foregroundColor(.textMuted)
            Spacer()
            Button("Tiếp tục") { showMergeReview = true }
                .font(.caption).fontWeight(.bold)
                .disabled(mergeSelection.count < 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.brandPrimary.pastelBackground(0.9))
    }

    private func handleRowTap(_ item: KhachHangDto) {
        if isMergeMode {
            if let idx = mergeSelection.firstIndex(where: { $0.id == item.id }) {
                mergeSelection.remove(at: idx)
            } else {
                mergeSelection.append(item)
            }
        } else {
            editing = item
        }
    }

    private func load() async {
        items = await APIClient.shared.getAllKhachHang()
        hasLoaded = true
    }

    private func delete(_ item: KhachHangDto) async {
        _ = await APIClient.shared.deleteKhachHang(id: item.id)
        await load()
    }
}

private struct KhachHangRowView: View {
    let item: KhachHangDto
    let isMergeMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    let onViTien: () -> Void
    let onLichSu: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Vùng bấm để chọn/sửa KHÔNG được lồng Menu bên trong (SwiftUI không cho 2 control
            // tương tác lồng nhau đáng tin cậy) — Menu "..." đặt làm sibling ở ngoài Button này.
            Button(action: onTap) {
                HStack(spacing: 10) {
                    if isMergeMode {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .brandPrimary : .textMuted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.ten)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.primary)
                        if !item.phones.isEmpty {
                            Text(item.phones.map(\.soDienThoai).joined(separator: ", "))
                                .font(.caption).foregroundColor(.textMuted)
                        }
                        if !item.addresses.isEmpty {
                            Text(item.addresses.map(\.diaChi).joined(separator: " | "))
                                .font(.caption2).foregroundColor(.textMuted)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if item.soDu > 0 {
                        Text(HoaDonFormatting.money(item.soDu))
                            .font(.caption2).fontWeight(.bold)
                            .foregroundColor(.brandPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isMergeMode {
                Menu {
                    Button { onViTien() } label: { Label("Ví tiền", systemImage: "wallet.pass") }
                    Button { onLichSu() } label: { Label("Lịch sử mua hàng", systemImage: "clock.arrow.circlepath") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.textMuted)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isSelected ? Color.brandPrimary : Color.brandPrimary).pastelBackground(isSelected ? 0.75 : 0.9))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            if !isMergeMode {
                Button(role: .destructive, action: onDelete) {
                    EmojiLabel("Xoá", "🗑️")
                }
            }
        }
    }
}

// MARK: - Thêm / sửa

private struct EditContactRow: Identifiable {
    let id: String
    var value: String
    var isDefault: Bool = false
}

/// Ép dòng đầu làm mặc định nếu chưa dòng nào được chọn (server chưa đánh dấu, hoặc vừa xoá dòng
/// đang là mặc định) — thay quy tắc ngầm cũ "dòng đầu luôn là mặc định".
private func ensureSingleDefaultRow(_ rows: inout [EditContactRow]) {
    guard !rows.isEmpty, !rows.contains(where: { $0.isDefault }) else { return }
    rows[0].isDefault = true
}

/// Nút ⭐ đầu mỗi dòng SĐT/địa chỉ để chọn tay dòng nào là mặc định.
private struct ContactRowEditor: View {
    @Binding var rows: [EditContactRow]
    let placeholder: String
    let keyboard: UIKeyboardType
    let allowEmpty: Bool

    var body: some View {
        ForEach($rows) { $row in
            HStack {
                Button {
                    for j in rows.indices { rows[j].isDefault = (rows[j].id == row.id) }
                } label: {
                    Image(systemName: row.isDefault ? "star.fill" : "star")
                        .foregroundColor(row.isDefault ? .brandPrimary : .textMuted)
                }
                .buttonStyle(.plain)

                TextField(placeholder, text: $row.value)
                    .keyboardType(keyboard)

                if allowEmpty || rows.count > 1 {
                    Button {
                        let wasDefault = row.isDefault
                        rows.removeAll { $0.id == row.id }
                        if wasDefault, !rows.isEmpty { rows[0].isDefault = true }
                    } label: {
                        Image(systemName: "trash").foregroundColor(.dangerColor)
                    }
                }
            }
        }
    }
}

private struct KhachHangEditSheet: View {
    let existing: KhachHangDto?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten: String
    @State private var phoneRows: [EditContactRow]
    @State private var addressRows: [EditContactRow]
    @State private var saving = false
    @State private var errorMessage: String?

    init(existing: KhachHangDto?, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _ten = State(initialValue: existing?.ten ?? "")
        var phones = existing?.phones.map { EditContactRow(id: $0.id, value: $0.soDienThoai, isDefault: $0.isDefault) } ?? [EditContactRow(id: UUID().uuidString, value: "", isDefault: true)]
        var addresses = existing?.addresses.map { EditContactRow(id: $0.id, value: $0.diaChi, isDefault: $0.isDefault) } ?? []
        ensureSingleDefaultRow(&phones)
        ensureSingleDefaultRow(&addresses)
        _phoneRows = State(initialValue: phones)
        _addressRows = State(initialValue: addresses)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Thông tin") {
                    TextField("Tên khách hàng", text: $ten)
                }

                Section("Số điện thoại") {
                    ContactRowEditor(rows: $phoneRows, placeholder: "Số điện thoại", keyboard: .phonePad, allowEmpty: false)
                    Button {
                        phoneRows.append(EditContactRow(id: UUID().uuidString, value: "", isDefault: phoneRows.isEmpty))
                    } label: {
                        EmojiLabel("Thêm SĐT", "➕")
                    }
                }

                Section("Địa chỉ") {
                    ContactRowEditor(rows: $addressRows, placeholder: "Địa chỉ", keyboard: .default, allowEmpty: true)
                    Button {
                        addressRows.append(EditContactRow(id: UUID().uuidString, value: "", isDefault: addressRows.isEmpty))
                    } label: {
                        EmojiLabel("Thêm địa chỉ", "➕")
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(existing == nil ? "Thêm khách hàng" : "Sửa khách hàng")
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
                .disabled(ten.trimmingCharacters(in: .whitespaces).isEmpty || saving)
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

        let tenMoi = ten.trimmingCharacters(in: .whitespaces)
        var keptPhones = phoneRows.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        var keptAddresses = addressRows.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
        ensureSingleDefaultRow(&keptPhones)
        ensureSingleDefaultRow(&keptAddresses)
        let phones = keptPhones.map { KhachHangPhoneDto(id: $0.id, soDienThoai: $0.value.trimmingCharacters(in: .whitespaces), isDefault: $0.isDefault) }
        let addresses = keptAddresses.map { KhachHangAddressDto(id: $0.id, diaChi: $0.value.trimmingCharacters(in: .whitespaces), isDefault: $0.isDefault) }

        if let existing {
            // duocNhanVoucher KHÔNG có UI chỉnh ở đây — giữ nguyên giá trị hiện tại, khớp Desktop
            // (SaveEditAsync cũng chỉ giữ nguyên, không cho sửa). Cờ này do rollout app kiểm soát
            // (bật hàng loạt khi publish App Store), không phải nhân viên tự bật/tắt từng khách.
            let payload = KhachHangDto(
                id: existing.id, ten: tenMoi, soDu: existing.soDu, duocNhanVoucher: existing.duocNhanVoucher,
                phones: phones, addresses: addresses, facebookThreadId: existing.facebookThreadId
            )
            let result = await APIClient.shared.updateKhachHang(payload)
            saving = false
            if result.success {
                onSaved(); dismiss()
            } else {
                errorMessage = result.message ?? "Lưu thất bại."
            }
        } else {
            let body = KhachHangCreateRequest(ten: tenMoi, duocNhanVoucher: false, phones: phones, addresses: addresses)
            let result = await APIClient.shared.createKhachHang(body)
            saving = false
            if result.success {
                onSaved(); dismiss()
            } else {
                errorMessage = result.message ?? "Lưu thất bại."
            }
        }
    }
}

// MARK: - Ví tiền (chỉ đọc)

private struct ViTienHistoryView: View {
    let khach: KhachHangDto
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ViGiaoDichDto] = []
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    fullScreenLoading()
                } else if items.isEmpty {
                    ContentUnavailableViewCompat(title: "Chưa có giao dịch ví", systemImage: "wallet.pass")
                } else {
                    List(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.tenLoai).font(.subheadline).fontWeight(.semibold)
                                Spacer()
                                Text((item.soTienThayDoi >= 0 ? "+" : "") + HoaDonFormatting.money(item.soTienThayDoi))
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(item.soTienThayDoi >= 0 ? .brandPrimary : .dangerColor)
                            }
                            Text("\(HoaDonFormatting.money(item.soDuTruoc)) → \(HoaDonFormatting.money(item.soDuSau))")
                                .font(.caption2).foregroundColor(.textMuted)
                            HStack {
                                Text(HoaDonFormatting.congNoTime(item.thoiGian)).font(.caption2).foregroundColor(.textMuted)
                                if let ghiChu = item.ghiChu, !ghiChu.isEmpty {
                                    Text(ghiChu).font(.caption2).foregroundColor(.textMuted)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .softScrollEdgeTop()
                }
            }
            .navigationTitle("Ví — \(khach.ten)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task {
                items = await APIClient.shared.getViGiaoDich(khachHangId: khach.id)
                hasLoaded = true
            }
        }
    }
}

// MARK: - Lịch sử mua hàng

private struct KhachHangLichSuView: View {
    let khach: KhachHangDto
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0 // 0 = tháng này, 1 = tháng trước, 2 = tất cả
    @State private var items: [KhachHangLichSuItemDto] = []
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Tháng này").tag(0)
                    Text("Tháng trước").tag(1)
                    Text("Tất cả").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(12)
                .onChange(of: tab) { _ in Task { await load() } }

                if !hasLoaded {
                    fullScreenLoading()
                } else if items.isEmpty {
                    ContentUnavailableViewCompat(title: "Chưa có lịch sử mua hàng", systemImage: "clock.arrow.circlepath")
                } else {
                    List(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text([item.tenSanPham, item.tenBienThe].filter { !$0.isEmpty }.joined(separator: "  "))
                                    .font(.subheadline).fontWeight(.semibold)
                                Spacer()
                                Text(HoaDonFormatting.money(item.thanhTien))
                                    .font(.subheadline).fontWeight(.bold)
                                    .foregroundColor(.brandPrimary)
                            }
                            HStack {
                                Text("SL \(Int(item.soLuong)) × \(HoaDonFormatting.money(item.donGia))")
                                    .font(.caption2).foregroundColor(.textMuted)
                                Spacer()
                                Text(HoaDonFormatting.congNoTime(item.ngayGio)).font(.caption2).foregroundColor(.textMuted)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .softScrollEdgeTop()
                }
            }
            .navigationTitle("Lịch sử — \(khach.ten)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        hasLoaded = false
        let now = Date()
        let cal = Calendar.current
        var nam = 0, thang = 0
        if tab == 0 {
            nam = cal.component(.year, from: now); thang = cal.component(.month, from: now)
        } else if tab == 1 {
            let prev = cal.date(byAdding: .month, value: -1, to: now) ?? now
            nam = cal.component(.year, from: prev); thang = cal.component(.month, from: prev)
        }
        items = await APIClient.shared.getKhachHangLichSu(khachHangId: khach.id, nam: nam, thang: thang)
        hasLoaded = true
    }
}

/// iOS 17 có `ContentUnavailableView` sẵn — viết tay bản tối giản để tương thích iOS 16.
private struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.largeTitle).foregroundColor(.textMuted)
            Text(title).font(.subheadline).foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Gộp khách

private struct MergeReviewSheet: View {
    let selection: [KhachHangDto]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ten: String
    @State private var phoneRows: [EditContactRow]
    @State private var addressRows: [EditContactRow]
    @State private var errorMessage: String?
    @State private var saving = false
    @State private var showConfirm = false
    @State private var countdown = 5
    @State private var countdownTimer: Timer?

    init(selection: [KhachHangDto], onDone: @escaping () -> Void) {
        self.selection = selection
        self.onDone = onDone
        let first = selection.first
        let others = selection.dropFirst()
        _ten = State(initialValue: [first?.ten].compactMap { $0 }.joined() + (others.isEmpty ? "" : " (\(others.map(\.ten).joined(separator: ", ")))"))
        _phoneRows = State(initialValue: MergeReviewSheet.unionValues(selection.flatMap { $0.phones.map(\.soDienThoai) }).map { EditContactRow(id: UUID().uuidString, value: $0) })
        _addressRows = State(initialValue: MergeReviewSheet.unionValues(selection.flatMap { $0.addresses.map(\.diaChi) }).map { EditContactRow(id: UUID().uuidString, value: $0) })
    }

    private static func unionValues(_ items: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for v in items {
            let t = v.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            result.append(t)
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Gộp \(selection.count) khách làm 1 — khách đầu (\(selection.first?.ten ?? "")) được GIỮ LẠI, các khách còn lại sẽ bị XOÁ. Thao tác KHÔNG THỂ HOÀN TÁC.")
                        .font(.caption).foregroundColor(.dangerColor)
                }

                Section("Tên sau khi gộp") {
                    TextField("Tên", text: $ten)
                }

                Section("Số điện thoại") {
                    ForEach($phoneRows) { $row in
                        HStack {
                            TextField("SĐT", text: $row.value)
                            Button { phoneRows.removeAll { $0.id == row.id } } label: {
                                Image(systemName: "trash").foregroundColor(.dangerColor)
                            }
                        }
                    }
                }

                Section("Địa chỉ") {
                    ForEach($addressRows) { $row in
                        HStack {
                            TextField("Địa chỉ", text: $row.value)
                            Button { addressRows.removeAll { $0.id == row.id } } label: {
                                Image(systemName: "trash").foregroundColor(.dangerColor)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle("Gộp khách hàng")
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
                    startCountdown()
                } label: {
                    Text("Gộp khách")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.dangerColor)
                .controlSize(.large)
                .disabled(ten.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
            .popupHost { host in
                host.alert("Xác nhận gộp khách", isPresented: $showConfirm) {
                    Button("Huỷ", role: .cancel) { countdownTimer?.invalidate() }
                    Button(countdown > 0 ? "Gộp sau \(countdown)s..." : "Gộp ngay", role: .destructive) {
                        if countdown <= 0 { Task { await doMerge() } }
                    }
                    .disabled(countdown > 0)
                } message: {
                    Text("Thao tác KHÔNG THỂ HOÀN TÁC. Kiểm tra lại thông tin trước khi tiếp tục.")
                }
            }
        }
    }

    private func startCountdown() {
        countdown = 5
        showConfirm = true
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            DispatchQueue.main.async {
                if countdown > 0 { countdown -= 1 }
                if countdown <= 0 { timer.invalidate() }
            }
        }
    }

    private func doMerge() async {
        guard let keep = selection.first else { return }
        saving = true
        errorMessage = nil

        let body = MergeKhachHangRequest(
            keepId: keep.id,
            mergeIds: selection.dropFirst().map(\.id),
            ten: ten.trimmingCharacters(in: .whitespaces),
            soDienThoais: phoneRows.map(\.value).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            diaChis: addressRows.map(\.value).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        )
        let result = await APIClient.shared.mergeKhachHang(body)
        saving = false
        if result.success {
            onDone(); dismiss()
        } else {
            errorMessage = result.message ?? "Gộp khách thất bại."
        }
    }
}
