import PhotosUI
import SwiftUI

/// 2 nút "Thêm từ ảnh" cạnh nút "+" thường trong tab Chi tiêu — chọn ảnh hoá đơn mua hàng (thư viện
/// hoặc chụp thẳng bằng camera), gửi lên Backend (Gemini Vision) đọc từng dòng + tự gợi ý map
/// NguyenLieu, rồi mở form duyệt/sửa trước khi lưu thật. Xem ReceiptParseService (Backend) cho phần
/// đọc ảnh + học mapping. Dùng chung 1 state (loading/lỗi/kết quả) vì chỉ 1 luồng chạy tại 1 thời điểm.
struct ReceiptImportButton: View {
    let date: Date
    let onSaved: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var loading = false
    @State private var loadError: String?
    @State private var parseResult: ReceiptParseResultDto?

    var body: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                iconOrSpinner("photo")
            }
            .disabled(loading)
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task { await handlePickedFromLibrary(item) }
            }

            Button {
                showCamera = true
            } label: {
                iconOrSpinner("camera")
            }
            .disabled(loading)
        }
        .foregroundColor(.brandPrimary)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                showCamera = false
                guard let image, let data = image.jpegData(compressionQuality: 0.85) else { return }
                Task { await handleImageData(data) }
            }
            .ignoresSafeArea()
        }
        .popupHost { host in
            host.alert("Đọc ảnh thất bại", isPresented: Binding(
                get: { loadError != nil },
                set: { if !$0 { loadError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(loadError ?? "")
            }
        }
        .sheet(item: $parseResult) { result in
            ReceiptReviewSheet(date: date, result: result) {
                onSaved()
            }
        }
    }

    @ViewBuilder
    private func iconOrSpinner(_ icon: String) -> some View {
        if loading {
            ProgressView().frame(width: 30, height: 30)
        } else {
            // SF Symbol (đổi lại 1/10 — quy ước: nút chỉ-có-icon (không kèm chữ) dùng SF Symbol để
            // ăn foregroundColor/tint, khác EmojiLabel/ActionButtonView (icon kèm chữ, giữ emoji).
            Image(systemName: icon).font(.system(size: 22))
        }
    }

    private func handlePickedFromLibrary(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            loadError = "Không đọc được ảnh đã chọn."
            return
        }
        await handleImageData(data)
    }

    private func handleImageData(_ data: Data) async {
        loading = true
        defer { loading = false }
        let (result, message) = await APIClient.shared.parseReceipt(imageData: data)
        if let result, !result.lines.isEmpty {
            parseResult = result
        } else {
            loadError = message ?? "Không đọc được dòng nào từ ảnh."
        }
    }
}

/// Bọc UIImagePickerController(sourceType: .camera) — PhotosPicker (SwiftUI) không hỗ trợ chụp
/// camera trực tiếp trước iOS 17, deployment target app đang là iOS 16.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}

extension ReceiptParseResultDto: Identifiable {
    var id: Int { lines.count }
}

struct ReceiptDraftLine: Identifiable {
    let id = UUID()
    let rawText: String
    var nguyenLieuId: String?
    var nguyenLieuTen: String?
    var fromLearnedAlias: Bool
    var soLuong: Double
    var donGia: Double
    var searchText: String = ""
    var included: Bool = true
    /// Chỉ luồng "Nhập từ Shopee" dùng: mỗi đơn có ngày giao + mã đơn riêng (lưu cột
    /// NguonShopeeOrderId, đánh dấu đã nhập), và tiêu đề nhóm hiện phía trên dòng đầu của mỗi đơn.
    /// Ảnh hoá đơn để nil — dùng ngày chung chọn ở đầu form.
    var ngay: Date? = nil
    var shopeeOrderId: String? = nil
    var nhom: String? = nil

    var thanhTien: Double { soLuong * donGia }
}

/// Form duyệt/sửa các dòng Gemini đọc được trước khi lưu thật — mỗi dòng bắt buộc chọn NguyenLieu
/// (kể cả khi Gemini đã gợi ý sẵn, người dùng vẫn đổi được), có thể bỏ dòng không muốn lưu. Lưu qua
/// POST /api/ChiTieuHangNgay/bulk kèm rawText từng dòng để Backend tự học mapping cho lần đọc ảnh sau.
/// Dùng chung cho "Nhập từ Shopee" (ShopeeImportView) — khi đó mỗi dòng mang ngày/ghi chú riêng của
/// đơn, lưu tách 1 lần bulk mỗi ngày.
struct ReceiptReviewSheet: View {
    let result: ReceiptParseResultDto
    var title = "Duyệt hoá đơn"
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    // Mặc định = ngày đang xem ở tab Chi tiêu (truyền vào qua init) nhưng cho sửa lại ngay trong màn
    // này — trước đây cố định theo ngày tab, hoá đơn chụp/nhập trễ (bill tháng về sau ngày đã xem)
    // phải thoát ra đổi ngày tab rồi mở lại từ đầu mới nhập được đúng ngày.
    @State private var selectedDate: Date
    @State private var lines: [ReceiptDraftLine]
    @State private var nguyenLieuList: [NguyenLieuDto] = []
    // Mặc định bật — luồng "Thêm từ ảnh"/camera hầu hết dùng cho bill nhà cung cấp cuối tháng, người
    // dùng vẫn tắt được nếu là hoá đơn lẻ trong ngày.
    @State private var billThang = true
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var warningAlertText: String?

