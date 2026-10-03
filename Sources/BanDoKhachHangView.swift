import MapKit
import SwiftUI

/// Dữ liệu tải thẳng từ file tĩnh trên VPS (KHÔNG qua Backend API) — cùng nguồn với trang web
/// "Bản Đồ Khách Hàng" (api.denncoffee.com/map-f90702696b23/), build lại + đẩy lên mỗi tối 21h
/// bằng scripts/build-customer-map.py (xem BackupCode_Dropbox.ps1 trên máy dev). URL không qua
/// JWT (dữ liệu ẩn danh — không có tên/SĐT khách, chỉ toạ độ + số đơn + doanh thu), khớp cách
/// trang web đang phục vụ.
private let mapDataURL = URL(string: "https://api.denncoffee.com/map-f90702696b23/data.json")!

private struct MapDataResponse: Decodable {
    struct StoreLocation: Decodable { let lat: Double; let lon: Double }
    struct Candidate: Decodable {
        let lat: Double, lon: Double, orders: Int, revenue: Double, dist_m: Double
        let sample_addrs: [String]?
    }
    let store: StoreLocation
    /// Mỗi phần tử: [vĩ độ, kinh độ, số đơn, doanh thu] — mảng thô (không object) để file nhẹ,
    /// khớp định dạng `customers` bên data.json (xem build-customer-map.py).
    let customers: [[Double]]
    let candidates: [Candidate]
}

private struct CustomerPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let orders: Int
    let revenue: Double
}

private struct CandidateZone: Identifiable {
    let id = UUID()
    let rank: Int
    let coordinate: CLLocationCoordinate2D
    let orders: Int
    let revenue: Double
    let distM: Double
    let sampleAddr: String?
}

