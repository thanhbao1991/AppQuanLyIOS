import SwiftUI

/// Công việc nội bộ — GET/PUT /api/CongViecNoiBo. Chỉ tick hoàn thành, không thêm/xoá/cảnh báo
/// (NgayCanhBao, XNgayCanhBao) — đơn giản hoá cho bản mobile. Không có footer, khớp màn Ảnh menu.
struct CongViecListView: View {
    @State private var items: [CongViecNoiBoDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var searchText = ""
    @State private var adding = false
    @State private var errorMessage: String?

    private var sortedItems: [CongViecNoiBoDto] {
        items
            .filter { $0.ten.matchesSearch(searchText) }
            .sorted { !$0.daHoanThanh && $1.daHoanThanh }
    }

    var body: some View {
            VStack(spacing: 0) {
                SearchBar(text: $searchText, placeholder: "Tìm việc...")

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
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
                                            Label("Thêm việc mới \"\(ten)\"", systemImage: "plus.circle")
                                        }
                                    }
                                    .disabled(adding)
                                    .listRowSeparator(.hidden)
                                }
                            }
                        } else {
                            ForEach(sortedItems) { item in
                                CongViecRowView(item: item) { toggled in
                                    Task { await toggle(item, done: toggled) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.top, 4)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Công việc")
            .navigationBarTitleDisplayMode(.inline)
            // Màn hình con có nav bar riêng (không dùng header tự vẽ như các tab chính) — tô luôn
            // nav bar màu brandPrimary + chữ trắng để khớp tông màu gradient của các tab khác, thay
            // vì chồng thêm 1 lớp gradient riêng gây đụng độ 2 header.
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await load() }
            .alert("Thêm việc thất bại", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getCongViecList()
        loading = false
        hasLoaded = true
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