    init(date: Date, result: ReceiptParseResultDto, onSaved: @escaping () -> Void) {
        _selectedDate = State(initialValue: date)
        self.result = result
        self.onSaved = onSaved
        _lines = State(initialValue: result.lines.map { l in
            ReceiptDraftLine(
                rawText: l.rawText,
                nguyenLieuId: l.suggestedNguyenLieuId,
                nguyenLieuTen: l.suggestedNguyenLieuTen,
                fromLearnedAlias: l.suggestedFromLearnedAlias,
                soLuong: l.soLuong,
                donGia: l.donGia
            )
        })
    }

    /// Luồng Shopee: dòng dựng sẵn (đã có ngày/ghi chú/nhóm theo từng đơn), Bill tháng mặc định tắt.
    init(title: String, lines: [ReceiptDraftLine], onSaved: @escaping () -> Void) {
        _selectedDate = State(initialValue: Date())
        self.result = ReceiptParseResultDto(lines: [], tongTrenPhieu: nil)
        self.title = title
        self.onSaved = onSaved
        _lines = State(initialValue: lines)
        _billThang = State(initialValue: false)
    }

    /// Mọi dòng tự mang ngày riêng (luồng Shopee) — ẩn ô chọn ngày chung.
    private var perLineDate: Bool { !lines.isEmpty && lines.allSatisfy { $0.ngay != nil } }

    private var includedLines: [ReceiptDraftLine] { lines.filter(\.included) }
    private var totalText: String {
        HoaDonFormatting.money(includedLines.reduce(0) { $0 + $1.thanhTien })
    }
    private var lechTong: Double? {
        guard let tong = result.tongTrenPhieu, tong > 0 else { return nil }
        let sum = includedLines.reduce(0) { $0 + $1.thanhTien }
        return abs(sum - tong) > 1 ? tong : nil
    }
    private var canSave: Bool {
        !includedLines.isEmpty && includedLines.allSatisfy { $0.nguyenLieuId != nil && $0.donGia > 0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if !perLineDate {
                        DatePicker("Ngày", selection: $selectedDate, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "vi_VN"))
                    }
                    Toggle("Bill tháng", isOn: $billThang)
                } footer: {
                    Text(perLineDate
                         ? "Mỗi đơn lưu theo ngày giao hàng của đơn đó. Bill tháng áp dụng chung."
                         : "Áp dụng chung cho tất cả dòng bên dưới.")
                }

