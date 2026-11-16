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

    private var conLai: Int { model.items.count }

    private var dsMon: [SanPhamDto] {
        let k = Self.chuanHoa(timKiem)
        let ds = k.isEmpty ? model.sanPhams : model.sanPhams.filter { ($0.timKiem ?? Self.chuanHoa($0.ten)).contains(k) }
        return ds.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AsyncImage(url: URL(string: anh.url)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFit()
                        } else if phase.error != nil {
                            Text("Không tải được ảnh").foregroundColor(.textMuted).frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 360)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text("Ảnh này là món nào? Chọn món bên dưới rồi bấm Duyệt — ảnh sẽ thay ảnh menu của món đó. Còn \(conLai) ảnh chờ.")
                }

                Section {
                    ForEach(dsMon) { sp in
                        Button { daChon = sp } label: { dong(sp) }
                            .buttonStyle(.plain)
                    }
                } header: {
                    TextField("Tìm món", text: $timKiem)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textCase(nil)
                        .padding(.bottom, 4)
                }

                if let loi {
                    Text(loi).foregroundColor(.dangerColor)
                }
            }
            .listStyle(.insetGrouped)
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
                .padding(.top, 10)
                .padding(.bottom, 8)
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
        HStack(spacing: 12) {
            AsyncImage(url: sp.hinhAnh.flatMap(URL.init(string:))) { phase in
                if let img = phase.image { img.resizable().scaledToFill() } else { Color.appNen }
            }
            .frame(width: 36, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(sp.ten).font(.body)
                if let nhom = sp.tenNhomSanPham, !nhom.isEmpty {
                    Text(nhom).font(.caption).foregroundColor(.textMuted)
                }
            }
            Spacer()
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
