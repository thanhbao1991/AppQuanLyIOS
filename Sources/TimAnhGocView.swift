import Photos
import SwiftUI
import Vision

/// "Tìm ảnh gốc" — CHỈ cho các món server đánh dấu cần ảnh gốc (GET /api/SanPham/can-anh-goc; 16/11/2026 = 42 món
/// ly "Cảm ơn To" mà server chỉ còn bản nhỏ ≤600px). Khác "Tự dò ảnh món" (1 gợi ý/món theo pHash): ở đây mỗi món
/// lấy RỘNG theo pHash rồi xếp lại bằng Vision FeaturePrint (chịu được ảnh menu cũ đã bị cắt/nén) và đưa 3 ảnh
/// ứng viên để chủ quán tự chọn — bấm ảnh để so to, "Dùng ảnh này" thì up ảnh gốc (server lưu gốc, tạo bản nhỏ).
/// Món đã có ảnh gốc tự rơi khỏi danh sách server ở lần mở sau.
struct TimAnhGocView: View {
    @StateObject private var matcher = PhotoMatcher()
    @State private var items: [SanPhamDto] = []
    @State private var loadError = false
    @State private var cands: [String: [UngVien]] = [:]
    @State private var dangTim = false
    @State private var daTim = 0
    @State private var uploadingId: String?
    @State private var doneIds: Set<String> = []
    @State private var xem: XemThu?
    @State private var message: String?

    struct UngVien: Hashable { let assetId: String; let diem: Float }
    struct XemThu: Identifiable { let sp: SanPhamDto; let assetId: String; var id: String { sp.id + assetId } }