                if let tong = lechTong {
                    Section {
                        Text("Tổng các dòng (\(totalText)) lệch với tổng trên phiếu (\(HoaDonFormatting.money(tong))). AI có thể đọc sai dòng hoặc giá — kiểm tra lại từng dòng trước khi lưu.")
                            .font(.footnote)
                            .foregroundColor(.dangerColor)
                    }
                }

                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    Section {
                        lineRow(binding(for: line))
                    } header: {
                        if let nhom = line.nhom, index == 0 || lines[index - 1].nhom != nhom {
                            Text(nhom)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundColor(.dangerColor)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }.disabled(saving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    Text(saving ? "Đang lưu..." : "Lưu (\(totalText))")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)
                .disabled(!canSave || saving)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                // Color(.systemBackground) thay vì .background(.bar) — xem HoaDonEditFormView.
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
        }
        .task { nguyenLieuList = await APIClient.shared.getNguyenLieu() }
        // Đã lưu thành công nhưng có dòng giá lệch lớn so với lần mua gần nhất — chỉ cảnh báo,
        // không chặn (xem AddExpenseSheet cùng cơ chế).
        .popupHost { host in
            host.alert("⚠️ Giá bất thường", isPresented: Binding(
                get: { warningAlertText != nil },
                set: { if !$0 { warningAlertText = nil } }
            )) {
                Button("Đã hiểu") { onSaved(); dismiss() }
            } message: {
                Text(warningAlertText ?? "")
            }
        }
    }

    /// Binding theo id thay vì theo vị trí — lưu xong từng nhóm (Shopee) thì dòng bị gỡ khỏi `lines`,
    /// binding theo index cũ sẽ trỏ lệch/văng.
    private func binding(for line: ReceiptDraftLine) -> Binding<ReceiptDraftLine> {
        Binding(
            get: { lines.first { $0.id == line.id } ?? line },
            set: { newValue in
                if let i = lines.firstIndex(where: { $0.id == line.id }) { lines[i] = newValue }
            }
        )
    }

    @ViewBuilder
    private func lineRow(_ line: Binding<ReceiptDraftLine>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.wrappedValue.rawText).font(.subheadline)
                if line.wrappedValue.nguyenLieuId == nil {
                    Text("Chưa khớp — chọn nguyên liệu").font(.caption).foregroundColor(.warningColor)
                } else if line.wrappedValue.fromLearnedAlias {
                    Text("Khớp từ lần trước").font(.caption).foregroundColor(.successColor)
                }
            }
            Spacer()
            Button {
                line.wrappedValue.included.toggle()
            } label: {
                Image(systemName: line.wrappedValue.included ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(line.wrappedValue.included ? .brandPrimary : .textMuted)
            }
        }

        if line.wrappedValue.included {
            nguyenLieuPicker(line)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Số lượng").font(.caption2).foregroundColor(.textMuted)
                    Stepper("\(line.wrappedValue.soLuong.formatted())", value: line.soLuong, in: 0.1...9999, step: 1)
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Đơn giá").font(.caption2).foregroundColor(.textMuted)
                    TextField("0", value: line.donGia, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 84)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Thành tiền").font(.caption2).foregroundColor(.textMuted)
                    Text(HoaDonFormatting.money(line.wrappedValue.thanhTien))
                        .font(.subheadline.bold())
                        .foregroundColor(.brandPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func nguyenLieuPicker(_ line: Binding<ReceiptDraftLine>) -> some View {
        if let ten = line.wrappedValue.nguyenLieuTen {
            HStack {
                Text(ten).bold()
                Spacer()
                Button("Đổi") {
                    line.wrappedValue.nguyenLieuId = nil
                    line.wrappedValue.nguyenLieuTen = nil
                }.font(.footnote)
            }
        } else {
            TextField("Tìm nguyên liệu...", text: line.searchText)
            if !line.wrappedValue.searchText.isEmpty {
                let matches = nguyenLieuList.filter { !$0.ngungSuDung && $0.ten.matchesSearch(line.wrappedValue.searchText) }.prefix(20)
                ForEach(matches) { nl in
                    Button {
                        line.wrappedValue.nguyenLieuId = nl.id
                        line.wrappedValue.nguyenLieuTen = nl.ten
                        line.wrappedValue.searchText = ""
                        if nl.giaNhap > 0 && line.wrappedValue.donGia <= 0 {
                            line.wrappedValue.donGia = nl.giaNhap
                        }
                    } label: {
                        Text(nl.ten)
                    }
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        // Ảnh hoá đơn: 1 nhóm theo ngày chung. Shopee: tách theo ngày giao của từng đơn (bulk chỉ nhận
        // 1 ngày/lần). Nhóm nào lưu xong thì gỡ khỏi form ngay — nhóm sau lỗi thì bấm Lưu lại không
        // bị nhập trùng nhóm trước.
        let groups = Dictionary(grouping: includedLines) { DateNavFormat.queryDate.string(from: $0.ngay ?? selectedDate) }
        var warnings: [String] = []
        var savedAny = false
        for key in groups.keys.sorted() {
            let groupLines = groups[key] ?? []
            let items = groupLines.compactMap { line -> ChiTieuHangNgayBulkItemRequest? in
                guard let nguyenLieuId = line.nguyenLieuId else { return nil }
                return ChiTieuHangNgayBulkItemRequest(
                    nguyenLieuId: nguyenLieuId,
                    ten: line.nguyenLieuTen,
                    soLuong: line.soLuong,
                    donGia: line.donGia,
                    thanhTien: line.thanhTien,
                    ghiChu: nil,
                    billThang: billThang,
                    rawText: line.rawText,
                    nguonShopeeOrderId: line.shopeeOrderId
                )
            }
            // NgayGio do server quyết định (VietnamTime.Now) — không gửi, để Backend tự set.
            let body = ChiTieuHangNgayBulkCreateRequest(ngay: key + "T00:00:00", ngayGio: nil, billThang: billThang, items: items)
            let result = await APIClient.shared.bulkCreateChiTieu(body)
            guard result.success else {
                saving = false
                errorMessage = result.message ?? "Không lưu được."
                if savedAny { onSaved() }
                return
            }
            savedAny = true
            warnings += result.warnings
            let savedIds = Set(groupLines.map(\.id))
            lines.removeAll { savedIds.contains($0.id) }
        }
        saving = false
        if !warnings.isEmpty {
            warningAlertText = warnings.joined(separator: "\n\n")
        } else {
            onSaved()
            dismiss()
        }
    }
}
