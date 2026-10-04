import SwiftUI

/// Công việc nội bộ — GET/PUT /api/CongViecNoiBo. Chỉ tick hoàn thành, không thêm/xoá/cảnh báo
/// (NgayCanhBao, XNgayCanhBao) — đơn giản hoá cho bản mobile. Không có footer, khớp màn Ảnh menu.
struct CongViecListView: View {
    let notificationBell: AnyView
    @State private var items: [CongViecNoiBoDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var adding = false
    @State private var errorMessage: String?
    /// Tải riêng sau danh sách việc — AI trả chậm, không chặn màn hình.
    @State private var deXuat: [CongViecDeXuatDto] = []
    /// Việc đang chờ xác nhận đổi trạng thái — bấm vào dòng KHÔNG đổi ngay, phải xác nhận trước
    /// (theo yêu cầu, tránh chạm nhầm khi lướt danh sách làm mất trạng thái tick đã có).
    @State private var confirmItem: CongViecNoiBoDto?
    @State private var confirmNewState = false

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
                    List {
                        if searchText.isEmpty && !deXuat.isEmpty {
                            Section("Đề xuất nên làm") {
                                ForEach(deXuat) { deXuatRow($0) }
                            }
                        }
                        if sortedItems.isEmpty {
                            if items.isEmpty {
                                Text("Chưa có việc nào")
                                    .foregroundColor(.textMuted)
                                    .frame(maxWidth: .infinity)
                                    .listRowSeparator(.hidden)
                            } else {
                                // Gõ tên không khớp việc nào có sẵn — cho thêm mới ngay bằng chính
                                // chuỗi đang tìm, khớp pattern "Thêm nguyên liệu mới" bên tab Chi tiêu
                                // (AddExpenseSheet), thay cho nút "+" ở toolbar trước đây.
                                let ten = searchText.trimmingCharacters(in: .whitespaces)
                                if !ten.isEmpty {
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
                        } else {
                            ForEach(sortedItems) { item in
                                CongViecRowView(item: item) { toggled in
                                    confirmItem = item
                                    confirmNewState = toggled
                                }
                            }
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
            .alert("Thêm việc thất bại", isPresented: Binding(
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

    private func load() async {
        loading = true
        items = await APIClient.shared.getCongViecList()
        loading = false
        hasLoaded = true
        CongViecBadge.shared.pendingCount = items.filter { !$0.daHoanThanh }.count
        deXuat = await APIClient.shared.getCongViecDeXuat()
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
        _ = await APIClient.shared.updateCongViec(id: item.id, ten: item.ten, daHoanThanh: done, ngayGio: item.ngayGio)
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
