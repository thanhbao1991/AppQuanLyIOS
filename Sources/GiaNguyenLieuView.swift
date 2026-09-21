import Charts
import SwiftUI

/// Công cụ tra giá nguyên liệu (Menu > Công cụ) — chọn 1 nguyên liệu rồi xem 15 lần mua gần nhất
/// (đơn giá/số lượng/ngày mua) để so giá, tránh phải lật lại từng ngày trong tab Chi tiêu. Đọc
/// thẳng ChiTieuHangNgay (bản ghi mua hàng), không lưu gì mới — xem
/// GET /api/ChiTieuHangNgay/gia-gan-day (ChiTieuHangNgayController/Service).
struct GiaNguyenLieuView: View {
    @State private var nguyenLieuList: [NguyenLieuDto] = []
    @State private var searchText = ""
    @State private var selected: NguyenLieuDto?
    @State private var items: [ChiTieuHangNgayDto] = []
    @State private var loading = false
    /// Nguyên liệu chi nhiều nhất từ đầu năm — hiện dưới ô tìm khi chưa gõ để chọn nhanh.
    @State private var topList: [NguyenLieuDto] = []

    /// Rỗng khi chưa gõ gì — khớp cách AddExpenseSheet (ChiTieuListView) tránh liệt kê hết danh
    /// sách nguyên liệu quá dài như dropdown.
    private var filteredList: [NguyenLieuDto] {
        guard !searchText.isEmpty else { return [] }
        return nguyenLieuList.filter { $0.ten.matchesSearch(searchText) }
    }

    var body: some View {
        List {
            Section(searchText.isEmpty && !topList.isEmpty ? "Chi nhiều nhất năm nay" : "Nguyên liệu") {
                TextField("Tìm nguyên liệu...", text: $searchText)
                // Gõ tiếp bất cứ lúc nào để tìm nguyên liệu khác — không còn nút "Đổi" chặn giữa,
                // chỉ ẩn tên đã chọn đi khi đang gõ để nhường chỗ cho kết quả tìm.
                if let selected, searchText.isEmpty {
                    Text(selected.ten).bold().foregroundColor(.brandPrimary)
                }
                ForEach(searchText.isEmpty ? topList : Array(filteredList.prefix(30))) { nl in
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
                        ProgressView().scaleEffect(1.4).tint(.brandPrimary)
                        Spacer()
                    }
                }
            } else if selected != nil {
                if items.isEmpty {
                    Section("15 lần mua gần nhất") {
                        Text("Chưa có lần mua nào.").foregroundColor(.textMuted)
                    }
                } else {
                    Section("Diễn biến giá") {
                        GiaNguyenLieuChart(items: items)
                    }
                    Section("15 lần mua gần nhất") {
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
        .task {
            nguyenLieuList = await APIClient.shared.getNguyenLieu()
            await loadTop()
        }
    }

    /// Cộng ThanhTien theo nguyên liệu qua các tháng từ đầu năm (gọi song song từng tháng), lấy 15
    /// nguyên liệu chi nhiều nhất còn đang dùng.
    private func loadTop() async {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        var tong: [String: Double] = [:]
        await withTaskGroup(of: [ChiTieuHangNgayDto].self) { group in
            for m in 1...month {
                group.addTask { await APIClient.shared.getChiTieuByMonth(year: year, month: m) }
            }
            for await rows in group {
                for r in rows { tong[r.nguyenLieuId, default: 0] += r.thanhTien }
            }
        }
        let byId = Dictionary(uniqueKeysWithValues: nguyenLieuList.map { ($0.id, $0) })
        topList = tong.sorted { $0.value > $1.value }
            .compactMap { byId[$0.key] }
            .filter { !$0.ngungSuDung }
            .prefix(15)
            .map { $0 }
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

/// Đường xu hướng đơn giá qua các lần mua — khớp phong cách KetQua6ThangChart (TinhLuongView).
/// `items` từ API xếp mới→cũ (NgayGio desc), đảo lại để trục X chạy trái→phải theo thời gian.
private struct GiaNguyenLieuChart: View {
    let items: [ChiTieuHangNgayDto]

    private var points: [(id: String, date: Date, donGia: Double)] {
        items.reversed().map { item in
            let date = HoaDonFormatting.parseIso(item.ngayGio) ?? .distantPast
            return (id: item.id, date: date, donGia: item.donGia)
        }
    }

    var body: some View {
        Chart(points, id: \.id) { point in
            LineMark(x: .value("Ngày", point.date), y: .value("Đơn giá", point.donGia))
                .foregroundStyle(Color.brandPrimary)
            PointMark(x: .value("Ngày", point.date), y: .value("Đơn giá", point.donGia))
                .foregroundStyle(Color.brandPrimary)
                .symbolSize(60)
        }
        .chartXAxis {
            // desiredCount thay vì .automatic trơn — dữ liệu là Date thật nên Charts tự thưa nhãn,
            // tránh chồng chữ khi có đủ 30 lần mua như trục string cũ.
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(), centered: true).font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(HoaDonFormatting.moneyShort(d)).font(.caption2)
                    }
                }
            }
        }
        .frame(height: 160)
        .padding(.vertical, 8)
    }
}
