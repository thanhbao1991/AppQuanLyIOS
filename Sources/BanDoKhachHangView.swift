import MapKit
import SwiftUI

/// Dữ liệu tải thẳng từ file tĩnh trên VPS (KHÔNG qua Backend API) — cùng nguồn với trang web
/// "Bản Đồ Khách Hàng" (api.denncoffee.com/map-f90702696b23/), build lại + đẩy lên mỗi tối 21h
/// bằng scripts/build-customer-map.py (xem BackupCode_Dropbox.ps1 trên máy dev). URL không qua
/// JWT (dữ liệu ẩn danh — không có tên/SĐT khách, chỉ toạ độ + số đơn + doanh thu), khớp cách
/// trang web đang phục vụ.
private let mapDataURL = URL(string: "https://api.denncoffee.com/map-f90702696b23/data.json")!
private let storeCoordinate = CLLocationCoordinate2D(latitude: 12.7095521, longitude: 108.3016576)

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

struct CandidateInfo: Identifiable {
    let id: Int
    let rank: Int
    let orders: Int
    let revenue: Double
    let distM: Double
    let sampleAddr: String?
}

/// Bản đồ mật độ khách hàng (App order) quanh quán — dùng Apple MapKit THẬT qua UIKit `MKMapView`
/// (không phải SwiftUI `Map(annotationItems:)`) vì bản SwiftUI cũ dựng ~700 custom view riêng lẻ
/// cho 615 khách + 72 điểm viền vòng tròn, không tận dụng được MKAnnotationView gốc/không gom cụm
/// → lag rõ rệt so với Google Maps khi test thật trên máy (phản hồi 2026-10-03). Bản UIKit này:
/// clustering tự động cho điểm khách (clusteringIdentifier, giống cách Apple/Google Maps gom cụm
/// hàng trăm điểm), vòng tròn 2km vẽ bằng MKCircle overlay thật (không còn giả lập bằng chấm rời).
struct BanDoKhachHangView: View {
    @State private var loading = true
    @State private var loadError: String?
    @State private var selectedCandidate: CandidateInfo?
    @State private var reloadToken = UUID()

    var body: some View {
        ZStack {
            if let loadError {
                VStack(spacing: 8) {
                    Text("Không tải được dữ liệu bản đồ").font(.headline)
                    Text(loadError).font(.caption).foregroundColor(.textMuted)
                    Button("Thử lại") { reloadToken = UUID() }
                        .buttonStyle(.borderedProminent).tint(.brandPrimary)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    NativeMapView(dataURL: mapDataURL, onLoaded: { loading = false; loadError = nil },
                                  onError: { loadError = $0; loading = false },
                                  onSelectCandidate: { selectedCandidate = $0 })
                        .frame(maxHeight: .infinity)
                    if let c = selectedCandidate {
                        candidateDetail(c)
                    }
                }
                if loading {
                    fullScreenLoading()
                }
            }
        }
        .id(reloadToken)
        .navigationTitle("Bản đồ khách hàng")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func candidateDetail(_ z: CandidateInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Khu vực tiềm năng #\(z.rank)").font(.subheadline.bold())
                Spacer()
                Button { selectedCandidate = nil } label: {
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
}

private func formatMoney(_ v: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = "."
    return (formatter.string(from: NSNumber(value: Int(v))) ?? "\(Int(v))") + " đ"
}

// MARK: - Annotation types

private final class CustomerAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let orders: Int
    init(coordinate: CLLocationCoordinate2D, orders: Int) {
        self.coordinate = coordinate
        self.orders = orders
    }
}

private final class CandidateAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let info: CandidateInfo
    init(coordinate: CLLocationCoordinate2D, info: CandidateInfo) {
        self.coordinate = coordinate
        self.info = info
    }
    var title: String? { "Khu vực tiềm năng #\(info.rank)" }
}

private final class StoreAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    var title: String? { "Chi nhánh hiện tại" }
}

