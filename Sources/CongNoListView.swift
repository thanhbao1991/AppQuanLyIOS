import SwiftUI
import UIKit

/// Danh sách hoá đơn còn ghi nợ, gọi GET /api/dashboard/cong-no-list (không có tham số ngày —
/// khác Hoá đơn/Thanh toán/Chi tiêu). Bấm vào card mở HoaDonDetailView để xem chi tiết + thu tiền
/// (đã bỏ 2 nút Tiền mặt/Chuyển khoản thu nhanh trên card — quay lại luồng mở sheet).
struct CongNoListView: View {
    @State private var items: [HoaDonListDto] = []
    @State private var loading = false
    @State private var hasLoaded = false
    @State private var selectedId: String?
    @State private var searchText = ""
    /// Lọc theo ngày ghi nợ (ngayNo) — nil = "Tất cả" (mặc định, khớp hành vi cũ trước khi có filter
    /// này). Khác Hoá đơn/Thanh toán (luôn bắt buộc 1 ngày, query lại server mỗi lần đổi) — Công nợ
    /// tải hết 1 lần (API không nhận tham số ngày) rồi lọc client-side, nên "không chọn ngày" vẫn
    /// là trạng thái hợp lệ và là mặc định.
    @State private var selectedDate: Date?

    private var sortedItems: [HoaDonListDto] {
        items
            // Bắt buộc gõ ĐÚNG dấu — khác mọi tab khác (tìm không dấu vẫn khớp) — vì đây là danh sách
            // nợ, khớp nhầm 2 khách tên gần giống nhau (khác dấu) có thể thu/gửi bill nhầm người.
            .filter { anyMatchesSearch(searchText, diacriticInsensitive: false, $0.tenKhachHangText, $0.tenBan, $0.ghiChu, $0.tenMonSummary) }
            .filter { item in
                guard let selectedDate else { return true }
                let dayStr = DateNavFormat.queryDate.string(from: selectedDate)
                return (item.ngayNo ?? "").hasPrefix(dayStr)
            }
            .sorted { ($0.ngayNo ?? "") > ($1.ngayNo ?? "") }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    CongNoDateFilterBar(date: $selectedDate)
                    SearchFieldRow(text: $searchText, placeholder: "Tìm có dấu: khách, món, ghi chú...")
                }
                .frame(height: HeaderBarMetrics.rowHeight)
                .padding(.horizontal)
                .padding(.vertical, HeaderBarMetrics.verticalPadding)
                .background(
                    LinearGradient(colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .top)
                )

                if !hasLoaded {
                    Spacer(); ProgressView(); Spacer()
                } else {
                    List {
                        if sortedItems.isEmpty {
                            Text("Không có công nợ nào")
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity)
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(sortedItems) { item in
                                CongNoRowView(
                                    item: item,
                                    onSelect: { selectedId = item.id }
                                )
                                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                // Cố ý KHÔNG có nút Xoá — mọi đơn trong tab này đều đã ghi nợ, xoá
                                // cứng quá nguy hiểm (mất dữ liệu nợ khách). Chỉ cho thu tiền ở đây;
                                // nếu cần huỷ đơn thì dùng Rollback bên Desktop (NoTabControl), khớp
                                // guard NgayNo bên HoaDonTabControl.Actions.cs.
                            }
                        }
                    }
                    .listStyle(.plain)
                    .padding(.top, 4)
                    .scrollDismissesKeyboard(.immediately)
                    .refreshable { await load() }
                }

                Divider()
                CongNoFooterView(items: sortedItems, label: searchText, showSendButton: !searchText.isEmpty)
            }
        }
        .task { await load() }
        .onEntityChanged(["HoaDon"], tab: .congNo) { Task { await load() } }
        .sheet(item: Binding(
            get: { selectedId.map { IdentifiableId($0) } },
            set: { selectedId = $0?.value }
        )) { wrapped in
            HoaDonDetailView(hoaDonId: wrapped.value) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        loading = true
        items = await APIClient.shared.getCongNoList()
        loading = false
        hasLoaded = true
    }
}

