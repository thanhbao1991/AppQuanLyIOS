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

/// Bản đồ mật độ khách hàng quanh quán — dùng Apple MapKit THẬT qua UIKit `MKMapView` (không phải
/// SwiftUI `Map(annotationItems:)`) vì bản SwiftUI cũ dựng hàng trăm custom view riêng lẻ, không
/// tận dụng được MKAnnotationView gốc → lag rõ rệt so với Google Maps khi test thật trên máy
/// (phản hồi 2026-10-03). KHÔNG còn vẽ vòng tròn minh hoạ bán kính trên map (bỏ 2026-10-04, chỉ
/// còn dùng bán kính để LỌC ẩn/hiện qua slider, không vẽ ra).
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
    /// Ẩn mọi vị trí (khách/đối thủ) nằm trong bán kính quanh quán — mặc định BẬT (ẩn) vì mục đích
    /// chính của màn này là tìm khu vực TIỀM NĂNG MỞ RỘNG, khu lõi sát quán đã quá rõ không cần
    /// nhìn lại mỗi lần (yêu cầu 2026-10-03). Bán kính tự chỉnh qua slider (yêu cầu 2026-10-04),
    /// mặc định 2.2km — không còn vẽ vòng tròn minh hoạ trên map nữa (yêu cầu cùng ngày).
    @State private var hideWithin2km = true
    @State private var hideRadiusKm: Double = 2.2

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
                                  hideRadiusKm: hideRadiusKm,
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
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                Text("Ẩn trong bán kính \(String(format: "%.1f", hideRadiusKm))km quanh quán").font(.caption)
            }
            .toggleStyle(.switch)
            .tint(.brandPrimary)
            .padding(.horizontal, 12)

            if hideWithin2km {
                HStack(spacing: 8) {
                    Text("0.5").font(.caption2).foregroundColor(.textMuted)
                    Slider(value: $hideRadiusKm, in: 0.5...10, step: 0.1)
                        .tint(.brandPrimary)
                    Text("10").font(.caption2).foregroundColor(.textMuted)
                }
                .padding(.horizontal, 12)
            }
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
// Cam (29/10/2026) — tím cũ 8E2D8C khó phân biệt với xanh dân địa phương trên bản đồ.
private let seasonalColor = Color(red: 0xF0 / 255, green: 0x8A / 255, blue: 0x00 / 255)
private let competitorColor = Color(red: 0xB0 / 255, green: 0x30 / 255, blue: 0x30 / 255)
private let localUIColor = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 1)
private let seasonalUIColor = UIColor(red: 0xF0 / 255, green: 0x8A / 255, blue: 0x00 / 255, alpha: 1)
private let competitorUIColor = UIColor(red: 0xB0 / 255, green: 0x30 / 255, blue: 0x30 / 255, alpha: 1)

// MARK: - Annotation types

/// Mọi chấm khách vẽ trên 1 overlay duy nhất (29/10/2026) — trước đó ~600 MKAnnotationView riêng lẻ (displayPriority
/// .required) cộng với gỡ/thêm lại toàn bộ mỗi lần SwiftUI gọi updateUIView làm map ĐỨNG HẲN sau một lúc vuốt/zoom
/// liên tục (user phải thoát màn). Overlay chỉ là 1 renderer vẽ chấm tròn cỡ cố định trên màn hình, không có view nào.
private final class CustomerDotsOverlay: NSObject, MKOverlay {
    struct Dot { let point: MKMapPoint; let isSeasonal: Bool }
    let dots: [Dot]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(dots: [Dot]) {
        self.dots = dots
        let rect = dots.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1.point, size: MKMapSize(width: 1, height: 1))) }
        // Nới viền cho chấm ở rìa không bị cắt nửa; rỗng thì lấy quanh quán.
        boundingMapRect = (rect.isNull ? MKMapRect(origin: MKMapPoint(storeCoordinate), size: MKMapSize(width: 1, height: 1)) : rect)
            .insetBy(dx: -2000, dy: -2000)
        coordinate = storeCoordinate
    }
}

private final class CustomerDotsRenderer: MKOverlayRenderer {
    private let dots: [CustomerDotsOverlay.Dot]

    init(dotsOverlay: CustomerDotsOverlay) {
        dots = dotsOverlay.dots
        super.init(overlay: dotsOverlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        // Đường kính 8pt trên màn hình ở mọi mức zoom; hơi trong suốt để chỗ đông khách tự đậm màu hơn.
        let r = 4 / zoomScale
        let vung = mapRect.insetBy(dx: -r, dy: -r)
        for d in dots where vung.contains(d.point) {
            let p = point(for: d.point)
            context.setFillColor((d.isSeasonal ? seasonalUIColor : localUIColor).withAlphaComponent(0.6).cgColor)
            context.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
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
    let hideRadiusKm: Double
    let onLoaded: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.region = MKCoordinateRegion(center: storeCoordinate,
                                         span: MKCoordinateSpan(latitudeDelta: 0.09, longitudeDelta: 0.09))
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
        private var allCustomers: [(coordinate: CLLocationCoordinate2D, isSeasonal: Bool)] = []
        /// Bộ lọc lần vẽ trước — updateUIView bị SwiftUI gọi cả khi màn khác cập nhật, lọc không đổi thì không vẽ lại.
        private var boLocDaVe: String?
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

            allCustomers = customers.map {
                (CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.long), $0.seasonal)
            }
            allCompetitorAnns = competitors.map {
                CompetitorAnnotation(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon), name: $0.name)
            }

            let store = StoreAnnotation(coordinate: storeCoordinate)

            await MainActor.run {
                applyFilter(on: map)
                map.addAnnotation(store)
                self.parent.onLoaded()
            }
        }

        func applyFilter(on map: MKMapView) {
            let storeLocation = CLLocation(latitude: storeCoordinate.latitude, longitude: storeCoordinate.longitude)
            let radiusMeters = parent.hideRadiusKm * 1000
            func withinRadius(_ coord: CLLocationCoordinate2D) -> Bool {
                CLLocation(latitude: coord.latitude, longitude: coord.longitude).distance(from: storeLocation) < radiusMeters
            }

            let boLoc = "\(parent.showLocal)|\(parent.showSeasonal)|\(parent.showCompetitors)|\(parent.hideWithin2km)|\(parent.hideRadiusKm)|\(allCustomers.count)|\(allCompetitorAnns.count)"
            guard boLoc != boLocDaVe else { return }
            boLocDaVe = boLoc

            map.removeOverlays(map.overlays.filter { $0 is CustomerDotsOverlay })
            let dots = allCustomers.filter { c in
                let categoryOn = (c.isSeasonal && parent.showSeasonal) || (!c.isSeasonal && parent.showLocal)
                guard categoryOn else { return false }
                return !(parent.hideWithin2km && withinRadius(c.coordinate))
            }.map { CustomerDotsOverlay.Dot(point: MKMapPoint($0.coordinate), isSeasonal: $0.isSeasonal) }
            if !dots.isEmpty { map.addOverlay(CustomerDotsOverlay(dots: dots), level: .aboveRoads) }

            let existingCompetitors = map.annotations.compactMap { $0 as? CompetitorAnnotation }
            map.removeAnnotations(existingCompetitors)
            if parent.showCompetitors {
                let filteredCompetitors = allCompetitorAnns.filter { ann in
                    !(parent.hideWithin2km && withinRadius(ann.coordinate))
                }
                map.addAnnotations(filteredCompetitors)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let dots = overlay as? CustomerDotsOverlay { return CustomerDotsRenderer(dotsOverlay: dots) }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
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
    }
}
