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
    let store: StoreLocation
    /// Mỗi phần tử: [vĩ độ, kinh độ, số đơn, doanh thu, seasonal] — mảng thô (không object) để
    /// file nhẹ, khớp định dạng `customers` bên data.json (xem build-customer-map.py).
    /// `seasonal`: 1 = khách ở kho/đại lý thu mua theo mùa vụ (chỉ hoạt động ~3 tháng/năm,
    /// nhận diện qua từ khoá địa chỉ "kho"/"đại lý"/"xưởng"/"sầu riêng"), 0 = dân địa phương.
    let customers: [[Double]]
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
    @State private var reloadToken = UUID()
    @State private var showLocal = true
    @State private var showSeasonal = true

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
                    NativeMapView(dataURL: mapDataURL, showLocal: showLocal, showSeasonal: showSeasonal,
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
        HStack(spacing: 8) {
            filterChip(title: "Dân địa phương", color: localColor, isOn: $showLocal)
            filterChip(title: "Kho / đại lý (mùa vụ)", color: seasonalColor, isOn: $showSeasonal)
            Spacer()
        }
        .padding(.horizontal, 12)
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
private let localUIColor = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 1)
private let seasonalUIColor = UIColor(red: 0x8E / 255, green: 0x2D / 255, blue: 0x8C / 255, alpha: 1)

// MARK: - Annotation types

private final class CustomerAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let orders: Int
    let isSeasonal: Bool
    init(coordinate: CLLocationCoordinate2D, orders: Int, isSeasonal: Bool) {
        self.coordinate = coordinate
        self.orders = orders
        self.isSeasonal = isSeasonal
    }
}

private final class StoreAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    var title: String? { "Chi nhánh hiện tại" }
}

// MARK: - UIViewRepresentable

private struct NativeMapView: UIViewRepresentable {
    let dataURL: URL
    let showLocal: Bool
    let showSeasonal: Bool
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
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        Task { await context.coordinator.load(into: map) }
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyFilter(on: uiView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NativeMapView
        private var maxOrders = 1
        private var allCustomerAnns: [CustomerAnnotation] = []

        init(parent: NativeMapView) { self.parent = parent }

        func load(into map: MKMapView) async {
            do {
                let (data, _) = try await URLSession.shared.data(from: parent.dataURL)
                let resp = try JSONDecoder().decode(MapDataResponse.self, from: data)

                allCustomerAnns = resp.customers.compactMap { row in
                    guard row.count >= 4 else { return nil }
                    let isSeasonal = row.count >= 5 && row[4] == 1
                    return CustomerAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: row[0], longitude: row[1]),
                        orders: Int(row[2]), isSeasonal: isSeasonal
                    )
                }
                maxOrders = max(1, allCustomerAnns.map(\.orders).max() ?? 1)

                let store = StoreAnnotation(coordinate: storeCoordinate)
                let circle = MKCircle(center: store.coordinate, radius: 2000)

                await MainActor.run {
                    applyFilter(on: map)
                    map.addAnnotation(store)
                    map.addOverlay(circle)
                    self.parent.onLoaded()
                }
            } catch {
                await MainActor.run { self.parent.onError(error.localizedDescription) }
            }
        }

        func applyFilter(on map: MKMapView) {
            let existing = map.annotations.compactMap { $0 as? CustomerAnnotation }
            map.removeAnnotations(existing)
            let filtered = allCustomerAnns.filter { ann in
                (ann.isSeasonal && parent.showSeasonal) || (!ann.isSeasonal && parent.showLocal)
            }
            map.addAnnotations(filtered)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster) as! MKMarkerAnnotationView
                let members = cluster.memberAnnotations.compactMap { $0 as? CustomerAnnotation }
                let isSeasonal = members.first?.isSeasonal ?? false
                view.markerTintColor = isSeasonal ? seasonalUIColor : localUIColor
                // Tong so DON (khong phai so khach) trong cum - khop cach doc "ghim cang dam =
                // cang nhieu don" cua ghim le (xem ham tint(for:)).
                view.glyphText = "\(members.reduce(0) { $0 + $1.orders })"
                view.canShowCallout = false
                // An "+N more" tu dong cua he thong (dem theo SO KHACH trong cum) - de lan voi
                // glyphText o tren vua doi sang SO DON, 2 con so khac nghia dung canh nhau se gay
                // hieu lam.
                view.titleVisibility = .hidden
                view.displayPriority = .defaultHigh
                return view
            }
            if let c = annotation as? CustomerAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "customer", for: c) as! MKMarkerAnnotationView
                view.clusteringIdentifier = c.isSeasonal ? "customer-seasonal" : "customer-local"
                view.canShowCallout = false
                view.displayPriority = .defaultLow
                view.markerTintColor = c.isSeasonal ? seasonalUIColor : tint(for: c.orders)
                view.glyphImage = nil
                view.titleVisibility = .hidden
                // Chấm nhỏ (không phải ghim to) cho hàng trăm điểm — scale marker xuống qua
                // transform, MKMarkerAnnotationView không có API đổi kích thước trực tiếp.
                view.transform = CGAffineTransform(scaleX: 0.55, y: 0.55)
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

        private func tint(for orders: Int) -> UIColor {
            let t = min(1, Double(orders) / Double(maxOrders))
            // Vàng nhạt (ít đơn) -> cam đậm (nhiều đơn).
            return UIColor(hue: 0.11 - 0.03 * t, saturation: 0.75, brightness: 0.9, alpha: 1)
        }
    }
}
