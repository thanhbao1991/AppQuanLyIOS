import Photos
import SwiftUI

/// "Tự dò ảnh món" — quét thư viện ảnh điện thoại, với mỗi món (lấy ảnh menu hiện tại làm mẫu) gợi ý
/// ảnh gốc nét khớp nhất trong máy. Chủ quán bấm "Dùng" → app lấy ảnh gốc full-res, upload (server tự
/// lưu bản gốc + tạo bản nhỏ cho khách). Vào từ màn "Ảnh menu" > nút "Tự dò". Quét có cache nên resume.
struct TuDoAnhMonView: View {
    @StateObject private var matcher = PhotoMatcher()
    @State private var items: [SanPhamDto] = []
    @State private var suggest: [String: (assetId: String, dist: Int)] = [:]
    @State private var matching = false
    @State private var uploadingId: String?
    @State private var doneIds: Set<String> = []
    @State private var skipIds: Set<String> = []
    @State private var message: String?

    private var candidates: [SanPhamDto] {
        items
            .filter { $0.hinhAnh != nil && suggest[$0.id] != nil && !doneIds.contains($0.id) && !skipIds.contains($0.id) }
            .sorted { (suggest[$0.id]?.dist ?? 99) < (suggest[$1.id]?.dist ?? 99) }
    }

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
            } else if candidates.isEmpty {
                Text(matching ? "Đang tìm khớp..." : "Quét máy rồi bấm \"Tìm khớp\" để xem gợi ý.")
                    .foregroundColor(.textMuted).frame(maxHeight: .infinity)
            } else {
                List { ForEach(candidates) { row($0) } }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.appNen)
            }
        }
        .navigationTitle("Tự dò ảnh món")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await setup() }
        .alert("Thông báo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Đã quét máy: \(matcher.scanned)/\(matcher.total)").font(.subheadline)
                Spacer()
                if matcher.isScanning {
                    Button("Dừng") { matcher.stop() }
                } else {
                    Button(matcher.scanned < matcher.total ? "Quét tiếp" : "Quét lại") {
                        Task { await matcher.scan(); await runMatch() }
                    }.disabled(!matcher.ready)
                }
            }
            if matcher.isScanning {
                ProgressView(value: Double(matcher.scanned), total: Double(max(1, matcher.total)))
            }
            HStack(spacing: 10) {
                Button { Task { await runMatch() } } label: {
                    Text(matching ? "Đang tìm khớp..." : "Tìm khớp cho các món")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(matching || matcher.scanned == 0)
            }
            if candidates.contains(where: { (suggest[$0.id]?.dist ?? 99) <= 6 }) {
                Button("Áp tất cả khớp chắc (≤6)") { Task { await applyAllStrong() } }
                    .font(.footnote)
            }
        }
        .padding(12)
        .background(Color.appNen)
    }

    @ViewBuilder
    private func row(_ sp: SanPhamDto) -> some View {
        let s = suggest[sp.id]
        HStack(spacing: 10) {
            // Ảnh hiện tại (server, nhỏ)
            if let ha = sp.hinhAnh, let url = URL(string: ha) {
                AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                    Color.textMuted.opacity(0.1)
                }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            Image(systemName: "arrow.right").foregroundColor(.textMuted).font(.caption)
            // Ảnh gợi ý (gốc nét trong máy)
            if let s {
                AssetThumb(assetId: s.assetId, matcher: matcher)
                    .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(sp.ten).font(.subheadline).lineLimit(2)
                if let s {
                    Text(s.dist <= 6 ? "Khớp chắc" : (s.dist <= 12 ? "Có thể khớp" : "Khớp yếu"))
                        .font(.caption2)
                        .foregroundColor(s.dist <= 6 ? .green : (s.dist <= 12 ? .orange : .textMuted))
                }
            }
            Spacer()
            if uploadingId == sp.id {
                ProgressView().frame(width: 28, height: 28)
            } else {
                VStack(spacing: 6) {
                    Button("Dùng") { Task { await apply(sp) } }
                        .font(.caption).buttonStyle(.borderedProminent)
                    Button("Bỏ") { skipIds.insert(sp.id) }
                        .font(.caption2).foregroundColor(.textMuted)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: logic
    private func setup() async {
        if let list = await APIClient.shared.getSanPhamListOrNil() { items = list }
        await matcher.prepare()
        if matcher.scanned > 0 { await runMatch() }
    }

    private func runMatch() async {
        guard !matching else { return }
        matching = true
        defer { matching = false }
        for sp in items where sp.hinhAnh != nil && suggest[sp.id] == nil {
            guard let ha = sp.hinhAnh, let h = await Self.hashOfURL(ha) else { continue }
            if let b = matcher.best(for: h) { suggest[sp.id] = (assetId: b.id, dist: b.dist) }
        }
    }

    private func apply(_ sp: SanPhamDto) async {
        guard let s = suggest[sp.id], let asset = matcher.asset(s.assetId) else { return }
        uploadingId = sp.id
        defer { uploadingId = nil }
        guard let full = await PhotoMatcher.fullImage(asset),
              let data = full.resizedForMenuUpload().jpegData(compressionQuality: 0.85) else {
            message = "Không lấy được ảnh gốc từ máy."
            return
        }
        let (url, msg) = await APIClient.shared.uploadSanPhamHinhAnh(id: sp.id, imageData: data, mimeType: "image/jpeg")
        if url != nil { doneIds.insert(sp.id) } else { message = msg ?? "Upload thất bại." }
    }

    private func applyAllStrong() async {
        let strong = candidates.filter { (suggest[$0.id]?.dist ?? 99) <= 6 }
        for sp in strong { await apply(sp) }
    }

    private static func hashOfURL(_ urlStr: String) async -> UInt64? {
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        return PhotoHash.pHash(img)
    }
}