// MARK: - UIViewRepresentable

private struct NativeMapView: UIViewRepresentable {
    let dataURL: URL
    let onLoaded: () -> Void
    let onError: (String) -> Void
    let onSelectCandidate: (CandidateInfo) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.region = MKCoordinateRegion(center: storeCoordinate,
                                         span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09))
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "customer")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "candidate")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "store")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        Task { await context.coordinator.load(into: map) }
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {}

    final class Coordinator: NSObject, MKMapViewDelegate {
        let parent: NativeMapView
        private var maxOrders = 1

        init(parent: NativeMapView) { self.parent = parent }

        func load(into map: MKMapView) async {
            do {
                let (data, _) = try await URLSession.shared.data(from: parent.dataURL)
                let resp = try JSONDecoder().decode(MapDataResponse.self, from: data)

                let customerAnns: [CustomerAnnotation] = resp.customers.compactMap { row in
                    guard row.count >= 3 else { return nil }
                    return CustomerAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: row[0], longitude: row[1]),
                        orders: Int(row[2])
                    )
                }
                maxOrders = max(1, customerAnns.map(\.orders).max() ?? 1)

                let candidateAnns: [CandidateAnnotation] = resp.candidates.enumerated().map { idx, c in
                    let info = CandidateInfo(id: idx, rank: idx + 1, orders: c.orders, revenue: c.revenue,
                                              distM: c.dist_m, sampleAddr: c.sample_addrs?.first)
                    return CandidateAnnotation(coordinate: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon), info: info)
                }

                let store = StoreAnnotation(coordinate: CLLocationCoordinate2D(latitude: resp.store.lat, longitude: resp.store.lon))
                let circle = MKCircle(center: store.coordinate, radius: 2000)

                await MainActor.run {
                    map.addAnnotations(customerAnns)
                    map.addAnnotations(candidateAnns)
                    map.addAnnotation(store)
                    map.addOverlay(circle)
                    self.parent.onLoaded()
                }
            } catch {
                await MainActor.run { self.parent.onError(error.localizedDescription) }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 1)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.canShowCallout = false
                view.displayPriority = .defaultHigh
                return view
            }
            if let c = annotation as? CustomerAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "customer", for: c) as! MKMarkerAnnotationView
                view.clusteringIdentifier = "customer"
                view.canShowCallout = false
                view.displayPriority = .defaultLow
                view.markerTintColor = tint(for: c.orders)
                view.glyphImage = nil
                view.titleVisibility = .hidden
                // Chấm nhỏ (không phải ghim to) cho 615 điểm — scale marker xuống qua transform,
                // MKMarkerAnnotationView không có API đổi kích thước trực tiếp.
                view.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
                return view
            }
            if let z = annotation as? CandidateAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "candidate", for: z) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(red: 0xDC / 255, green: 0x35 / 255, blue: 0x45 / 255, alpha: 1)
                view.glyphText = "\(z.info.rank)"
                view.canShowCallout = false
                view.displayPriority = .required
                view.transform = .identity
                return view
            }
            if annotation is StoreAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "store", for: annotation) as! MKMarkerAnnotationView
                view.markerTintColor = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 1)
                view.glyphImage = UIImage(systemName: "cup.and.saucer.fill")
                view.canShowCallout = true
                view.displayPriority = .required
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let z = view.annotation as? CandidateAnnotation else { return }
            parent.onSelectCandidate(z.info)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 0.7)
            renderer.lineWidth = 2
            renderer.fillColor = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 0.06)
            return renderer
        }

        private func tint(for orders: Int) -> UIColor {
            let t = min(1, Double(orders) / Double(maxOrders))
            // Vàng nhạt (ít đơn) -> cam đậm (nhiều đơn).
            return UIColor(hue: 0.11 - 0.03 * t, saturation: 0.75, brightness: 0.9, alpha: 1)
        }
    }
}
