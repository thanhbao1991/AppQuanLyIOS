import Photos
import SwiftUI
import UIKit
import Vision

/// Quét thư viện ảnh điện thoại 1 lần, mỗi ảnh tính 2 thứ (14/11/2026):
///  1. Vân tay (perceptual hash) — để "Tự dò ảnh món" tìm ảnh gốc nét khớp từng món menu.
///  2. Có người/mặt hay không (Vision) — để "Lọc ảnh không người" gom ảnh không người cho chủ xoá.
/// Cache theo localIdentifier (JSON ở Application Support) nên QUÉT LẠI ĐƯỢC (resume), mở lại không
/// tính lại từ đầu. PhotoKit isNetworkAccessAllowed đọc được cả ảnh iCloud chưa tải về máy.

// MARK: - Perceptual hash (pHash, DCT) — giống imagehash.phash
enum PhotoHash {
    static func pHash(_ image: UIImage) -> UInt64? {
        let n = 32
        guard let gray = grayPixels(image, size: n) else { return nil }
        let dct = dct2d(gray, n: n)
        var vals = [Float](); vals.reserveCapacity(64)
        for y in 0..<8 { for x in 0..<8 { vals.append(dct[y * n + x]) } }
        let median = vals.sorted()[vals.count / 2]
        var h: UInt64 = 0
        for (i, v) in vals.enumerated() where v > median { h |= (UInt64(1) << UInt64(i)) }
        return h
    }

    static func hamming(_ a: UInt64, _ b: UInt64) -> Int { (a ^ b).nonzeroBitCount }

    private static func grayPixels(_ image: UIImage, size n: Int) -> [Float]? {
        guard let cg = image.cgImage else { return nil }
        var px = [UInt8](repeating: 0, count: n * n)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8,
                                  bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        return px.map { Float($0) }
    }

    private static var cosCache = [Int: [Float]]()
    private static func cosMatrix(_ n: Int) -> [Float] {
        if let m = cosCache[n] { return m }
        var m = [Float](repeating: 0, count: n * n)
        for k in 0..<n {
            for x in 0..<n { m[k * n + x] = cos(Float.pi * Float(k) * (2 * Float(x) + 1) / (2 * Float(n))) }
        }
        cosCache[n] = m
        return m
    }

    private static func dct2d(_ p: [Float], n: Int) -> [Float] {
        let c = cosMatrix(n)
        var tmp = [Float](repeating: 0, count: n * n)
        for k in 0..<n {
            for x in 0..<n {
                var s: Float = 0
                for y in 0..<n { s += c[k * n + y] * p[y * n + x] }
                tmp[k * n + x] = s
            }
        }
        var out = [Float](repeating: 0, count: n * n)
        for k in 0..<n {
            for l in 0..<n {
                var s: Float = 0
                for x in 0..<n { s += tmp[k * n + x] * c[l * n + x] }
                out[k * n + l] = s
            }
        }
        return out
    }
}

// MARK: - Person detection (Vision, on-device)
enum PersonDetect {
    /// true nếu có mặt người HOẶC thân người. Thiên về GIỮ (lỗi -> coi như có người).
    static func hasPerson(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let faceReq = VNDetectFaceRectanglesRequest()
        let humanReq = VNDetectHumanRectanglesRequest()
        do { try handler.perform([faceReq, humanReq]) } catch { return true }
        let faces = faceReq.results?.count ?? 0
        let humans = humanReq.results?.count ?? 0
        return faces > 0 || humans > 0
    }
}

// MARK: - Kết quả 1 ảnh
private struct AssetInfo: Codable {
    var hash: UInt64
    var hasPerson: Bool
}

// MARK: - Matcher engine (dùng chung cho cả 2 tính năng)
@MainActor
final class PhotoMatcher: ObservableObject {
    @Published var total = 0
    @Published var scanned = 0
    @Published var isScanning = false
    @Published var authDenied = false
    @Published var ready = false

