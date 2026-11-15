import SwiftUI

/// Công việc nội bộ — GET/POST/PUT /api/CongViecNoiBo. Tick hoàn thành + thêm việc mới từ ô tìm
/// kiếm. Mục đầu "Cảnh báo hư hỏng" (15/11/2026, thay "Đề xuất nên làm"): việc đã xong có đặt số ngày
/// cảnh báo (XNgayCanhBao) — server tính NgayCanhBao = lúc tick xong + X ngày. Đặt số ngày bằng giữ
/// lâu dòng việc. Không có footer, khớp màn Ảnh menu.
struct CongViecListView: View {
    let notificationBell: AnyView
    @State private var items: [CongViecNoiBoDto] = []
    @State private var hasLoaded = false
    /// Lượt tải gần nhất lỗi — hiện banner "Thử lại", giữ danh sách + badge đang có.
    @State private var loadFailed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var adding = false
    @State private var errorMessage: String?
    /// Việc đang chờ xác nhận đổi trạng thái — bấm vào dòng KHÔNG đổi ngay, phải xác nhận trước
    /// (theo yêu cầu, tránh chạm nhầm khi lướt danh sách làm mất trạng thái tick đã có).
    @State private var confirmItem: CongViecNoiBoDto?
    @State private var confirmNewState = false

    /// Việc đang đặt số ngày cảnh báo (alert nhập số).
    @State private var editDaysItem: CongViecNoiBoDto?
    @State private var editDaysText = ""

    /// Việc đã xong có ngày hư, hư sớm nhất lên đầu.
    private var canhBaoHuHong: [CanhBaoHuHong] {
        items.compactMap { item in
            guard item.daHoanThanh, let d = HoaDonFormatting.parseIso(item.ngayCanhBao) else { return nil }
            return CanhBaoHuHong(item: item, ngayHu: d)
        }
        .sorted { $0.ngayHu < $1.ngayHu }
    }

    /// Tên việc mới lấy từ ô tìm — nil khi ô trống hoặc đã có việc TRÙNG KHÍT tên (không phân biệt
    /// hoa/thường). Trước đây nút thêm chỉ hiện khi tìm không ra gì VÀ danh sách đã có việc: không
    /// thêm được việc đầu tiên, cũng không thêm được "Lau" khi đã có "Lau bàn".
    private var tenViecMoi: String? {
        let ten = searchText.trimmingCharacters(in: .whitespaces)
        guard !ten.isEmpty else { return nil }
        let trung = items.contains { $0.ten.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(ten) == .orderedSame }
        return trung ? nil : ten
    }