/// Bản đồ mật độ khách hàng (App order) quanh quán — dùng Apple MapKit thật (native, không phải
/// ảnh nền baked như bản web) để cân nhắc nơi mở chi nhánh mới. Dữ liệu ẩn danh, tải từ file tĩnh
/// trên VPS, không gọi Backend API — xem comment mapDataURL ở trên.
struct BanDoKhachHangView: View {
    @State private var storeCoordinate: CLLocationCoordinate2D?
    @State private var customers: [CustomerPoint] = []
    @State private var candidates: [CandidateZone] = []
    @State private var ringPoints: [CLLocationCoordinate2D] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 12.7095521, longitude: 108.3016576),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var loading = true
    @State private var loadError: String?
    @State private var selectedCandidate: CandidateZone?

    var body: some View {
        ZStack {
            if loading {
                fullScreenLoading()
            } else if let loadError {
                VStack(spacing: 8) {
                    Text("Không tải được dữ liệu bản đồ").font(.headline)
                    Text(loadError).font(.caption).foregroundColor(.textMuted)
                    Button("Thử lại") { Task { await load() } }
                        .buttonStyle(.borderedProminent).tint(.brandPrimary)
                }
                .padding()
            } else {
                mapContent
            }
        }
        .navigationTitle("Bản đồ khách hàng")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var mapContent: some View {
        VStack(spacing: 0) {
            Map(coordinateRegion: $region, annotationItems: annotationItems) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    annotationView(for: item)
                }
            }
            .frame(maxHeight: .infinity)

            if let selectedCandidate {
                candidateDetail(selectedCandidate)
            }
        }
    }

    // Gộp 3 nguồn điểm (khách hàng, khu vực tiềm năng, vành đai 2km) vào 1 mảng annotation duy
    // nhất vì SwiftUI `Map(annotationItems:)` chỉ nhận 1 mảng Identifiable — tách enum theo loại
    // để annotationView(for:) vẽ khác nhau.
    private enum AnnotationKind: Identifiable {
        case customer(CustomerPoint)
        case candidate(CandidateZone)
        case store
        case ring(Int, CLLocationCoordinate2D)

        var id: String {
            switch self {
            case .customer(let c): return "c-\(c.id)"
            case .candidate(let c): return "z-\(c.id)"
            case .store: return "store"
            case .ring(let i, _): return "ring-\(i)"
            }
        }
        var coordinate: CLLocationCoordinate2D {
            switch self {
            case .customer(let c): return c.coordinate
            case .candidate(let c): return c.coordinate
            case .store: return CLLocationCoordinate2D(latitude: 12.7095521, longitude: 108.3016576)
            case .ring(_, let c): return c
            }
        }
    }

    private var annotationItems: [AnnotationKind] {
        var items: [AnnotationKind] = ringPoints.enumerated().map { .ring($0.offset, $0.element) }
        items.append(.store)
        items.append(contentsOf: customers.map { .customer($0) })
        items.append(contentsOf: candidates.map { .candidate($0) })
        return items
    }

    @ViewBuilder
    private func annotationView(for item: AnnotationKind) -> some View {
        switch item {
        case .ring:
            Circle().fill(Color.brandPrimary.opacity(0.55)).frame(width: 5, height: 5)
        case .store:
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.white, Color.brandPrimary)
                .background(Circle().fill(.white).frame(width: 14, height: 14))
        case .customer(let c):
            let t = intensity(for: c.orders)
            Circle()
                .fill(Color(hue: 0.08 + 0.08 * (1 - t), saturation: 0.75, brightness: 0.85))
                .frame(width: sizeFor(c.orders), height: sizeFor(c.orders))
                .overlay(Circle().stroke(.white, lineWidth: 0.5))
        case .candidate(let z):
            Button {
                selectedCandidate = (selectedCandidate?.id == z.id) ? nil : z
            } label: {
                ZStack {
                    Circle().fill(Color.dangerColor).frame(width: 24, height: 24)
                    Text("\(z.rank)").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
                }
                .overlay(Circle().stroke(.white, lineWidth: 2))
            }
        }
    }

    private func candidateDetail(_ z: CandidateZone) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Khu vực tiềm năng #\(z.rank)").font(.subheadline.bold())
                Spacer()
                Button {
                    selectedCandidate = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                }
            }
            Text("\(z.orders) đơn · \(formatMoney(z.revenue)) · cách quán \(String(format: "%.1f", z.distM / 1000)) km")
                .font(.caption).foregroundColor(.textMuted)
            if let addr = z.sampleAddr, !addr.isEmpty {
                Text(addr).font(.caption2).foregroundColor(.textMuted).lineLimit(2)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private func intensity(for orders: Int) -> Double {
        let maxOrders = customers.map(\.orders).max() ?? 1
        guard maxOrders > 0 else { return 0 }
        return min(1, Double(orders) / Double(maxOrders))
    }

    private func sizeFor(_ orders: Int) -> CGFloat {
        6 + CGFloat(intensity(for: orders).squareRoot()) * 10
    }

    private func formatMoney(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return (formatter.string(from: NSNumber(value: Int(v))) ?? "\(Int(v))") + " đ"
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: mapDataURL)
            let resp = try JSONDecoder().decode(MapDataResponse.self, from: data)
            storeCoordinate = CLLocationCoordinate2D(latitude: resp.store.lat, longitude: resp.store.lon)
            customers = resp.customers.compactMap { row in
                guard row.count >= 4 else { return nil }
                return CustomerPoint(
                    coordinate: CLLocationCoordinate2D(latitude: row[0], longitude: row[1]),
                    orders: Int(row[2]), revenue: row[3]
                )
            }
            candidates = resp.candidates.enumerated().map { idx, c in
                CandidateZone(
                    rank: idx + 1,
                    coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon),
                    orders: c.orders, revenue: c.revenue, distM: c.dist_m,
                    sampleAddr: c.sample_addrs?.first
                )
            }
            ringPoints = Self.circlePoints(center: resp.store, radiusMeters: 2000, count: 72)
            if let store = storeCoordinate {
                region = MKCoordinateRegion(center: store, span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09))
            }
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    /// 72 điểm viền vòng tròn bán kính cố định quanh quán — thay cho MKCircle overlay (API mới,
    /// cần iOS 17+ với SwiftUI `Map` bản mới; deployment target app này đang là iOS 16).
    private static func circlePoints(center: MapDataResponse.StoreLocation, radiusMeters: Double, count: Int) -> [CLLocationCoordinate2D] {
        let earthRadius = 6_371_000.0
        let latRad = center.lat * .pi / 180
        return (0..<count).map { i in
            let bearing = (2 * Double.pi / Double(count)) * Double(i)
            let lat2 = asin(sin(latRad) * cos(radiusMeters / earthRadius) + cos(latRad) * sin(radiusMeters / earthRadius) * cos(bearing))
            let lon2 = (center.lon * .pi / 180) + atan2(
                sin(bearing) * sin(radiusMeters / earthRadius) * cos(latRad),
                cos(radiusMeters / earthRadius) - sin(latRad) * sin(lat2)
            )
            return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
        }
    }
}
