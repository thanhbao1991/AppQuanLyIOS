import SwiftUI

/// Công việc nội bộ — GET/POST/PUT /api/CongViecNoiBo. Tick hoàn thành + thêm việc mới từ ô tìm
/// kiếm; không xoá/cảnh báo (NgayCanhBao, XNgayCanhBao) — đơn giản hoá cho bản mobile. Không có
/// footer, khớp màn Ảnh menu.
struct CongViecListView: View {
    let notificationBell: AnyView
    @State private var items: [CongViecNoiBoDto] = []
    @State private var hasLoaded = false
    /// Lượt tải gần nhất lỗi — hiện banner "Thử lại", giữ danh sách + badge đang có.
    @State private var loadFailed = false
    /// Lượt tải đề xuất mới nhất — đề xuất tải riêng (chậm), lượt cũ về sau không được ghi đè.
    @State private var deXuatGeneration = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var adding = false
    @State private var errorMessage: String?
    /// Tải riêng sau danh sách việc — AI trả chậm, không chặn màn hình.
    @State private var deXuat: [CongViecDeXuatDto] = []
    /// Việc đang chờ xác nhận đổi trạng thái — bấm vào dòng KHÔNG đổi ngay, phải xác nhận trước
    /// (theo yêu cầu, tránh chạm nhầm khi lướt danh sách làm mất trạng thái tick đã có).
    @State private var confirmItem: CongViecNoiBoDto?
    @State private var confirmNewState = false

    /// Chỉ đề xuất việc CHƯA làm theo `items` hiện tại — đề xuất tải chậm hơn danh sách, không lọc
    /// thì việc vừa tick xong vẫn nằm trong "Đề xuất nên làm" cho tới khi lượt đề xuất mới về.
    private var visibleDeXuat: [CongViecDeXuatDto] {
        deXuat.filter { d in items.contains { $0.id == d.congViecId && !$0.daHoanThanh } }
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
                        if searchText.isEmpty && !visibleDeXuat.isEmpty {
                            Section("Đề xuất nên làm") {
                                ForEach(visibleDeXuat) { deXuatRow($0) }
                            }
                        }
                        if items.isEmpty && searchText.isEmpty {
                            Text("Chưa có việc nào — gõ tên vào ô tìm để thêm")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(sortedItems) { item in
                            CongViecRowView(item: item) { toggled in
                                confirmItem = item
                                confirmNewState = toggled
                            }
                        }
                        // Thêm mới ngay bằng chính chuỗi đang tìm (khớp pattern "Thêm nguyên liệu mới"
                        // bên tab Chi tiêu) — luôn ở cuối kết quả, miễn chưa có việc trùng khít tên.
                        if let ten = tenViecMoi {
                            Button {
                                Task { await addCongViec(ten: ten) }
                            } label: {
                                if adding {
                                    ProgressView()
                                } else {
                                    EmojiLabel("Thêm việc mới \"\(ten)\"", "➕")
                                }
                            }
                            .disabled(adding)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .softScrollEdgeTop()
                    .padding(.top, 4)
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

        // Đề xuất tải RIÊNG, không chặn load() — trước đây kéo refresh/tick xong phải chờ cả phần
        // AI chậm này mới hết vòng quay.
        deXuatGeneration += 1
        let generation = deXuatGeneration
        Task {
            let moi = await APIClient.shared.getCongViecDeXuat()
            if generation == deXuatGeneration { deXuat = moi }
        }
    }

    /// Chỉ hiện tên — bấm vào mở đúng confirm đổi trạng thái của công việc tương ứng (tìm trong
    /// `items` theo congViecId), y hệt bấm dòng công việc thường.
    private func deXuatRow(_ d: CongViecDeXuatDto) -> some View {
        Button {
            guard let item = items.first(where: { $0.id == d.congViecId }) else { return }
            confirmItem = item
            confirmNewState = !item.daHoanThanh
        } label: {
            Text(d.ten)
                .font(.subheadline.bold())
                .foregroundColor(.primary)
        }
        .padding(.vertical, 2)
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
                    .foregroundColor(item.daHoanThanh ? .successColor : .textMuted)
                    .font(.title3)
                Text(item.ten)
                    .strikethrough(item.daHoanThanh)
                    .foregroundColor(item.daHoanThanh ? .textMuted : .primary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
