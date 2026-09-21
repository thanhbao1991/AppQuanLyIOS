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
    @State private var showDetail = false
    /// Nguyên liệu chi nhiều nhất từ đầu năm — hiện dưới ô tìm khi chưa gõ để chọn nhanh.
    @State private var topIds: [String] = []

    private var topList: [NguyenLieuDto] {
        let byId = Dictionary(uniqueKeysWithValues: nguyenLieuList.map { ($0.id, $0) })
        return topIds.compactMap { byId[$0] }
    }

    private var yeuThichList: [NguyenLieuDto] {
        nguyenLieuList.filter { $0.yeuThich == true && !$0.ngungSuDung }
            .sorted { $0.ten.localizedCompare($1.ten) == .orderedAscending }
    }

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
            }

            if searchText.isEmpty {
                if !yeuThichList.isEmpty {
                    Section("⭐ Online") {
                        ForEach(yeuThichList) { row($0) }
                    }
                }
                // Món đã ⭐ nằm nhóm trên rồi — nhóm này bù thêm cho đủ tổng 30 dòng.
                let conLai = topList.filter { $0.yeuThich != true }.prefix(max(30 - yeuThichList.count, 0))
                if !conLai.isEmpty {
                    Section("Chi nhiều nhất năm nay") {
                        ForEach(Array(conLai)) { row($0) }
                    }
                }
            } else {
                Section("Kết quả") {
                    ForEach(filteredList.prefix(30)) { row($0) }
                }
            }
        }
        .navigationTitle("Giá nguyên liệu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Chạm tên → sang màn riêng xem giá (thay vì kéo xuống cuối danh sách).
        .navigationDestination(isPresented: $showDetail) {
            if let selected { GiaNguyenLieuDetailView(nguyenLieu: selected) }
        }
        .task {
            nguyenLieuList = await APIClient.shared.getNguyenLieu()
            await loadTop()
        }
    }

    /// Cộng ThanhTien theo nguyên liệu qua các tháng từ đầu năm (gọi song song từng tháng), xếp theo
    /// chi nhiều nhất (còn đang dùng); phần cắt đủ 30 dòng làm ở body sau khi trừ món đã ⭐.
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
        topIds = tong.sorted { $0.value > $1.value }
            .compactMap { byId[$0.key] }
            .filter { !$0.ngungSuDung }
            .map { $0.id }
    }

    /// Dòng nguyên liệu: chạm tên để xem giá, chạm ⭐ để ghim/bỏ ghim (cập nhật ngay, lỗi thì hoàn lại).
    private func row(_ nl: NguyenLieuDto) -> some View {
        HStack {
            Button {
                selected = nl
                showDetail = true
            } label: {
                Text(nl.ten).frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                Task { await toggleYeuThich(nl) }
            } label: {
                Image(systemName: nl.yeuThich == true ? "star.fill" : "star")
                    .foregroundColor(nl.yeuThich == true ? .yellow : .textMuted)
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleYeuThich(_ nl: NguyenLieuDto) async {
        guard let i = nguyenLieuList.firstIndex(where: { $0.id == nl.id }) else { return }
        let value = nguyenLieuList[i].yeuThich != true
        nguyenLieuList[i].yeuThich = value
        if !(await APIClient.shared.setNguyenLieuYeuThich(id: nl.id, value: value)),
           let j = nguyenLieuList.firstIndex(where: { $0.id == nl.id }) {
            nguyenLieuList[j].yeuThich = !value
        }
    }
}

/// Màn xem giá 1 nguyên liệu: biểu đồ + 15 lần mua gần nhất.
private struct GiaNguyenLieuDetailView: View {
    let nguyenLieu: NguyenLieuDto
    @State private var items: [ChiTieuHangNgayDto] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView().scaleEffect(1.4).tint(.brandPrimary)
                        Spacer()
                    }
                }
            } else if items.isEmpty {
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
        .navigationTitle(nguyenLieu.ten)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            items = await APIClient.shared.getGiaNguyenLieuGanDay(nguyenLieuId: nguyenLieu.id)
            loading = false
        }
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
