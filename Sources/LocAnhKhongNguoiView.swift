import Photos
import SwiftUI

/// "Lọc ảnh không người" — quét thư viện (Vision nhận diện người/mặt), gom ảnh KHÔNG người cho chủ
/// quán chọn & xoá hàng loạt. Xoá qua PhotoKit → iOS tự hiện hộp xác nhận + đưa vào "Recently Deleted"
/// (giữ 30 ngày, khôi phục được). Dùng CHUNG cache quét với "Tự dò ảnh món" (quét 1 lần, 2 tính năng
/// cùng dùng). Vào từ màn "Ảnh menu" > nút "Lọc ảnh".
struct LocAnhKhongNguoiView: View {
    @StateObject private var matcher = PhotoMatcher()
    @State private var selected: Set<String> = []
    @State private var deleting = false
    @State private var confirmDelete = false
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 3)]
    private var ids: [String] { matcher.noPersonIds() }

    var body: some View {
        VStack(spacing: 0) {
            header
            if matcher.authDenied {
                VStack(spacing: 12) {
                    Text("Chưa cấp quyền truy cập ảnh").foregroundColor(.textMuted)
                    Button("Mở Cài đặt") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                }.frame(maxHeight: .infinity)
            } else if ids.isEmpty {
                Text(matcher.isScanning ? "Đang quét..." : "Chưa thấy ảnh 'không người'. Bấm Quét để dò.")
                    .foregroundColor(.textMuted).frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(ids, id: \.self) { cell($0) }
                    }
                    .padding(3)
                }
            }
            if !selected.isEmpty { deleteBar }
        }
        .navigationTitle("Lọc ảnh không người")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await matcher.prepare() }
        .confirmationDialog("Xoá \(selected.count) ảnh?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Xoá \(selected.count) ảnh", role: .destructive) { Task { await doDelete() } }
            Button("Huỷ", role: .cancel) {}
        } message: {
            Text("Ảnh sẽ vào \"Đã xoá gần đây\" (Recently Deleted) 30 ngày, khôi phục được. iOS sẽ hỏi xác nhận lần nữa.")
        }
        .alert("Thông báo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Đã quét: \(matcher.scanned)/\(matcher.total) · Không người: \(matcher.noPersonCount)")
                    .font(.footnote)
                Spacer()
                if matcher.isScanning {
                    Button("Dừng") { matcher.stop() }
                } else {
                    Button(matcher.scanned < matcher.total ? "Quét tiếp" : "Quét lại") {
                        Task { await matcher.scan() }
                    }.disabled(!matcher.ready)
                }
            }
            if matcher.isScanning {
                ProgressView(value: Double(matcher.scanned), total: Double(max(1, matcher.total)))
            }
            if !ids.isEmpty {
                HStack {
                    Button(selected.count == ids.count ? "Bỏ chọn hết" : "Chọn tất cả") {
                        selected = selected.count == ids.count ? [] : Set(ids)
                    }.font(.footnote)
                    Spacer()
                    Text("Đã chọn \(selected.count)").font(.footnote).foregroundColor(.textMuted)
                }
            }
        }
        .padding(12)
        .background(Color.appNen)
    }

    @ViewBuilder
    private func cell(_ id: String) -> some View {
        let isSel = selected.contains(id)
        AssetThumb(assetId: id, matcher: matcher)
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topTrailing) {
                Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSel ? .green : .white)
                    .background(Circle().fill(.black.opacity(0.25)))
                    .padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green, lineWidth: isSel ? 3 : 0))
            .onTapGesture {
                if isSel { selected.remove(id) } else { selected.insert(id) }
            }
    }

    private var deleteBar: some View {
        Button {
            confirmDelete = true
        } label: {
            if deleting {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Label("Xoá \(selected.count) ảnh đã chọn", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(deleting)
        .padding(12)
        .background(Color.appNen)
    }

    private func doDelete() async {
        deleting = true
        defer { deleting = false }
        let ok = await matcher.deleteAssets(Array(selected))
        if ok { selected.removeAll() } else { message = "Chưa xoá được (có thể bạn đã huỷ)." }
    }
}
