import Charts
import SwiftUI

/// Công cụ tra giá nguyên liệu (Menu > Công cụ) — chọn 1 nguyên liệu rồi xem 5 lần mua gần nhất
/// (đơn giá/số lượng/ngày mua) để so giá, tránh phải lật lại từng ngày trong tab Chi tiêu. Đọc
/// thẳng ChiTieuHangNgay (bản ghi mua hàng), không lưu gì mới — xem
/// GET /api/ChiTieuHangNgay/gia-gan-day (ChiTieuHangNgayController/Service).
///
/// Gộp chung 1 màn cho cả "Nguyên liệu" / "Vật liệu" / "Vật tư" / "Chi phí khác" (Menu > Công cụ) —
/// tính năng giống hệt nhau, chỉ khác bộ lọc theo NguyenLieuDto.phanLoai. Mặc định hiện "Tất cả";
/// đổi nhóm qua menu lọc trên toolbar. `phanLoai == nil` (chưa phân loại) luôn được tính vào nhóm
/// "Nguyên liệu" để không mất các dòng cũ trước khi có cột PhanLoai/chưa kịp phân loại.
///
/// Đã gộp luôn màn danh mục "Nguyên liệu" (Menu > Cấu hình) vào đây: nút + để thêm, màn chi tiết có
/// nút "Sửa" (NguyenLieuEditSheet), xoá bằng vuốt trái trên danh sách — 1 mục menu "Nguyên liệu & giá"
/// thay cho 2 mục.
struct GiaNguyenLieuView: View {
    /// nil = Tất cả. Truyền sẵn 1 nhóm khi cần mở thẳng vào nhóm đó.
    @State private var phanLoai: PhanLoaiNguyenLieu?

    init(phanLoai: PhanLoaiNguyenLieu? = nil) {
        _phanLoai = State(initialValue: phanLoai)
    }

    private var title: String { phanLoai?.giaScreenTitle ?? "Nguyên liệu & giá" }

    @State private var allNguyenLieu: [NguyenLieuDto] = []
    @State private var searchText = ""
    @State private var selected: NguyenLieuDto?
    @State private var showDetail = false
    @State private var showAdd = false
    /// Nguyên liệu cần mua sắp tới (đến hạn/trễ hạn) — hiện dưới ô tìm khi chưa gõ, gấp nhất trước.
    @State private var canMua: [MuaHangDeXuatDto] = []
    @State private var canMuaLoaded = false
    @State private var loadFailed = false
    /// Nguyên liệu đang chờ xác nhận "Ngừng dùng" — chạm nhầm 1 lần là dòng biến khỏi danh sách,
    /// muốn lấy lại phải gõ tìm đúng tên.
    @State private var ngungDungPending: NguyenLieuDto?
    @State private var xoaPending: NguyenLieuDto?

    /// Không chọn nhóm nào (Tất cả) thì lấy hết; chọn nhóm thì lọc đúng nhóm đó (nhóm Nguyên liệu
    /// nhận thêm cả phanLoai == nil).
    private var nguyenLieuList: [NguyenLieuDto] {
        var list = allNguyenLieu
        if let phanLoai {
            list = list.filter {
                $0.phanLoai == phanLoai.rawValue || (phanLoai == .nguyenLieu && $0.phanLoai == nil)
            }
        }
        return list
    }

    private var muaShopeeList: [NguyenLieuDto] {
        nguyenLieuList.filter { $0.muaShopee == true && !$0.ngungSuDung }
            .sorted { $0.ten.localizedCompare($1.ten) == .orderedAscending }
    }

