import SwiftUI

/// Công cụ tra giá nguyên liệu (Menu > Công cụ) — chọn 1 nguyên liệu rồi xem 10 lần mua gần nhất
/// (đơn giá/số lượng/ngày mua) để so giá, tránh phải lật lại từng ngày trong tab Chi tiêu. Đọc
/// thẳng ChiTieuHangNgay (bản ghi mua hàng), không lưu gì mới — xem
/// GET /api/ChiTieuHangNgay/gia-gan-day (ChiTieuHangNgayController/Service).
struct GiaNguyenLieuView: View {
    @State private var nguyenLieuList: [NguyenLieuDto] = []
    @State private var searchText = ""
    @State private var selected: NguyenLieuDto?
    @State private var items: [ChiTieuHangNgayDto] = []
    @State private var loading = false

    /// Rỗng khi chưa gõ gì — khớp cách AddExpenseSheet (ChiTieuListView) tránh liệt kê hết danh
    /// sách nguyên liệu quá dài như dropdown.
    private var filteredList: [NguyenLieuDto] {
        guard !searchText.isEmpty else { return [] }
        return nguyenLieuList.filter { $0.ten.matchesSearch(searchText) }
    }

    var body: some View {
        List {
            Section("Nguyên liệu") {
                TextField("Tìm nguyên liệu...", text: $searchText)
                // Gõ tiếp bất cứ lúc nào để tìm nguyên liệu khác — không còn nút "Đổi" chặn giữa,
                // chỉ ẩn tên đã chọn đi khi đang gõ để nhường chỗ cho kết quả tìm.
                if let selected, searchText.isEmpty {
                    Text(selected.ten).bold().foregroundColor(.brandPrimary)
                }
                ForEach(filteredList.prefix(30)) { nl in
                    Button {
                        selected = nl
                        searchText = ""
                        Task { await loadGia(nl) }
                    } label: {
                        Text(nl.ten)
                    }
                }
            }

            if loading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if selected != nil {
                Section("10 lần mua gần nhất") {
                    if items.isEmpty {
                        Text("Chưa có lần mua nào.").foregroundColor(.textMuted)
                    } else {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(HoaDonFormatting.congNoTime(item.ngayGio))
                                        .font(.subheadline)
                                    Text("SL \(item.soLuong.cleanString)")
                                        .font(.caption)
                                        .foregroundColor(.textMuted)
                                }
                                Spacer()
                                Text(HoaDonFormatting.money(item.donGia))
                                    .font(.subheadline.bold())
                                    .foregroundColor(.brandPrimary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Giá nguyên liệu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { nguyenLieuList = await APIClient.shared.getNguyenLieu() }
    }

    private func loadGia(_ nl: NguyenLieuDto) async {
        loading = true
        items = await APIClient.shared.getGiaNguyenLieuGanDay(nguyenLieuId: nl.id)
        loading = false
    }
}

private extension Double {
    var cleanString: String {
        self.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(self)
    }
}