    private var info: [String: AssetInfo] = [:]     // localIdentifier -> {hash, hasPerson}
    private var assetMap: [String: PHAsset] = [:]
    private var allAssets: [PHAsset] = []
    private var cancelFlag = false

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("menuPhotoScan.json")
    }

    var noPersonCount: Int { info.values.filter { !$0.hasPerson }.count }

    func prepare() async {
        guard await requestAuth() else { authDenied = true; ready = false; return }
        loadCache()
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let res = PHAsset.fetchAssets(with: opts)
        var a = [PHAsset](); a.reserveCapacity(res.count)
        res.enumerateObjects { asset, _, _ in a.append(asset) }
        allAssets = a
        assetMap = Dictionary(a.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { x, _ in x })
        total = a.count
        scanned = info.keys.filter { assetMap[$0] != nil }.count
        ready = true
    }

    func scan() async {
        guard ready, !isScanning else { return }
        isScanning = true; cancelFlag = false
        let pending = allAssets.filter { info[$0.localIdentifier] == nil }
        var i = 0
        while i < pending.count && !cancelFlag {
            let batch = Array(pending[i..<min(i + 6, pending.count)])
            let results = await withTaskGroup(of: (String, AssetInfo).self) { group -> [(String, AssetInfo)] in
                for a in batch { group.addTask { await PhotoMatcher.scanAsset(a) } }
                var r = [(String, AssetInfo)]()
                for await x in group { r.append(x) }
                return r
            }
            for (id, v) in results { info[id] = v }
            scanned += results.count
            if (i / 6) % 20 == 0 { saveCache() }
            i += 6
        }
        saveCache()
        isScanning = false
    }

    func stop() { cancelFlag = true }
    func asset(_ id: String) -> PHAsset? { assetMap[id] }

    /// Ảnh khớp nhất cho 1 vân tay mẫu (bỏ hash 0 = ảnh lỗi).
    func best(for query: UInt64) -> (id: String, dist: Int)? {
        var bestId = ""; var bestDist = 65
        for (id, v) in info where v.hash != 0 {
            let d = PhotoHash.hamming(query, v.hash)
            if d < bestDist { bestDist = d; bestId = id }
        }
        return bestId.isEmpty ? nil : (bestId, bestDist)
    }

    /// Danh sách id ảnh KHÔNG người (mới nhất trước — allAssets đã sort giảm theo ngày).
    func noPersonIds() -> [String] {
        allAssets.compactMap { a in
            if let v = info[a.localIdentifier], !v.hasPerson { return a.localIdentifier }
            return nil
        }
    }

    /// Xoá các asset (iOS tự hiện xác nhận + vào Recently Deleted 30 ngày). Trả true nếu xong.
    func deleteAssets(_ ids: [String]) async -> Bool {
        let assets = ids.compactMap { assetMap[$0] }
        guard !assets.isEmpty else { return false }
        let ok: Bool = await withCheckedContinuation { cont in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            }, completionHandler: { success, _ in cont.resume(returning: success) })
        }
        if ok { for id in ids { info[id] = nil; assetMap[id] = nil } ; allAssets.removeAll { ids.contains($0.localIdentifier) }; saveCache() }
        return ok
    }

    // MARK: helpers
    private func requestAuth() async -> Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: return true
        case .notDetermined:
            return await PHPhotoLibrary.requestAuthorization(for: .readWrite) != .denied
        default: return false
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode([String: AssetInfo].self, from: data) else { return }
        info = dict
    }

    private func saveCache() {
        if let data = try? JSONEncoder().encode(info) { try? data.write(to: cacheURL, options: .atomic) }
    }

    private nonisolated static func scanAsset(_ a: PHAsset) async -> (String, AssetInfo) {
        let img = await requestThumb(a, size: 512)
        let hash = img.flatMap { PhotoHash.pHash($0) } ?? 0
        let person = img.map { PersonDetect.hasPerson($0) } ?? true   // lỗi -> coi như có người (giữ)
        return (a.localIdentifier, AssetInfo(hash: hash, hasPerson: person))
    }

    private nonisolated static func requestThumb(_ a: PHAsset, size: CGFloat) async -> UIImage? {
        await withCheckedContinuation { cont in
            let ro = PHImageRequestOptions()
            ro.deliveryMode = .fastFormat
            ro.resizeMode = .fast
            ro.isNetworkAccessAllowed = true
            ro.isSynchronous = false
            PHImageManager.default().requestImage(
                for: a, targetSize: CGSize(width: size, height: size),
                contentMode: .aspectFill, options: ro
            ) { image, _ in cont.resume(returning: image) }
        }
    }

    /// Ảnh gốc độ phân giải cao để upload.
    nonisolated static func fullImage(_ a: PHAsset) async -> UIImage? {
        await withCheckedContinuation { cont in
            let ro = PHImageRequestOptions()
            ro.deliveryMode = .highQualityFormat
            ro.resizeMode = .exact
            ro.isNetworkAccessAllowed = true
            ro.isSynchronous = false
            var resumed = false
            PHImageManager.default().requestImage(
                for: a, targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit, options: ro
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degraded && !resumed { resumed = true; cont.resume(returning: image) }
            }
        }
    }
}

// MARK: - Thumbnail dùng chung
struct AssetThumb: View {
    let assetId: String
    let matcher: PhotoMatcher
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.textMuted.opacity(0.12))
            .overlay {
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fill) }
            }
            .task {
                guard let asset = matcher.asset(assetId) else { return }
                let ro = PHImageRequestOptions()
                ro.deliveryMode = .opportunistic
                ro.resizeMode = .fast
                ro.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(
                    for: asset, targetSize: CGSize(width: 200, height: 200),
                    contentMode: .aspectFill, options: ro
                ) { result, _ in if let result { image = result } }
            }
    }
}
