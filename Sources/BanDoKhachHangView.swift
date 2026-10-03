import MapKit
import SwiftUI

/// Đối thủ cạnh tranh vẫn đọc từ file tĩnh trên VPS (KHÔNG qua Backend API) — snapshot crawl thủ
/// công, không có trong DB. Khách hàng (customers) từ 2026-10-04 đọc thẳng từ DB qua
/// APIClient.getMapCustomers() (KhachHangAddresses.Lat/Long) thay vì crawl ngoài platform — xem
/// memory/session liên quan (gộp theo HoaDons chỉ đạt ~50% do tỷ lệ "bắt đơn" + KhachHangId của
/// đơn App trỏ vào shipper; gộp theo KhachHangAddresses đạt ~100%).
private let competitorsDataURL = URL(string: "https://api.denncoffee.com/map-f90702696b23/data.json")!
private let storeCoordinate = CLLocationCoordinate2D(latitude: 12.7095521, longitude: 108.3016576)

private struct MapDataResponse: Decodable {
    /// Danh sách quán trà sữa/cà phê đối thủ ở Krông Pắc — snapshot tĩnh crawl thủ công từ API
    /// khách hàng shippershipping.com (xem scripts/competitor_stores_krongpac.json), KHÔNG tự
    /// động làm mới.
    let competitors: [CompetitorLocation]?
}

private struct CompetitorLocation: Decodable {
    let name: String
    let lat: Double
    let lon: Double
}

/// Bản đồ mật độ khách hàng (App order) quanh quán — dùng Apple MapKit THẬT qua UIKit `MKMapView`
/// (không phải SwiftUI `Map(annotationItems:)`) vì bản SwiftUI cũ dựng ~700 custom view riêng lẻ
/// cho 615 khách + 72 điểm viền vòng tròn, không tận dụng được MKAnnotationView gốc → lag rõ rệt
/// so với Google Maps khi test thật trên máy (phản hồi 2026-10-03). Vòng tròn 2km vẽ bằng MKCircle
/// overlay thật (không còn giả lập bằng chấm rời).
/// KHÔNG gom cụm (đã thử clustering tự động rồi BỎ 2026-10-04) — số trên cụm đổi theo cách MapKit
/// gom lại mỗi lần zoom (quy luật hình học bình thường của thuật toán, không phải bug) khiến nhìn
/// như "sai số", gây khó chịu lặp lại nhiều lần khi dùng thật. Ưu tiên số LUÔN ĐÚNG hơn nhìn gọn.
struct BanDoKhachHangView: View {
    @State private var loading = true
    @State private var loadError: String?
    @State private var reloadToken = UUID()
    @State private var showLocal = true
    @State private var showSeasonal = true
    @State private var showCompetitors = true
    /// Ẩn mọi vị trí (khách/đối thủ) nằm trong vòng tròn 2km quanh quán — mặc định BẬT (ẩn) vì
    /// mục đích chính của màn này là tìm khu vực TIỀM NĂNG MỞ RỘNG, khu lõi sát quán đã quá rõ
    /// không cần nhìn lại mỗi lần (yêu cầu 2026-10-03).
    @State private var hideWithin2km = true

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
                    filterBar()
                    NativeMapView(showLocal: showLocal, showSeasonal: showSeasonal,
                                  showCompetitors: showCompetitors, hideWithin2km: hideWithin2km,
                                  onLoaded: { loading = false; loadError = nil },
                                  onError: { loadError = $0; loading = false })
                        .frame(maxHeight: .infinity)
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

    private func filterBar() -> some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "Dân địa phương", color: localColor, isOn: $showLocal)
                    filterChip(title: "Kho / đại lý (mùa vụ)", color: seasonalColor, isOn: $showSeasonal)
                    filterChip(title: "Đối thủ", color: competitorColor, isOn: $showCompetitors)
                }
                .padding(.horizontal, 12)
            }
            Toggle(isOn: $hideWithin2km) {
                Text("Ẩn trong bán kính 2km quanh quán").font(.caption)
            }
            .toggleStyle(.switch)
            .tint(.brandPrimary)
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func filterChip(title: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle().fill(isOn.wrappedValue ? color : Color.textMuted.opacity(0.3)).frame(width: 9, height: 9)
                Text(title).font(.caption.weight(.medium))
                    .foregroundColor(isOn.wrappedValue ? .primary : .textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                Capsule().fill(isOn.wrappedValue ? color.opacity(0.12) : Color.textMuted.opacity(0.08))
            )
            .overlay(Capsule().strokeBorder(isOn.wrappedValue ? color.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private let localColor = Color(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255)
private let seasonalColor = Color(red: 0x8E / 255, green: 0x2D / 255, blue: 0x8C / 255)
private let competitorColor = Color(red: 0xB0 / 255, green: 0x30 / 255, blue: 0x30 / 255)
private let localUIColor = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 1)
private let seasonalUIColor = UIColor(red: 0x8E / 255, green: 0x2D / 255, blue: 0x8C / 255, alpha: 1)
private let competitorUIColor = UIColor(red: 0xB0 / 255, green: 0x30 / 255, blue: 0x30 / 255, alpha: 1)

// MARK: - Annotation types

private final class CustomerAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let isSeasonal: Bool
    init(coordinate: CLLocationCoordinate2D, isSeasonal: Bool) {
        self.coordinate = coordinate
        self.isSeasonal = isSeasonal
    }
}

private final class StoreAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    var title: String? { "Chi nhánh hiện tại" }
}

private final class CompetitorAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let name: String
    init(coordinate: CLLocationCoordinate2D, name: String) {
        self.coordinate = coordinate
        self.name = name
    }
    var title: String? { name }
}