    private var sortedItems: [CongViecNoiBoDto] {
        items
            .filter { $0.ten.matchesSearch(searchText) }
            .sorted { !$0.daHoanThanh && $1.daHoanThanh }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm việc...", trailing: AnyView(notificationBell), tinted: true)

                if !hasLoaded {
                    fullScreenLoading()
                } else {
                    if loadFailed {
                        ThongKeLoadErrorBanner(text: "Chưa tải được danh sách việc") { Task { await load() } }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                    }
                    List {
                        if searchText.isEmpty && !canhBaoHuHong.isEmpty {
                            Section {
                                ForEach(canhBaoHuHong) { canhBaoRow($0.item, ngayHu: $0.ngayHu) }
                            } header: {
                                sectionHeader("Cảnh báo hư hỏng", nil)
                            }
                        }
                        if items.isEmpty && searchText.isEmpty {
                            Text("Chưa có việc nào — gõ tên vào ô tìm để thêm")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        }
                        // 02/11/2026: chia "Cần làm" / "Đã xong" trong khung bo góc (insetGrouped) trên nền xám — cùng
                        // tông các tab thẻ khác, vẫn là checklist kiểu Lời nhắc.
                        let canLam = sortedItems.filter { !$0.daHoanThanh }
                        let daXong = sortedItems.filter { $0.daHoanThanh }
                        if !canLam.isEmpty || tenViecMoi != nil {
                            Section {
                                ForEach(canLam) { congViecRow($0) }
                                // Thêm mới ngay bằng chính chuỗi đang tìm (khớp pattern "Thêm nguyên liệu mới"
                                // bên tab Chi tiêu) — luôn ở cuối, miễn chưa có việc trùng khít tên.
                                if let ten = tenViecMoi {
                                    Button {
                                        Task { await addCongViec(ten: ten) }
                                    } label: {
                                        if adding {
                                            ProgressView()
                                        } else {
                                            IconLabel("Thêm việc mới \"\(ten)\"", AppIcon.them)
                                        }
                                    }
                                    .disabled(adding)
                                }
                            } header: {
                                sectionHeader("Cần làm", canLam.count)
                            }
                        }
                        if !daXong.isEmpty {
                            Section {
                                ForEach(daXong) { congViecRow($0) }
                            } header: {
                                sectionHeader("Đã xong", daXong.count)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .softScrollEdgeTop()
                    .refreshable { await load() }
                }
            }
            .navigationBarHidden(true)
            .task { await load() }
            // Backend không bắn EntityChanged cho CongViecNoiBo — mở lại app thì tự tải lại để thấy
            // việc máy khác đã tick (chuyển tab đã tự tải sẵn vì view được dựng lại).
            .onChange(of: scenePhase) { phase in
                if phase == .active, hasLoaded { Task { await load() } }
            }
            .popupHost { host in
            host
            .alert("Không thực hiện được", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Số ngày cảnh báo", isPresented: Binding(
                get: { editDaysItem != nil },
                set: { if !$0 { editDaysItem = nil } }
            )) {
                TextField("Số ngày (0 = tắt)", text: $editDaysText)
                    .keyboardType(.numberPad)
                Button("Lưu") {
                    if let item = editDaysItem, let soNgay = Int(editDaysText.trimmingCharacters(in: .whitespaces)), soNgay >= 0 {
                        Task { await saveSoNgay(item, soNgay: soNgay) }
                    }
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("\(editDaysItem?.ten ?? ""): báo hư sau bao nhiêu ngày kể từ lúc làm xong")
            }
            .confirmationDialog(
                confirmNewState ? "Đánh dấu đã làm?" : "Đánh dấu chưa làm?",
                isPresented: Binding(get: { confirmItem != nil }, set: { if !$0 { confirmItem = nil } }),
                titleVisibility: .visible
            ) {
                Button(confirmNewState ? "Đã làm" : "Chưa làm") {
                    if let confirmItem {
                        Task { await toggle(confirmItem, done: confirmNewState) }
                    }
                }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text(confirmItem?.ten ?? "")
            }
            }
        }
    }

    private func load() async {
        let fresh = await APIClient.shared.getCongViecList()
        if let fresh {
            items = fresh
            CongViecBadge.shared.pendingCount = fresh.filter { !$0.daHoanThanh }.count
        }
        loadFailed = fresh == nil
        hasLoaded = true
    }

    private func congViecRow(_ item: CongViecNoiBoDto) -> some View {
        CongViecRowView(item: item) { toggled in
            confirmItem = item
            confirmNewState = toggled
        }
        .contextMenu { soNgayButton(item) }
    }

    private func soNgayButton(_ item: CongViecNoiBoDto) -> some View {
        Button {
            editDaysText = (item.xNgayCanhBao ?? 0) > 0 ? "\(item.xNgayCanhBao!)" : ""
            editDaysItem = item
        } label: {
            Label("Số ngày cảnh báo hư", systemImage: "exclamationmark.triangle")
        }
    }

    private func sectionHeader(_ ten: String, _ soLuong: Int?) -> some View {
        HStack(spacing: 6) {
            Text(ten)
            if let soLuong { Text("\(soLuong)").foregroundColor(.textMuted) }
        }
        .font(.footnote.weight(.semibold))
        .textCase(nil)
    }

    /// Bấm vào = confirm "chưa làm" (mở lại để làm mẻ mới), y hệt bấm dòng việc thường.
    private func canhBaoRow(_ item: CongViecNoiBoDto, ngayHu: Date) -> some View {
        let cal = Calendar.current
        let soNgay = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: ngayHu)).day ?? 0
        let (chu, mau): (String, Color) = soNgay < 0 ? ("Hư \(-soNgay) ngày", .red)
            : soNgay == 0 ? ("Hư hôm nay", .red)
            : soNgay == 1 ? ("Còn 1 ngày", .orange)
            : ("Còn \(soNgay) ngày", .textMuted)
        return Button {
            confirmItem = item
            confirmNewState = false
        } label: {
            HStack {
                Text(item.ten)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                Spacer()
                Text(chu)
                    .font(.subheadline.weight(soNgay <= 1 ? .semibold : .regular))
                    .foregroundColor(mau)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { soNgayButton(item) }
    }

    private func saveSoNgay(_ item: CongViecNoiBoDto, soNgay: Int) async {
        let result = await APIClient.shared.updateCongViec(
            id: item.id, ten: item.ten, daHoanThanh: item.daHoanThanh, ngayGio: item.ngayGio, xNgayCanhBao: soNgay)
        if !result.success {
            errorMessage = "Chưa lưu được số ngày \"\(item.ten)\": \(result.message ?? "lỗi không rõ")"
        }
        await load()
    }

    private func toggle(_ item: CongViecNoiBoDto, done: Bool) async {
        let result = await APIClient.shared.updateCongViec(id: item.id, ten: item.ten, daHoanThanh: done, ngayGio: item.ngayGio)
        if !result.success {
            errorMessage = "Chưa đổi được trạng thái \"\(item.ten)\": \(result.message ?? "lỗi không rõ")"
        }
        await load()
    }

    /// Thêm việc mới ngay từ ô tìm kiếm khi gõ tên chưa có việc nào khớp — khớp pattern "Thêm nguyên
    /// liệu mới" bên tab Chi tiêu, thay cho sheet/nút "+" riêng ở toolbar trước đây.
    private func addCongViec(ten: String) async {
        adding = true
        errorMessage = nil
        let result = await APIClient.shared.createCongViec(ten: ten)
        adding = false
        if result.success {
            searchText = ""
            await load()
        } else {
            errorMessage = result.message ?? "Không thêm được công việc."
        }
    }
}

private struct CanhBaoHuHong: Identifiable {
    let item: CongViecNoiBoDto
    let ngayHu: Date
    var id: String { item.id }
}

/// Dòng phẳng, không còn kiểu "card" (nền màu/bo góc/shadow) — khớp style SanPhamHinhAnhRow (màn
/// Ảnh menu): chỉ HStack + padding dọc, dùng separator mặc định của List thay vì tự vẽ khung.
private struct CongViecRowView: View {
    let item: CongViecNoiBoDto
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!item.daHoanThanh)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.daHoanThanh ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.daHoanThanh ? .brandPrimary : .textMuted)
                    .font(.title3)
                Text(item.ten)
                    .strikethrough(item.daHoanThanh)
                    .foregroundColor(item.daHoanThanh ? .textMuted : .primary)
                Spacer()
                if let x = item.xNgayCanhBao, x > 0 {
                    Text("\(x) ngày")
                        .font(.caption)
                        .foregroundColor(.textMuted)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
