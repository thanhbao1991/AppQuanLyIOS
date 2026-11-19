import SwiftUI

/// Ảnh menu chờ gắn món — cổng tab Kê đặt TRƯỚC duyệt công thức (chủ quán 17/11/2026): còn ảnh thì mỗi lần vào tab
/// nhân viên chọn món cho ảnh; phải duyệt HẾT ảnh mới được vào tab (không có "Duyệt sau"), duyệt xong 1 ảnh sheet tự
/// chuyển ảnh kế. Hết ảnh mới quay lại duyệt công thức như cũ.
@MainActor
final class DuyetAnhMenuModel: ObservableObject {
    @Published var items: [AnhChoDuyetDto] = []
    @Published var sanPhams: [SanPhamDto] = []
    @Published var dangDuyet: AnhChoDuyetDto?

    /// false = tải lỗi (cổng cho vào thẳng, không khoá nhân viên vì mạng).
    func load() async -> Bool {
        async let a = APIClient.shared.getAnhChoDuyetOrNil()
        async let s = APIClient.shared.getSanPhamListOrNil()
        let (anh, sp) = await (a, s)
        guard let anh, let sp else { return false }
        items = anh
        sanPhams = sp
        return true
    }
}

struct DuyetAnhMenuSheet: View {
    @State private var anh: AnhChoDuyetDto
    @ObservedObject var model: DuyetAnhMenuModel

    init(anh: AnhChoDuyetDto, model: DuyetAnhMenuModel) {
        _anh = State(initialValue: anh)
        self.model = model
    }

    @Environment(\.dismiss) private var dismiss
    @State private var timKiem = ""
    @State private var daChon: SanPhamDto?
    @State private var xacNhan = false
    @State private var xacNhanBo = false
    @State private var dangLuu = false
    @State private var loi: String?

    private var dsMon: [SanPhamDto] {
        let k = Self.chuanHoa(timKiem)
        let ds = k.isEmpty ? model.sanPhams : model.sanPhams.filter { ($0.timKiem ?? Self.chuanHoa($0.ten)).contains(k) }
        return ds.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                AsyncImage(url: URL(string: anh.url)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                        } else if phase.error != nil {
                            Text("Không tải được ảnh").foregroundColor(.textMuted).frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)

                ForEach(dsMon) { sp in
                    Button { daChon = sp } label: { dong(sp) }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                }

                if let loi {
                    Text(loi).foregroundColor(.dangerColor)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 34)
            // Ô tìm KHÔNG đặt trong header của List: mỗi lần lọc List dựng lại header → TextField mất focus,
            // bàn phím bật/tắt liên tục. .searchable nằm ở thanh điều hướng nên giữ focus ổn định.
            .searchable(text: $timKiem, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm món")
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Duyệt ảnh menu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandGradient, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Text("Còn \(model.items.count) ảnh")
                        .font(.subheadline).foregroundColor(.textMuted)
                        .fixedSize()
                    Button {
                        xacNhanBo = true
                    } label: {
                        Text("Ko dùng").fontWeight(.bold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.dangerColor)
                    .controlSize(.large)
                    .disabled(dangLuu)
                    Button {
                        xacNhan = true
                    } label: {
                        Text(dangLuu ? "Đang lưu..." : "Duyệt").fontWeight(.bold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .controlSize(.large)
                    .disabled(daChon == nil || dangLuu)
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 4)
                .background(Color(.systemBackground))
                .overlay(Divider(), alignment: .top)
            }
            .confirmationDialog("Dùng ảnh này cho \(daChon?.ten ?? "")?", isPresented: $xacNhan, titleVisibility: .visible) {
                Button("Duyệt") { Task { await duyet() } }
                Button("Không", role: .cancel) {}
            } message: {
                Text("Ảnh menu hiện tại của món sẽ được thay (ảnh cũ vẫn lưu bản sao trên máy chủ).")
            }
            .confirmationDialog("Không dùng ảnh này?", isPresented: $xacNhanBo, titleVisibility: .visible) {
                Button("Ko dùng", role: .destructive) { Task { await boAnh() } }
                Button("Huỷ", role: .cancel) {}
            } message: {
                Text("Ảnh sẽ bỏ khỏi danh sách chờ (máy chủ vẫn giữ bản sao).")
            }
        }
    }

    private func dong(_ sp: SanPhamDto) -> some View {
        // 1 dòng/món (chủ quán 17/11: hiện được nhiều món nhất) — tên + nhóm cùng hàng, ảnh nhỏ.
        HStack(spacing: 10) {
            AsyncImage(url: sp.anhNho.flatMap(URL.init(string:))) { phase in
                if let img = phase.image { img.resizable().scaledToFill() } else { Color.appNen }
            }
            .frame(width: 24, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(sp.ten).font(.body).lineLimit(1)
            Spacer(minLength: 4)
            if let nhom = sp.tenNhomSanPham, !nhom.isEmpty {
                Text(nhom).font(.caption).foregroundColor(.textMuted).lineLimit(1)
            }
            if daChon?.id == sp.id {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.brandPrimary).font(.title3)
            }
        }
        .contentShape(Rectangle())
    }

    private func duyet() async {
        guard let sp = daChon else { return }
        await xuLy { await APIClient.shared.ganAnhChoDuyet(ma: anh.ma, sanPhamId: sp.id) }
    }

    /// "Ko dùng" (chủ quán 17/11/2026: không phải ảnh nào cũng dùng) — server dời ảnh vào backup.
    private func boAnh() async {
        await xuLy { await APIClient.shared.boAnhChoDuyet(ma: anh.ma) }
    }

    /// Gọi API cho ảnh đang xem; xong thì sang ảnh kế, hết ảnh thì đóng (cổng cho vào tab).
    private func xuLy(_ goi: () async -> ActionResult) async {
        dangLuu = true
        loi = nil
        let kq = await goi()
        if kq.success {
            model.items.removeAll { $0.ma == anh.ma }   // tải lại lỗi cũng không hiện lại ảnh vừa xử lý
            _ = await model.load()
            dangLuu = false
            if let ke = model.items.first {
                anh = ke
                daChon = nil
                timKiem = ""
            } else {
                dismiss()
            }
        } else {
            dangLuu = false
            loi = kq.message ?? "Không lưu được, thử lại."
        }
    }

    /// Khớp chuẩn hoá TimKiem của server (không dấu, chữ thường) — như ô tìm món khi tạo đơn.
    static func chuanHoa(_ s: String) -> String {
        BillTextBuilder.toAsciiNoDiacritics(s, upper: false)
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .split(separator: " ").joined(separator: " ")
    }
}