    private var conLai: [SanPhamDto] { items.filter { !doneIds.contains($0.id) } }

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
            } else if loadError {
                Text("Không tải được danh sách món. Thoát ra vào lại để thử lại.").foregroundColor(.textMuted).frame(maxHeight: .infinity)
            } else if conLai.isEmpty {
                Text(items.isEmpty ? "Đang tải danh sách món..." : "Đã có ảnh gốc cho tất cả các món 🎉")
                    .foregroundColor(.textMuted).frame(maxHeight: .infinity)
            } else {
                List { ForEach(conLai) { row($0) } }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color.appNen)
            }
        }
        .navigationTitle("Tìm ảnh gốc")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await setup() }
        .sheet(item: $xem) { x in xemSheet(x) }
        .alert("Thông báo", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        } message: { Text(message ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(conLai.count) món cần ảnh gốc · đã xong \(doneIds.count)").font(.subheadline.weight(.semibold))
            HStack {
                Text("Đã quét máy: \(matcher.scanned)/\(matcher.total)").font(.footnote).foregroundColor(.textMuted)
                Spacer()
                if matcher.isScanning {
                    Button("Dừng") { matcher.stop() }.font(.footnote)
                } else if matcher.scanned < matcher.total {
                    Button("Quét tiếp") { Task { await matcher.scan(); await timTatCa(lamLai: true) } }
                        .font(.footnote).disabled(!matcher.ready)
                }
            }
            if matcher.isScanning {
                ProgressView(value: Double(matcher.scanned), total: Double(max(1, matcher.total)))
            }
            Button { Task { await timTatCa(lamLai: true) } } label: {
                Text(dangTim ? "Đang so ảnh... \(daTim)/\(items.count)" : "Tìm ảnh gốc trong máy")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(dangTim || matcher.scanned == 0 || items.isEmpty)
            Text("Bấm vào ảnh ứng viên để so to với ảnh menu hiện tại, đúng thì bấm \"Dùng ảnh này\".")
                .font(.caption).foregroundColor(.textMuted)
        }
        .padding(12)
        .background(Color.appNen)
    }

    @ViewBuilder
    private func row(_ sp: SanPhamDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                anhServer(sp, size: 52)
                Text(sp.ten).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer()
                if uploadingId == sp.id { ProgressView() }
            }
            if let list = cands[sp.id] {
                if list.isEmpty {
                    Text("Không tìm thấy ảnh giống trong máy").font(.caption).foregroundColor(.textMuted)
                } else {
                    HStack(spacing: 8) {
                        ForEach(list, id: \.self) { c in
                            Button { xem = XemThu(sp: sp, assetId: c.assetId) } label: {
                                AssetThumb(assetId: c.assetId, matcher: matcher)
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if dangTim {
                Text("Đang tìm...").font(.caption).foregroundColor(.textMuted)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func anhServer(_ sp: SanPhamDto, size: CGFloat) -> some View {
        if let ha = sp.anhNho, let url = URL(string: ha) {
            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                Color.textMuted.opacity(0.1)
            }
            .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func xemSheet(_ x: XemThu) -> some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(x.sp.ten).font(.headline)
                HStack(alignment: .top, spacing: 10) {
                    VStack(spacing: 4) {
                        Text("Ảnh menu hiện tại").font(.caption).foregroundColor(.textMuted)
                        if let ha = x.sp.anhLon, let url = URL(string: ha) {
                            AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fit) } placeholder: { ProgressView() }
                                .frame(maxHeight: 360)
                        }
                    }
                    VStack(spacing: 4) {
                        Text("Ảnh trong máy").font(.caption).foregroundColor(.textMuted)
                        AnhLonTrongMay(assetId: x.assetId, matcher: matcher).frame(maxHeight: 360)
                    }
                }
                Button {
                    xem = nil
                    Task { await dung(x.sp, assetId: x.assetId) }
                } label: { Text("Dùng ảnh này").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                Button("Không phải") { xem = nil }
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    // MARK: logic
    private func setup() async {
        await matcher.prepare()
        guard let ids = await APIClient.shared.getSanPhamCanAnhGoc(),
              let list = await APIClient.shared.getSanPhamListOrNil(includeNgungBan: true) else { loadError = true; return }
        let set = Set(ids)
        items = list.filter { set.contains($0.id.lowercased()) }.sorted { $0.ten < $1.ten }
        if matcher.scanned > 0 { await timTatCa(lamLai: false) }
    }

    private func timTatCa(lamLai: Bool) async {
        guard !dangTim else { return }
        dangTim = true; daTim = 0
        defer { dangTim = false }
        for sp in items where !doneIds.contains(sp.id) {
            if !lamLai, cands[sp.id] != nil { daTim += 1; continue }
            cands[sp.id] = await timChoMon(sp)
            daTim += 1
        }
    }

    /// pHash lấy rộng 12 ảnh gần nhất (≤24 bit) → xếp lại bằng Vision FeaturePrint → 3 ảnh giống nhất.
    private func timChoMon(_ sp: SanPhamDto) async -> [UngVien] {
        guard let ha = sp.hinhAnh, let url = URL(string: ha),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let mau = UIImage(data: data), let h = PhotoHash.pHash(mau) else { return [] }
        let gan = matcher.nearest(for: h, k: 12, maxDist: 24)
        let assets: [(String, PHAsset)] = gan.compactMap { g in matcher.asset(g.id).map { (g.id, $0) } }
        guard !assets.isEmpty else { return [] }
        let xep = await Task.detached(priority: .userInitiated) { () -> [UngVien] in
            guard let fpMau = FeaturePrint.of(mau) else { return [] }
            var out: [UngVien] = []
            for (id, a) in assets {
                guard let img = await PhotoMatcher.requestThumb(a, size: 512),
                      let fp = FeaturePrint.of(img),
                      let d = FeaturePrint.distance(fpMau, fp) else { continue }
                out.append(UngVien(assetId: id, diem: d))
            }
            return out.sorted { $0.diem < $1.diem }
        }.value
        return Array(xep.prefix(3))
    }

    private func dung(_ sp: SanPhamDto, assetId: String) async {
        guard let asset = matcher.asset(assetId) else { return }
        uploadingId = sp.id
        defer { uploadingId = nil }
        guard let full = await PhotoMatcher.fullImage(asset) else {
            message = "Không lấy được ảnh gốc từ máy."
            return
        }
        let kq = full.menuUploadJPEG()
        guard let data = kq.data else { message = kq.loi ?? "Ảnh không dùng được."; return }
        let (url, msg) = await APIClient.shared.uploadSanPhamHinhAnh(id: sp.id, imageData: data, mimeType: "image/jpeg")
        if url != nil { doneIds.insert(sp.id) } else { message = msg ?? "Upload thất bại." }
    }
}

/// Vân tay ảnh của Vision — so 2 ảnh "cùng cảnh" kể cả khi 1 ảnh đã bị cắt/nén/thu nhỏ (pHash thì không chịu cắt).
enum FeaturePrint {
    static func of(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let cg = image.cgImage else { return nil }
        let req = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([req]) } catch { return nil }
        return req.results?.first as? VNFeaturePrintObservation
    }

    static func distance(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float? {
        var d: Float = 0
        do { try a.computeDistance(&d, to: b); return d } catch { return nil }
    }
}

/// Ảnh trong máy cỡ lớn (để so trong sheet) — tải iCloud nếu chưa có trên máy.
private struct AnhLonTrongMay: View {
    let assetId: String
    let matcher: PhotoMatcher
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) } else { ProgressView() }
        }
        .task {
            guard let a = matcher.asset(assetId) else { return }
            image = await PhotoMatcher.requestThumb(a, size: 1024)
        }
    }
}