/// Nút chọn ngày lọc cho tab Công nợ — khác `DaySearchBar` (Hoá đơn/Thanh toán) ở chỗ cho phép
/// trạng thái "Tất cả" (date == nil), vì Công nợ không bắt buộc phải xem theo từng ngày như 2 tab
/// kia. Dùng Menu thay vì bấm mở thẳng DatePicker để chèn 2 lối tắt "Hôm nay"/"Hôm qua" (khớp yêu
/// cầu) mà không phải tự vẽ lại UI chọn ngày kiểu Hoá đơn.
private struct CongNoDateFilterBar: View {
    @Binding var date: Date?
    @State private var showPicker = false
    @State private var pickerDate = Date()

    private var label: String {
        guard let date else { return "Tất cả" }
        return DateNavFormat.dayTitle.string(from: date)
    }

    var body: some View {
        Menu {
            Button("Hôm nay") { date = Date() }
            Button("Hôm qua") { date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) }
            Button("Chọn ngày khác…") {
                pickerDate = date ?? Date()
                showPicker = true
            }
            if date != nil {
                Divider()
                Button("Tất cả", role: .destructive) { date = nil }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(label)
            }
            .font(.subheadline.bold())
            .foregroundColor(.white)
        }
        .fixedSize()
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                DatePicker("Chọn ngày", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .navigationBarTitleDisplayMode(.inline)
                    // Chọn 1 ô là đóng luôn, khớp hành vi DaySearchBar — chỉ đổi tháng/năm hiển thị
                    // trong lịch không kích hoạt vì chưa đổi giá trị pickerDate.
                    .onChange(of: pickerDate) { newValue in
                        showPicker = false
                        date = newValue
                    }
                Spacer()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

/// Footer "Hôm nay" + "Tổng nợ" + nút gửi bill ảnh QR — dùng chung giữa CongNoListView (tab Công nợ,
/// `label` = searchText, chỉ hiện nút khi đã gõ tìm) và KhachHangNoDetailSheet (Thống kê, `label` =
/// tên khách, luôn hiện vì đã lọc sẵn 1 khách). Không đánh dấu private.
struct CongNoFooterView: View {
    let items: [HoaDonListDto]
    let label: String
    var showSendButton: Bool = true
    /// Truyền xuống CongNoRowView khi render ảnh — false ở KhachHangNoDetailSheet (đã lọc 1 khách,
    /// list trên màn hình cũng đang ẩn tên) để ảnh xuất ra khớp đúng những gì đang thấy.
    var showName: Bool = true

    @State private var copiedFeedback = false
    @State private var showPayAllConfirm = false
    @State private var payAllInput = ""
    @State private var payingAll = false
    @State private var payAllResultMessage: String?
    /// true = thu tiền mặt, false = chuyển khoản — chọn qua 1 trong 2 nút, dùng chung 1 luồng xác
    /// nhận/thực thi payAll() bên dưới, khớp cách thuTien(isCash:) nhận cùng 1 tham số ở từng đơn
    /// (HoaDonDetailView, nút F1/F4).
    @State private var payAllIsCash = true
    /// Tổ hợp hoá đơn khớp đúng số tiền khách trả thiếu (xem findMatchingSubset) — chờ xác nhận
    /// riêng ở alert thứ 2 trước khi thu, KHÔNG tự động thu ngay khi tìm thấy khớp.
    @State private var matchedSubset: [HoaDonListDto]?
    @State private var showMatchConfirm = false
    @State private var showMultiCustomerError = false

    private var totalText: String {
        HoaDonFormatting.money(items.reduce(0) { $0 + $1.conLai })
    }

    /// Định danh khách để so "cùng 1 người" — ưu tiên `khachHangId` (khách đã có hồ sơ, chắc chắn
    /// đúng); khách lẻ (không có `khachHangId`) coi là CÙNG người chỉ khi trùng cả tên lẫn SĐT hiển
    /// thị, vì tên trùng (vd nhiều "Khách lẻ") không đủ để gộp.
    private func customerKey(_ item: HoaDonListDto) -> String {
        if let id = item.khachHangId, !id.isEmpty { return "kh:\(id)" }
        return "le:\(item.tenKhachHangText ?? "")|\(item.soDienThoaiText ?? "")"
    }

    /// Danh sách Công nợ lọc theo món/ghi chú có thể gộp NHIỀU khách khác nhau — thu hàng loạt (Tiền
    /// mặt/Chuyển khoản) chỉ có ý nghĩa khi toàn bộ `items` đang hiện là CÙNG 1 người, nếu không con
    /// số tổng cộng dồn chẳng còn nghĩa gì (tiền của khách A lẫn vào nợ khách B). Check này chạy
    /// TRƯỚC MỌI THỨ — trước cả khi mở alert nhập số tiền, chứ không chỉ trước lúc gọi API.
    private var isSingleCustomer: Bool {
        items.isEmpty || Set(items.map(customerKey)).count <= 1
    }

    private var multiCustomerNames: String {
        var seen = Set<String>()
        var names: [String] = []
        for item in items {
            let key = customerKey(item)
            guard seen.insert(key).inserted else { continue }
            names.append(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : "Khách lẻ")
        }
        return names.joined(separator: ", ")
    }

    /// Nợ phát sinh hôm nay — cùng logic gộp NgayNo với items, chỉ lọc thêm theo ngày hiện tại.
    private var todayText: String {
        let today = DateNavFormat.queryDate.string(from: Date())
        let total = items
            .filter { ($0.ngayNo ?? "").hasPrefix(today) }
            .reduce(0) { $0 + $1.conLai }
        return HoaDonFormatting.money(total)
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if showSendButton {
                    footerColumnButton(
                        icon: copiedFeedback ? "✅" : "🧾",
                        label: copiedFeedback ? "Đã copy" : "Gửi Bill",
                        color: .brandPrimary
                    ) {
                        Task { await copyBillImage() }
                    }
                } else {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                if showSendButton && !items.isEmpty {
                    footerColumnButton(icon: "💵", label: "Tiền mặt", color: .successColor) {
                        startPayAll(isCash: true)
                    }
                    .disabled(payingAll)
                } else {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                if showSendButton && !items.isEmpty {
                    footerColumnButton(icon: "💳", label: "Chuyển khoản", color: .brandPrimary) {
                        startPayAll(isCash: false)
                    }
                    .disabled(payingAll)
                } else {
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Hôm nay: \(todayText)")
                    .font(.caption2).foregroundColor(.dangerColor)
                Text(totalText)
                    .font(.headline)
                    .foregroundColor(.dangerColor)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .overlay { if payingAll { ProgressView() } }
        .alert(items.count > 1 ? "Xác nhận thanh toán toàn bộ nợ" : "Xác nhận thanh toán", isPresented: $showPayAllConfirm) {
            // Chỉ bắt gõ lại số tiền khi thu GỘP nhiều hoá đơn cùng lúc — rủi ro bấm nhầm hàng loạt.
            // Chỉ 1 đơn thì hỏi xác nhận thường là đủ, khớp cách xác nhận F1/F4 trong chi tiết đơn.
            if items.count > 1 {
                TextField("Nhập lại \(totalText)", text: $payAllInput)
                    .keyboardType(.numberPad)
            }
            Button("Xác nhận") { Task { await payAll() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            let ptText = payAllIsCash ? "tiền mặt" : "chuyển khoản"
            Text(items.count > 1
                 ? "Thu \(ptText) \(items.count) hoá đơn, tổng \(totalText). Nhập đúng tổng để thu hết, hoặc nhập số khách trả thiếu để hệ thống tự tìm tổ hợp hoá đơn cộng khớp đúng số đó."
                 : "Thu \(ptText) \(totalText) cho hoá đơn này?")
        }
        .alert("Không thể thu hàng loạt", isPresented: $showMultiCustomerError) {
            Button("OK") {}
        } message: {
            Text("Danh sách đang hiện gồm nhiều khách khác nhau (\(multiCustomerNames)) — chỉ thu hàng loạt được khi TẤT CẢ hoá đơn cùng 1 khách. Hãy tìm kiếm/lọc lại cho còn đúng 1 người rồi thử lại.")
        }
        .alert("Khớp tổ hợp nợ", isPresented: $showMatchConfirm) {
            Button("Xác nhận") { Task { await payMatchedSubset() } }
            Button("Huỷ", role: .cancel) { matchedSubset = nil }
        } message: {
            Text(matchConfirmMessage)
        }
        .alert("Kết quả", isPresented: Binding(
            get: { payAllResultMessage != nil },
            set: { if !$0 { payAllResultMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(payAllResultMessage ?? "")
        }
    }

    /// Nội dung alert xác nhận khớp tổ hợp — liệt kê tên khách + ngày nợ từng hoá đơn trong tổ hợp
    /// tìm được để nhân viên tự soát lại đúng người/đúng đơn trước khi bấm Xác nhận (danh sách Công
    /// nợ có thể gộp nhiều khách khác nhau khi lọc theo món/ghi chú — dù đã chặn ở bước check "cùng 1
    /// khách", vẫn hiện chi tiết để soát luôn cả trường hợp trùng tên/nhiều đơn dễ nhầm).
    private var matchConfirmMessage: String {
        guard let matchedSubset else { return "" }
        let ptText = payAllIsCash ? "tiền mặt" : "chuyển khoản"
        let danhSach = matchedSubset
            .sorted { ($0.ngayNo ?? "") < ($1.ngayNo ?? "") }
            .map { item in
                let ten = item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : "Khách lẻ"
                return "\(ten) (\(HoaDonFormatting.congNoTime(item.ngayNo)), \(HoaDonFormatting.money(item.conLai)))"
            }.joined(separator: "\n")
        let conLaiCount = items.count - matchedSubset.count
        let conLaiTotal = HoaDonFormatting.money(items.filter { i in !matchedSubset.contains { $0.id == i.id } }.reduce(0) { $0 + $1.conLai })
        return "Tìm thấy \(matchedSubset.count) hoá đơn cộng đúng \(payAllInput.filter(\.isNumber))đ:\n\(danhSach)\n\nThu \(ptText) đủ các hoá đơn này? Còn lại \(conLaiCount) hoá đơn, tổng \(conLaiTotal) vẫn nợ."
    }

    /// Tìm 1 tổ hợp trong `items` mà tổng conLai cộng lại khớp CHÍNH XÁC `target`, ƯU TIÊN hoá đơn CŨ
    /// vào giỏ trước. Thuật toán "lấp đầy giỏ" đơn giản: sắp hoá đơn theo `ngayNo` TĂNG DẦN (cũ →
    /// mới), rồi lần lượt LẤY từng hoá đơn cho vào giỏ (`stack`); nếu sau đó không dò ra đủ (dư âm/
    /// hết hoá đơn) thì GỠ hoá đơn vừa lấy ra, chuyển sang thử BỎ QUA nó rồi lấy hoá đơn kế tiếp. Thử
    /// "lấy" trước "bỏ qua" ở mỗi bước → tổ hợp tìm được luôn ưu tiên hoá đơn cũ nhất có thể.
    ///
    /// Chặn bằng ngân sách số bước dò (`stepsBudget`) thay vì giới hạn số lượng hoá đơn — dữ liệu
    /// thực tế (giá tiền đa dạng) dò ra rất nhanh dù danh sách dài; chỉ input cực đoan mới chạm ngân
    /// sách, khi đó coi như không dò được (an toàn, không sai kết quả, chỉ là chưa tìm ra).
    ///
    /// Nếu có NHIỀU tổ hợp cùng khớp đúng số tiền, chỉ lấy tổ hợp đầu tiên dò ra được — luôn hiện chi
    /// tiết tên/ngày/tiền để nhân viên tự xác nhận đúng ý trước khi thu, không coi đây là kết quả
    /// chắc chắn duy nhất đúng.
    private func findMatchingSubset(target: Int) -> [HoaDonListDto]? {
        guard target > 0, !items.isEmpty else { return nil }
        let oldestFirst = items.sorted { ($0.ngayNo ?? "") < ($1.ngayNo ?? "") }
        let amounts = oldestFirst.map { Int($0.conLai.rounded()) }

        var stack: [Int] = []
        var stepsBudget = 2_000_000

        func dfs(_ idx: Int, _ remaining: Int) -> Bool {
            stepsBudget -= 1
            if stepsBudget <= 0 { return false }
            if remaining == 0 { return true }
            if idx >= amounts.count || remaining < 0 { return false }

            // Thử LẤY hoá đơn idx vào giỏ trước (ưu tiên hoá đơn cũ).
            stack.append(idx)
            if dfs(idx + 1, remaining - amounts[idx]) { return true }
            stack.removeLast() // không khớp — gỡ ra

            // Không được thì thử BỎ QUA hoá đơn idx, sang hoá đơn kế tiếp.
            return dfs(idx + 1, remaining)
        }

        guard dfs(0, target) else { return nil }
        return stack.map { oldestFirst[$0] }
    }

    /// Bước kiểm tra ĐẦU TIÊN trước khi mở bất kỳ alert thu tiền nào — chặn hẳn nếu items đang hiện
    /// không cùng 1 khách (xem isSingleCustomer). Chỉ khi qua được check này mới cho gõ số tiền/chọn
    /// phương thức, tránh cộng dồn nợ của nhiều người khác nhau vào 1 lần thu.
    private func startPayAll(isCash: Bool) {
        guard isSingleCustomer else {
            showMultiCustomerError = true
            return
        }
        payAllIsCash = isCash
        payAllInput = ""
        showPayAllConfirm = true
    }

    private func footerColumnButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(icon).font(.footnote)
                Text(label).font(.system(size: 10).bold()).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    /// Yêu cầu gõ lại ĐÚNG tổng nợ đang hiện (so khớp số nguyên, bỏ dấu chấm/khoảng trắng) trước khi
    /// thu — chặn bấm nhầm hàng loạt hoá đơn cùng lúc, không có cách hoàn tác gộp nào ngoài rollback
    /// từng đơn một. Thu tuần tự từng hoá đơn qua F1 (giống bấm tay "Tiền mặt" trong chi tiết đơn).
    private func payAll() async {
        if items.count > 1 {
            let entered = payAllInput.filter(\.isNumber)
            let expected = Int(items.reduce(0) { $0 + $1.conLai }.rounded())
            guard !entered.isEmpty, let enteredValue = Int(entered) else {
                payAllResultMessage = "Vui lòng nhập số tiền hợp lệ."
                return
            }
            if enteredValue != expected {
                // Không khớp tổng — thử tìm tổ hợp hoá đơn bất kỳ cộng đúng số khách trả thiếu
                // (xem findMatchingSubset) trước khi báo huỷ hẳn.
                if let match = findMatchingSubset(target: enteredValue) {
                    matchedSubset = match
                    showMatchConfirm = true
                } else {
                    payAllResultMessage = "Số tiền nhập không khớp \(totalText), cũng không khớp tổ hợp nợ nào — đã huỷ, không có gì thay đổi."
                }
                return
            }
        }

        await executeThu(items)
    }

    /// Bấm Xác nhận trên alert "Khớp tổ hợp nợ" — chỉ thu đúng tổ hợp đã tìm thấy, KHÔNG đụng tới các
    /// hoá đơn còn lại (vẫn giữ nguyên trạng thái nợ).
    private func payMatchedSubset() async {
        guard let matchedSubset else { return }
        await executeThu(matchedSubset)
        self.matchedSubset = nil
    }

    /// Thu tuần tự từng hoá đơn trong `targets` qua F1/F4 (giống bấm tay "Tiền mặt"/"Chuyển khoản"
    /// trong chi tiết đơn) — dùng chung cho cả thu hết (payAll) lẫn thu đúng tổ hợp đã khớp tìm được.
    private func executeThu(_ targets: [HoaDonListDto]) async {
        payingAll = true
        var failCount = 0
        for item in targets {
            let result = await APIClient.shared.thuTien(
                hoaDonId: item.id, isCash: payAllIsCash, soTien: item.conLai,
                ten: item.tenKhachHangText ?? "Khách lẻ", khachHangId: item.khachHangId
            )
            if !result.success { failCount += 1 }
        }
        payingAll = false
        let ptText = payAllIsCash ? "tiền mặt" : "chuyển khoản"
        payAllResultMessage = failCount == 0
            ? "Đã thu \(ptText) \(targets.count) hoá đơn."
            : "Thu xong nhưng \(failCount)/\(targets.count) hoá đơn lỗi — kiểm tra lại."
    }

    /// Render toàn bộ danh sách (kể cả phần cần cuộn) thành 1 ảnh, copy vào clipboard để dán thẳng
    /// vào khung chat Zalo/Facebook — ImageRenderer (iOS 16+) vẽ ra ngoài màn hình nên không bị giới
    /// hạn bởi viewport như chụp màn hình thường. Kèm 1 mã QR duy nhất cho TỔNG nợ đang lọc (không
    /// gắn với 1 hoá đơn cụ thể vì có thể gộp nhiều đơn) — lấy qua Backend /api/HoaDon/bill-qr, dùng
    /// chung BankQrConfig với Desktop/Mobile (xem [[project_bank_qr_consolidation]]). addInfo tính
    /// hẳn trên Backend qua /api/HoaDon/gop-addinfo (BankQrConfig.BuildAddInfo là nguồn DUY NHẤT,
    /// không còn bản build song song bằng Swift nữa — tránh lệch format như vụ thiếu "SEVQR"
    /// 2026-08-23). Chỉ ghi mã hoá đơn đầu và cuối trong danh sách đang hiển thị (mới nhất đến cũ
    /// nhất), không liệt kê hết — tránh vượt giới hạn ký tự nội dung CK ngân hàng. `item.maHoaDon`
    /// (Backend tính sẵn) ưu tiên hơn tự cắt chuỗi id.
    private func copyBillImage() async {
        let snapshot = items
        let total = snapshot.reduce(0.0) { $0 + $1.conLai }
        let codes = snapshot.map { $0.maHoaDon?.isEmpty == false ? $0.maHoaDon! : BillTextBuilder.buildMaHoaDon($0.id) }
        let addInfo: String
        if let maDau = codes.first {
            let maCuoi = codes.last == maDau ? nil : codes.last
            addInfo = await APIClient.shared.getGopAddInfo(ten: label, maDau: maDau, maCuoi: maCuoi)
                ?? "SEVQR " + BillTextBuilder.toAsciiNoDiacritics("\(label) \(maDau)", upper: true)
        } else {
            addInfo = "SEVQR " + BillTextBuilder.toAsciiNoDiacritics(label, upper: true)
        }
        let qrData = await APIClient.shared.getBillQrImage(amount: total, addInfo: addInfo)
        let qrImage = qrData.flatMap { UIImage(data: $0) }

        let content = BillSnapshotView(items: snapshot, totalText: totalText, todayText: todayText, qrImage: qrImage, showName: showName)
            .frame(width: UIScreen.main.bounds.width)

        let renderer = ImageRenderer(content: content)
        renderer.scale = UIScreen.main.scale
        guard let uiImage = renderer.uiImage else { return }
        UIPasteboard.general.image = uiImage

        copiedFeedback = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedFeedback = false
        }
    }
}

/// Layout dùng riêng để render ảnh Gửi Bill Nợ — độc lập với List (List không rasterize hết nội
/// dung ngoài viewport), nền trắng cố định để ảnh dán vào chat luôn đọc được bất kể theme máy.
private struct BillSnapshotView: View {
    let items: [HoaDonListDto]
    let totalText: String
    let todayText: String
    let qrImage: UIImage?
    var showName: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                CongNoRowView(item: item, showName: showName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }
            VStack(spacing: 2) {
                HStack {
                    Spacer()
                    Text("Hôm nay: \(todayText)")
                        .font(.caption2).foregroundColor(.dangerColor)
                }
                HStack {
                    Text("Tổng nợ").font(.subheadline).foregroundColor(.textMuted)
                    Spacer()
                    Text(totalText).font(.headline).foregroundColor(.dangerColor)
                }
            }
            .padding(12)

            if let qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 200, height: 200)
                    .padding(.bottom, 16)
            }
        }
        .background(Color.white)
    }
}

/// Không đánh dấu private — ThongKeThangView (card "Tổng nợ hiện tại" → KhachHangNoDetailSheet) tái
/// dùng để layout khớp y hệt tab Công nợ, không phải sửa 2 nơi.
struct CongNoRowView: View {
    let item: HoaDonListDto
    /// Nil trong BillSnapshotView (ảnh render tĩnh để gửi bill — không cần tương tác).
    var onSelect: (() -> Void)? = nil
    /// false khi list đã lọc theo 1 khách (KhachHangNoDetailSheet) — tên lặp lại y hệt ở mọi dòng
    /// nên bỏ, nhường chỗ cho tóm tắt món lên làm dòng chính.
    var showName: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.dangerColor).frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                if showName {
                    Text(item.tenKhachHangText?.isEmpty == false ? item.tenKhachHangText! : (item.tenBan.map { "Bàn \($0)" } ?? "Khách lẻ"))
                        .font(.subheadline.bold())
                }
                if let mon = item.tenMonSummary, !mon.isEmpty {
                    Text(mon)
                        .font(showName ? .footnote : .subheadline.bold())
                        .foregroundColor(showName ? .textMuted : .primary)
                        .lineLimit(1)
                } else if !showName {
                    Text("Hoá đơn").font(.subheadline.bold())
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(HoaDonFormatting.congNoTime(item.ngayNo))
                    .font(.footnote).foregroundColor(.textMuted)
                Text(HoaDonFormatting.money(item.conLai)).font(.subheadline.bold()).foregroundColor(.dangerColor)
            }
        }
        .padding(12)
        .background(Color.dangerColor.pastelBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
    }
}
