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
    /// Nguyên liệu cần mua sắp tới (đến hạn/trễ hạn) — hiện dưới ô tìm khi chưa gõ, gấp nhất trước.
    @State private var canMua: [MuaHangDeXuatDto] = []
    @State private var canMuaLoaded = false

    private var yeuThichList: [NguyenLieuDto] {
        nguyenLieuList.filter { $0.yeuThich == true && !$0.ngungSuDung }
            .sorted { $0.ten.localizedCompare($1.ten) == .orderedAscending }
    }

    /// Nguyên liệu cần mua (có đề xuất) + nguyên liệu ⭐ chưa đến hạn (d = nil).
    private struct GoiYItem: Identifiable {
        let nl: NguyenLieuDto
        let d: MuaHangDeXuatDto?
        var id: String { nl.id }
    }

    private var goiYList: [GoiYItem] {
        let byId = Dictionary(uniqueKeysWithValues: nguyenLieuList.map { ($0.id, $0) })
        var result: [GoiYItem] = []
        var seen = Set<String>()
        for d in canMua {
            if let id = d.nguyenLieuId, let nl = byId[id], !nl.ngungSuDung, seen.insert(id).inserted {
                result.append(GoiYItem(nl: nl, d: d))
            }
        }
        for nl in yeuThichList where seen.insert(nl.id).inserted {
            result.append(GoiYItem(nl: nl, d: nil))
        }
        return result
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
                // Gộp "cần mua" + ⭐ Online: việc đến hạn/trễ hạn xếp gấp nhất trước, món ⭐ chưa đến hạn
                // (không có đề xuất) nằm dưới theo tên. ⭐ trên từng dòng vẫn bấm để ghim/bỏ ghim.
                if !goiYList.isEmpty {
                    Section("Gợi ý mua") {
                        ForEach(goiYList) { row($0.nl, $0.d) }
                    }
                } else if canMuaLoaded {
                    Section("Gợi ý mua") {
                        Text("Chưa có nguyên liệu nào đến hạn mua.").foregroundColor(.textMuted)
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
            canMua = await APIClient.shared.getCanMua()
            canMuaLoaded = true
        }
    }

    /// Dòng nguyên liệu: chạm tên để xem giá, chạm ⭐ để ghim/bỏ ghim (cập nhật ngay, lỗi thì hoàn lại).
    /// Có đề xuất `d` thì hiện thêm số lượng thường mua + mức gấp (trễ/hôm nay/còn N ngày).
    private func row(_ nl: NguyenLieuDto, _ d: MuaHangDeXuatDto? = nil) -> some View {
        HStack {
            Button {
                selected = nl
                showDetail = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nl.ten).foregroundColor(.primary)
                        if let sl = d?.soLuongDeXuat {
                            Text("Thường mua \(sl.cleanString)" + (nl.donViTinh.map { " \($0)" } ?? ""))
                                .font(.caption).foregroundColor(.textMuted)
                        }
                    }
                    Spacer()
                    if let d {
                        Text(d.soNgayConLai < 0 ? "Trễ \(-d.soNgayConLai) ngày" : d.soNgayConLai == 0 ? "Hôm nay" : "Còn \(d.soNgayConLai) ngày")
                            .font(.caption.bold())
                            .foregroundColor(d.soNgayConLai <= 0 ? .red : .brandPrimary)
                    }
                }
            }
            Button {
                Task { await toggleYeuThich(nl) }
            } label: {
                Image(systemName: nl.yeuThich == true ? "star.fill" : "star")
                    .foregroundColor(nl.yeuThich == true ? .yellow : .textMuted)
            }
            .buttonStyle(.borderless)
            // Nút "Ngừng dùng" cạnh ⭐: loại nguyên liệu không còn mua khỏi danh sách (đặt NgungSuDung,
            // bật lại được ở màn Nguyên liệu). Không hiện ở món đã ngừng dùng (kết quả tìm kiếm).
            if !nl.ngungSuDung {
                Button {
                    Task { await ngungSuDung(nl) }
                } label: {
                    Image(systemName: "nosign").foregroundColor(.textMuted)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
        }
    }

    /// Đánh dấu ngừng sử dụng — ẩn dòng ngay (goiYList lọc theo ngungSuDung), lỗi thì hoàn lại.
    private func ngungSuDung(_ nl: NguyenLieuDto) async {
        guard let i = nguyenLieuList.firstIndex(where: { $0.id == nl.id }) else { return }
        nguyenLieuList[i].ngungSuDung = true
        if !(await APIClient.shared.setNguyenLieuNgungSuDung(id: nl.id, value: true)),
           let j = nguyenLieuList.firstIndex(where: { $0.id == nl.id }) {
            nguyenLieuList[j].ngungSuDung = false
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
    /// Tải riêng, không chặn danh sách giá — AI trả chậm hơn, xong lúc nào hiện lúc đó.
    @State private var deXuat: MuaHangDeXuatDto?
    @State private var deXuatLoading = true

    var body: some View {
        List {
            if deXuatLoading || deXuat != nil {
                Section("Đề xuất mua tiếp") { deXuatCard }
            }
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
            async let giaTask = APIClient.shared.getGiaNguyenLieuGanDay(nguyenLieuId: nguyenLieu.id)
            async let deXuatTask = APIClient.shared.getDeXuatMua(nguyenLieuId: nguyenLieu.id)
            items = await giaTask
            loading = false
            deXuat = await deXuatTask
            deXuatLoading = false
        }
    }

    @ViewBuilder
    private var deXuatCard: some View {
        if let d = deXuat {
            let ngay = HoaDonFormatting.parseIso(d.ngayDeXuat)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ngay.map { $0.formatted(.dateTime.weekday(.wide).day().month().locale(Locale(identifier: "vi_VN"))) } ?? d.ngayDeXuat)
                        .font(.headline)
                    Spacer()
                    Text(conLaiText(d.soNgayConLai))
                        .font(.subheadline.bold())
                        .foregroundColor(d.soNgayConLai <= 0 ? .red : .brandPrimary)
                }
                if let sl = d.soLuongDeXuat {
                    Text("Nên mua khoảng \(sl.cleanString)" + (nguyenLieu.donViTinh.map { " \($0)" } ?? ""))
                        .font(.subheadline)
                }
                Text((d.nguonAI ? "✨ AI: " : "") + d.lyDo)
                    .font(.caption)
                    .foregroundColor(.textMuted)
            }
            .padding(.vertical, 2)
        } else {
            HStack {
                Spacer()
                ProgressView().tint(.brandPrimary)
                Text("AI đang tính...").font(.caption).foregroundColor(.textMuted)
                Spacer()
            }
        }
    }

    private func conLaiText(_ n: Int) -> String {
        if n < 0 { return "Quá hạn \(-n) ngày" }
        if n == 0 { return "Hôm nay" }
        return "Còn \(n) ngày"
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