// MARK: - UIViewRepresentable

private struct NativeMapView: UIViewRepresentable {
    let showLocal: Bool
    let showSeasonal: Bool
    let showCompetitors: Bool
    let hideWithin2km: Bool
    let onLoaded: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.region = MKCoordinateRegion(center: storeCoordinate,
                                         span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09))
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "customer")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "store")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "competitor")
        Task { await context.coordinator.load(into: map) }
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyFilter(on: uiView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        private var allCustomerAnns: [CustomerAnnotation] = []
        private var allCompetitorAnns: [CompetitorAnnotation] = []

        init(parent: NativeMapView) { self.parent = parent }

        func load(into map: MKMapView) async {
            // Khach hang: tu DB (KhachHangAddresses.Lat/Long qua APIClient). Doi thu: van tu file
            // tinh tren VPS (khong co trong DB) - 2 nguon doc song song.
            async let customersTask = APIClient.shared.getMapCustomers()
            async let competitorsTask: [CompetitorLocation] = {
                guard let (data, _) = try? await URLSession.shared.data(from: competitorsDataURL),
                      let resp = try? JSONDecoder().decode(MapDataResponse.self, from: data) else { return [] }
                return resp.competitors ?? []
            }()
            let (customers, competitors) = await (customersTask, competitorsTask)

            if customers.isEmpty {
                await MainActor.run { self.parent.onError("Không tải được dữ liệu khách hàng.") }
                return
            }

            allCustomerAnns = customers.map {
                CustomerAnnotation(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.long), isSeasonal: $0.seasonal)
            }
            allCompetitorAnns = competitors.map {
                CompetitorAnnotation(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), name: $0.name)
            }

            let store = StoreAnnotation(coordinate: storeCoordinate)
            let circle = MKCircle(center: store.coordinate, radius: 2000)

            await MainActor.run {
                applyFilter(on: map)
                map.addAnnotation(store)
                map.addOverlay(circle)
                self.parent.onLoaded()
            }
        }

        func applyFilter(on map: MKMapView) {
            let storeLocation = CLLocation(latitude: storeCoordinate.latitude, longitude: storeCoordinate.longitude)
            func within2km(_ coord: CLLocationCoordinate2D) -> Bool {
                CLLocation(latitude: coord.latitude, longitude: coord.longitude).distance(from: storeLocation) < 2000
            }

            let existingCustomers = map.annotations.compactMap { $0 as? CustomerAnnotation }
            map.removeAnnotations(existingCustomers)
            let filtered = allCustomerAnns.filter { ann in
                let categoryOn = (ann.isSeasonal && parent.showSeasonal) || (!ann.isSeasonal && parent.showLocal)
                guard categoryOn else { return false }
                return !(parent.hideWithin2km && within2km(ann.coordinate))
            }
            map.addAnnotations(filtered)

            let existingCompetitors = map.annotations.compactMap { $0 as? CompetitorAnnotation }
            map.removeAnnotations(existingCompetitors)
            if parent.showCompetitors {
                let filteredCompetitors = allCompetitorAnns.filter { ann in
                    !(parent.hideWithin2km && within2km(ann.coordinate))
                }
                map.addAnnotations(filteredCompetitors)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let c = annotation as? CustomerAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "customer", for: c) as! MKMarkerAnnotationView
                // KHONG gom cum (clusteringIdentifier) nua - xem comment dau file.
                view.markerTintColor = c.isSeasonal ? seasonalUIColor : localUIColor
                view.glyphImage = nil
                view.canShowCallout = false
                view.titleVisibility = .hidden
                // .required (khong phai .defaultLow) - ep MapKit LUON hien du moi cham, khong tu
                // an bot ghim chong nhau de "giam nhieu" (he thong declutter rieng cua MapKit,
                // khac han clustering) - phan hoi 2026-10-04: zoom xa tuong nhu bi gom nhung thuc
                // ra la bi an bot.
                view.displayPriority = .required
                // Chấm nhỏ (không phải ghim to) cho hàng trăm điểm — scale marker xuống qua
                // transform, MKMarkerAnnotationView không có API đổi kích thước trực tiếp.
                view.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
                // Hơi trong suốt (không phải 100%) để khi zoom xa, nhiều chấm chồng lên nhau tự
                // nhiên đậm màu hơn — cho cảm giác mật độ mà KHÔNG cần in số (tránh lặp lại vấn đề
                // "số đổi theo zoom" đã bỏ gom cụm vì lý do này, phản hồi 2026-10-04).
                view.alpha = 0.6
                return view
            }
            if annotation is StoreAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "store", for: annotation) as! MKMarkerAnnotationView
                view.markerTintColor = localUIColor
                view.glyphImage = UIImage(systemName: "cup.and.saucer.fill")
                view.canShowCallout = true
                view.displayPriority = .required
                return view
            }
            if let comp = annotation as? CompetitorAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "competitor", for: comp) as! MKMarkerAnnotationView
                view.markerTintColor = competitorUIColor
                view.glyphImage = UIImage(systemName: "storefront.fill")
                // Khong gom cum - chi 81 quan, giu rieng le de bam xem ten tung quan.
                view.canShowCallout = true
                view.titleVisibility = .adaptive
                view.displayPriority = .defaultLow
                view.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                return view
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(circle: circle)
            renderer.strokeColor = localUIColor.withAlphaComponent(0.7)
            renderer.lineWidth = 2
            renderer.fillColor = localUIColor.withAlphaComponent(0.06)
            return renderer
        }
    }
}
