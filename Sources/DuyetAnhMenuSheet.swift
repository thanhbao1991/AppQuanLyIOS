import SwiftUI

/// Ảnh menu chờ gắn món — cổng tab Kê đặt TRƯỚC duyệt công thức (chủ quán 17/11/2026): còn ảnh thì mỗi lần vào tab
/// nhân viên chọn món cho 1 ảnh; hết ảnh mới quay lại duyệt công thức như cũ.
@MainActor
final class DuyetAnhMenuModel: ObservableObject {
    @Published var items: [AnhChoDuyetDto] = []
    @Published var sanPhams: [SanPhamDto] = []
    @Published var dangDuyet: AnhChoDuyetDto?
    /// Vừa bấm "Duyệt sau" — cổng tab vẫn cho vào. MainTabView đọc xong tự đặt lại false.
    var duyetSau = false

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
    let anh: AnhChoDuyetDto
    @ObservedObject var model: DuyetAnhMenuModel

    @Environment(\.dismiss) private var dismiss
    @State private var timKiem = ""
    @State private var daChon: SanPhamDto?
    @State private var xacNhan = false
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
                    Button {
                        model.duyetSau = true
                        dismiss()
                    } label: {
                        Text("Duyệt sau").fontWeight(.bold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandPrimary)
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
        }
    }

    private func dong(_ sp: SanPhamDto) -> some View {
        // 1 dòng/món (chủ quán 17/11: hiện được nhiều món nhất) — tên + nhóm cùng hàng, ảnh nhỏ.
        HStack(spacing: 10) {
            AsyncImage(url: sp.hinhAnh.flatMap(URL.init(string:))) { phase in
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
        dangLuu = true
        loi = nil
        let kq = await APIClient.shared.ganAnhChoDuyet(ma: anh.ma, sanPhamId: sp.id)
        if kq.success {
            _ = await model.load()
            dangLuu = false
            dismiss()
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