    /// Nguyên liệu cần mua (có đề xuất) + nguyên liệu giỏ Shopee chưa đến hạn (d = nil).
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
        for nl in muaShopeeList where seen.insert(nl.id).inserted {
            result.append(GoiYItem(nl: nl, d: nil))
        }
        return result
    }

    /// Tách "Gợi ý mua" thành 2 nhóm: nhóm 1 là nguyên liệu giỏ Shopee, nhóm 2 là phần còn lại (đến hạn/trễ hạn nhưng không mua Shopee).
    private var goiYMuaShopee: [GoiYItem] {
        goiYList.filter { $0.nl.muaShopee == true }
    }

    private var goiYKhac: [GoiYItem] {
        goiYList.filter { $0.nl.muaShopee != true }
    }

    /// Rỗng khi chưa gõ gì — khớp cách AddExpenseSheet (ChiTieuListView) tránh liệt kê hết danh
    /// sách nguyên liệu quá dài như dropdown.
    private var filteredList: [NguyenLieuDto] {
        guard !searchText.isEmpty else { return [] }
        return nguyenLieuList.filter { $0.ten.matchesSearch(searchText) }
    }

    /// Tách kết quả tìm kiếm: nhóm 1 là nguyên liệu giỏ Shopee, nhóm 2 là phần còn lại.
    private var filteredMuaShopee: [NguyenLieuDto] {
        filteredList.filter { $0.muaShopee == true }
    }

    private var filteredKhac: [NguyenLieuDto] {
        filteredList.filter { $0.muaShopee != true }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm nguyên liệu...")

            List {
                if loadFailed {
                    ThongKeLoadErrorBanner(text: "Chưa tải được danh sách nguyên liệu") { Task { await load() } }
                        .listRowSeparator(.hidden)
                }
                // Không tiêu đề nhóm (đồng bộ màn Tồn kho). Tách giỏ Shopee riêng với nhóm còn lại; giỏ trên từng dòng vẫn bấm để ghim/bỏ ghim.
                if searchText.isEmpty {
                    if !goiYMuaShopee.isEmpty {
                        Section {
                            ForEach(goiYMuaShopee) { row($0.nl, $0.d) }
                        }
                    }
                    if !goiYKhac.isEmpty {
                        Section {
                            ForEach(goiYKhac) { row($0.nl, $0.d) }
                        }
                    } else if canMuaLoaded && goiYMuaShopee.isEmpty && !loadFailed {
                        Section {
                            Text("Chưa có nguyên liệu nào đến hạn mua.").foregroundColor(.textMuted)
                        }
                    }
                } else {
                    if !filteredMuaShopee.isEmpty {
                        Section {
                            ForEach(filteredMuaShopee.prefix(30)) { row($0) }
                        }
                    }
                    if !filteredKhac.isEmpty {
                        Section {
                            ForEach(filteredKhac.prefix(30)) { row($0) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .softScrollEdgeTop()
            .refreshable { await load() }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Nhảy thẳng sang Tồn kho, khỏi quay ra Menu (2 màn tách riêng từ 17/10/2026).
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink { TonKhoListView() } label: {
                    Image(systemName: "shippingbox").foregroundColor(.white)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus").foregroundColor(.white)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                PopoverMenu(width: 230) {
                    PopoverMenuItem("Tất cả", isSelected: phanLoai == nil) { phanLoai = nil }
                    PopoverMenuDivider()
                    ForEach(PhanLoaiNguyenLieu.allCases) { pl in
                        PopoverMenuItem(pl.label, isSelected: phanLoai == pl) { phanLoai = pl }
                    }
                } label: {
                    Image(systemName: phanLoai != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .foregroundColor(.white)
                }
            }
        }
        // Chạm tên → sang màn riêng xem giá (thay vì kéo xuống cuối danh sách).
        .navigationDestination(isPresented: $showDetail) {
            if let selected { GiaNguyenLieuDetailView(nguyenLieu: selected) { await load() } }
        }
        .sheet(isPresented: $showAdd) {
            NguyenLieuEditSheet(existing: nil) { Task { await load() } }
        }
        .task { await load() }
        .confirmDelete(
            $ngungDungPending, title: "Ngừng dùng nguyên liệu", confirmLabel: "Ngừng dùng",
            name: { $0.ten },
            note: "Nguyên liệu sẽ ẩn khỏi danh sách; muốn dùng lại thì gõ tìm đúng tên rồi bấm nút hoàn tác.",
            perform: { await ngungSuDung($0) },
            onDone: {})
        .confirmDelete($xoaPending, name: { $0.ten }, perform: { await APIClient.shared.deleteNguyenLieu(id: $0.id) }, onDone: load)
    }

    private func load() async {
        let fresh = await APIClient.shared.getNguyenLieuOrNil()
        if let fresh { allNguyenLieu = fresh }
        loadFailed = fresh == nil
        canMua = await APIClient.shared.getCanMua()
        canMuaLoaded = true
    }

    /// Dòng nguyên liệu: chạm tên để xem giá, chạm giỏ để ghim/bỏ ghim (cập nhật ngay, lỗi thì hoàn lại).
    /// Có đề xuất `d` thì hiện thêm số lượng thường mua + mức gấp (trễ/hôm nay/còn N ngày).
    private func row(_ nl: NguyenLieuDto, _ d: MuaHangDeXuatDto? = nil) -> some View {
        HStack(spacing: 12) {
            // Giỏ xách bên trái tên = mua qua Shopee (field muaShopee).
            Button {
                Task { await toggleMuaShopee(nl) }
            } label: {
                Image(systemName: nl.muaShopee == true ? "bag.fill" : "bag")
                    .foregroundColor(nl.muaShopee == true ? .orange : .textMuted)
            }
            .buttonStyle(.borderless)
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
            if nl.ngungSuDung && !searchText.isEmpty {
                // Nguyên liệu đã ngừng dùng chỉ xuất hiện lại khi tìm kiếm — thêm nút bỏ đánh dấu ngay tại đây.
                Button {
                    Task { await boNgungSuDung(nl) }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle").foregroundColor(.brandPrimary)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 8)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        // Xoá / Ngừng dùng bằng vuốt trái (quy ước mọi màn trong Menu) — thay nút ⃠ cạnh dòng và nút
        // "Xoá nguyên liệu" trong màn Sửa, cả hai đều dễ chạm nhầm. Vẫn qua hộp xác nhận.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { xoaPending = nl } label: { Label("Xoá", systemImage: "trash") }
                .tint(.dangerColor)
            if !nl.ngungSuDung {
                Button { ngungDungPending = nl } label: { Label("Ngừng dùng", systemImage: "nosign") }
                    .tint(.gray)
            }
        }
    }

    /// Đánh dấu ngừng sử dụng — ẩn dòng ngay (goiYList lọc theo ngungSuDung), lỗi thì hoàn lại.
    private func ngungSuDung(_ nl: NguyenLieuDto) async -> ActionResult {
        guard let i = allNguyenLieu.firstIndex(where: { $0.id == nl.id }) else {
            return ActionResult(success: true, message: nil)
        }
        allNguyenLieu[i].ngungSuDung = true
        if !(await APIClient.shared.setNguyenLieuNgungSuDung(id: nl.id, value: true)) {
            if let j = allNguyenLieu.firstIndex(where: { $0.id == nl.id }) {
                allNguyenLieu[j].ngungSuDung = false
            }
            return ActionResult(success: false, message: "Chưa đánh dấu ngừng dùng được \"\(nl.ten)\" — thử lại.")
        }
        return ActionResult(success: true, message: nil)
    }

    /// Bỏ đánh dấu ngừng sử dụng — chỉ gọi được từ kết quả tìm kiếm (mục đã ngừng dùng mới hiện ở đó).
    private func boNgungSuDung(_ nl: NguyenLieuDto) async {
        guard let i = allNguyenLieu.firstIndex(where: { $0.id == nl.id }) else { return }
        allNguyenLieu[i].ngungSuDung = false
        if !(await APIClient.shared.setNguyenLieuNgungSuDung(id: nl.id, value: false)),
           let j = allNguyenLieu.firstIndex(where: { $0.id == nl.id }) {
            allNguyenLieu[j].ngungSuDung = true
        }
    }

    private func toggleMuaShopee(_ nl: NguyenLieuDto) async {
        guard let i = allNguyenLieu.firstIndex(where: { $0.id == nl.id }) else { return }
        let value = allNguyenLieu[i].muaShopee != true
        allNguyenLieu[i].muaShopee = value
        if !(await APIClient.shared.setNguyenLieuMuaShopee(id: nl.id, value: value)),
           let j = allNguyenLieu.firstIndex(where: { $0.id == nl.id }) {
            allNguyenLieu[j].muaShopee = !value
        }
    }
}

/// Màn xem giá 1 nguyên liệu: thông tin (sửa/xoá qua nút "Sửa") + biểu đồ + 5 lần mua gần nhất.
struct GiaNguyenLieuDetailView: View {
    @State private var nguyenLieu: NguyenLieuDto
    /// Báo màn danh sách tải lại sau khi sửa/xoá.
    let onChanged: () async -> Void

    init(nguyenLieu: NguyenLieuDto, onChanged: @escaping () async -> Void) {
        _nguyenLieu = State(initialValue: nguyenLieu)
        self.onChanged = onChanged
    }

    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false
    @State private var items: [ChiTieuHangNgayDto] = []
    @State private var loading = true
    /// Tải riêng, không chặn danh sách giá — AI trả chậm hơn, xong lúc nào hiện lúc đó.
    @State private var deXuat: MuaHangDeXuatDto?
    @State private var deXuatLoading = true

    var body: some View {
        List {
            Section("Thông tin") { thongTin }
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
                Section("5 lần mua gần nhất") {
                    Text("Chưa có lần mua nào.").foregroundColor(.textMuted)
                }
            } else {
                Section("Diễn biến giá") {
                    GiaNguyenLieuChart(items: items)
                }
                Section("5 lần mua gần nhất") {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(thoiDiemMua(item))
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Sửa") { showEdit = true }.foregroundColor(.white)
            }
        }
        .sheet(isPresented: $showEdit) {
            NguyenLieuEditSheet(existing: nguyenLieu) { Task { await refresh() } }
        }
        .task {
            async let giaTask = APIClient.shared.getGiaNguyenLieuGanDay(nguyenLieuId: nguyenLieu.id, soLan: 5)
            async let deXuatTask = APIClient.shared.getDeXuatMua(nguyenLieuId: nguyenLieu.id)
            items = await giaTask
            loading = false
            deXuat = await deXuatTask
            deXuatLoading = false
        }
    }

    /// Lấy lại bản mới sau khi sửa; không còn trong danh sách (đã xoá) thì quay về màn trước.
    private func refresh() async {
        if let fresh = await APIClient.shared.getNguyenLieuOrNil() {
            if let nl = fresh.first(where: { $0.id == nguyenLieu.id }) {
                nguyenLieu = nl
            } else {
                dismiss()
            }
        }
        await onChanged()
    }

    @ViewBuilder
    private var thongTin: some View {
        HStack {
            Text("Giá nhập")
            Spacer()
            Text(HoaDonFormatting.money(nguyenLieu.giaNhap) + (nguyenLieu.donViTinh.map { $0.isEmpty ? "" : " / \($0)" } ?? ""))
                .fontWeight(.semibold)
                .foregroundColor(.brandPrimary)
        }
        HStack {
            Text("Phân loại")
            Spacer()
            if let pl = nguyenLieu.phanLoai, let label = PhanLoaiNguyenLieu.label(for: pl) {
                Text(label)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(PhanLoaiNguyenLieu.color(for: pl))
                    .clipShape(Capsule())
            } else {
                Text("Chưa phân loại").foregroundColor(.textMuted)
            }
        }
        // Chạm → sang đúng món này bên màn Tồn kho (xem/kiểm kê), khỏi quay ra Menu tìm lại.
        if let bhId = nguyenLieu.nguyenLieuBanHangId {
            NavigationLink {
                TonKhoChiTietView(nguyenLieuBanHangId: bhId)
            } label: {
                HStack {
                    Text("Tồn kho")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(TonKhoNguyenLieu.nhanDong(nguyenLieu) ?? "Chưa theo dõi")
                            .fontWeight(.semibold).monospacedDigit()
                            .foregroundColor(TonKhoNguyenLieu.dangTheoDoi(nguyenLieu) ? TonKhoNguyenLieu.mau(nguyenLieu) : .textMuted)
                        if let phu = TonKhoNguyenLieu.phuDong(nguyenLieu) {
                            Text(phu).font(.caption).foregroundColor(.textMuted)
                        }
                    }
                }
            }
        }
        if nguyenLieu.ngungSuDung {
            Text("Đã ngừng dùng").foregroundColor(.textMuted)
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
            }
            .padding(.vertical, 2)
        } else {
            HStack {
                Spacer()
                ProgressView().tint(.brandPrimary)
                Text("Đang tính...").font(.caption).foregroundColor(.textMuted)
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

/// Ngày mua thật là `ngay`; `ngayGio` là giờ bấm lưu. Nhập bù ngày cũ (chọn 5/5 rồi thêm vào 16/10)
/// thì 2 mốc khác ngày — khi đó chỉ hiện ngày mua, không ghép giờ lưu vào cho khỏi sai.
private func thoiDiemMua(_ item: ChiTieuHangNgayDto) -> String {
    guard let ngay = HoaDonFormatting.parseIso(item.ngay) else { return HoaDonFormatting.congNoTime(item.ngayGio) }
    if let gio = HoaDonFormatting.parseIso(item.ngayGio), Calendar.current.isDate(ngay, inSameDayAs: gio) {
        return HoaDonFormatting.congNoTime(item.ngayGio)
    }
    let f = DateFormatter()
    f.dateFormat = "dd/MM/yyyy"
    f.locale = Locale(identifier: "vi_VN")
    return f.string(from: ngay)
}

private extension Double {
    var cleanString: String {
        self.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(self)
    }
}

/// Đường xu hướng đơn giá qua các lần mua — khớp phong cách KetQua6ThangChart (TinhLuongView).
/// `items` từ API xếp mới→cũ (Ngay desc), đảo lại để trục X chạy trái→phải theo thời gian.
private struct GiaNguyenLieuChart: View {
    let items: [ChiTieuHangNgayDto]

    private var points: [(id: String, date: Date, donGia: Double)] {
        items.reversed().map { item in
            let date = HoaDonFormatting.parseIso(item.ngay ?? item.ngayGio) ?? .distantPast
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
