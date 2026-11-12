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
    /// Lớp tên đường (12/11/2026): bản đồ Apple ở Krông Pắc thiếu tên nhiều đường — server tự suy
    /// vị trí tên từ địa chỉ khách, nhân viên vẽ tay để bổ sung/sửa.
    @StateObject private var tenDuong = BanDoTenDuongModel()

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
                    if !tenDuong.dangVe { filterBar() }
                    NativeMapView(showLocal: showLocal, showSeasonal: showSeasonal,
                                  showCompetitors: showCompetitors, hideWithin2km: hideWithin2km,
                                  hideRadiusKm: hideRadiusKm,
                                  tenDuong: tenDuong,
                                  tenDuongSig: tenDuong.chuKy,
                                  onLoaded: { loading = false; loadError = nil },
                                  onError: { loadError = $0; loading = false })
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if tenDuong.dangVe { thanhVe() }
                        }
                        .overlay(alignment: .top) {
                            if let tb = tenDuong.thongBao {
                                Text(tb)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(Capsule().fill(.regularMaterial))
                                    .padding(.top, 10)
                                    .transition(.opacity)
                                    .task(id: tb) {
                                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                                        if tenDuong.thongBao == tb { tenDuong.thongBao = nil }
                                    }
                            }
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
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !tenDuong.dangVe {
                    Button {
                        tenDuong.batDauVe(nil)
                    } label: {
                        Image(systemName: "pencil.line")
                    }
                    .accessibilityLabel("Vẽ đường")
                }
            }
        }
        .task { await tenDuong.tai() }
        .confirmationDialog(tenDuong.chon?.ten ?? "", isPresented: Binding(
            get: { tenDuong.chon != nil },
            set: { if !$0 { tenDuong.chon = nil } }
        ), titleVisibility: .visible, presenting: tenDuong.chon) { d in
            Button(d.tuDong ? "Vẽ đường này" : "Vẽ lại đường này") { tenDuong.batDauVe(d) }
            if !d.tuDong {
                Button("Xoá nét vẽ tay", role: .destructive) { Task { await tenDuong.xoaNet(d) } }
            }
            Button("Đóng", role: .cancel) {}
        } message: { d in
            Text(d.tuDong
                 ? "Vị trí tự suy từ \(d.soKhach) địa chỉ khách — có thể lệch. Vẽ tay để chính xác hơn."
                 : "Đường do nhân viên vẽ tay.")
        }
        .sheet(isPresented: $tenDuong.hienChonTen) {
            ChonTenDuongSheet { id, ten in
                Task { await tenDuong.luu(tenDuongId: id, ten: ten) }
            }
        }
    }

    /// Thanh dưới cùng khi đang vẽ: chạm lên bản đồ để thêm điểm dọc con đường.
    private func thanhVe() -> some View {
        VStack(spacing: 10) {
            Text(tenDuong.veLai.map { "Vẽ lại: \($0.ten)" } ?? "Vẽ đường mới")
                .font(.subheadline.weight(.semibold))
            Text(tenDuong.diemVe.isEmpty
                 ? "Chạm lần lượt các điểm dọc theo con đường (chạm 1 điểm nếu chỉ muốn đặt tên khu vực)."
                 : "\(tenDuong.diemVe.count) điểm — chạm tiếp để nối dài.")
                .font(.caption).foregroundColor(.textMuted)
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Huỷ", role: .cancel) { tenDuong.huyVe() }
                    .buttonStyle(.bordered)
                Button {
                    if !tenDuong.diemVe.isEmpty { tenDuong.diemVe.removeLast() }
                } label: {
                    Label("Bỏ điểm cuối", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(tenDuong.diemVe.isEmpty)
                Button {
                    if let d = tenDuong.veLai {
                        Task { await tenDuong.luu(tenDuongId: d.id, ten: nil) }
                    } else {
                        tenDuong.hienChonTen = true
                    }
                } label: {
                    if tenDuong.dangLuu { ProgressView() } else { Text("Lưu").bold() }
                }
                .buttonStyle(.borderedProminent).tint(.brandPrimary)
                .disabled(tenDuong.diemVe.isEmpty || tenDuong.dangLuu)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)).shadow(radius: 6, y: 2))
        .padding(12)
    }

    private func filterBar() -> some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "Dân địa phương", color: localColor, isOn: $showLocal)
                    filterChip(title: "Kho / đại lý (mùa vụ)", color: seasonalColor, isOn: $showSeasonal)
                    filterChip(title: "Đối thủ", color: competitorColor, isOn: $showCompetitors)
                    filterChip(title: "Tên đường", color: streetColor, isOn: $tenDuong.hien)
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
private let streetColor = Color(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3A / 255)
private let streetUIColor = UIColor(red: 0x3A / 255, green: 0x3A / 255, blue: 0x3A / 255, alpha: 1)
/// Nét vẽ tay — màu thương hiệu (xanh lục đậm) để phân biệt với đường của Apple.
private let streetDrawnUIColor = UIColor(red: 0x1B / 255, green: 0x6B / 255, blue: 0x5F / 255, alpha: 1)
private let drawingUIColor = UIColor.systemRed

// MARK: - Tên đường

/// Trạng thái lớp tên đường + chế độ vẽ. Không đánh dấu @MainActor cả lớp để Coordinator (UIKit,
/// không cô lập actor) đọc/ghi được thuộc tính đồng bộ — mọi chỗ dùng đều chạy trên main thread;
/// các hàm async gọi API thì đánh dấu @MainActor riêng.
final class BanDoTenDuongModel: ObservableObject {
    @Published var duongs: [MapTenDuongDto] = []
    @Published var hien = true
    @Published var dangVe = false
    @Published var diemVe: [CLLocationCoordinate2D] = []
    /// Đang vẽ lại 1 đường có sẵn (lưu thẳng theo id, không hỏi tên).
    @Published var veLai: MapTenDuongDto?
    /// Nhãn vừa chạm — mở hộp chọn Vẽ lại/Xoá nét.
    @Published var chon: MapTenDuongDto?
    @Published var hienChonTen = false
    @Published var dangLuu = false
    @Published var thongBao: String?

    /// Thay đổi khi cần vẽ lại lớp tên đường/nét đang vẽ — truyền vào NativeMapView để SwiftUI gọi updateUIView.
    var chuKy: String { chuKyDuong + "#" + chuKyVe }

    /// Lớp nhãn/nét đã lưu — KHÔNG gồm điểm đang vẽ, để mỗi lần chạm thêm điểm không phải gỡ/thêm lại
    /// hàng chục nhãn (nhấp nháy).
    var chuKyDuong: String {
        "\(hien)|\(dangVe)|\(veLai?.id ?? "")|"
            + duongs.map { "\($0.id)\($0.tuDong)\($0.diem.count)\($0.diem.first?.first ?? 0)" }.joined()
    }

    var chuKyVe: String {
        "\(dangVe)|\(diemVe.count)|\(diemVe.last.map { "\($0.latitude),\($0.longitude)" } ?? "")"
    }

    @MainActor
    func tai() async {
        if let d = await APIClient.shared.getMapTenDuong() { duongs = d }
    }

    func batDauVe(_ duong: MapTenDuongDto?) {
        veLai = duong
        diemVe = []
        dangVe = true
    }

    func huyVe() {
        dangVe = false
        diemVe = []
        veLai = nil
    }

    @MainActor
    func luu(tenDuongId: String?, ten: String?) async {
        guard !diemVe.isEmpty else { return }
        dangLuu = true
        let r = await APIClient.shared.luuDuongVe(LuuDuongVeRequest(
            tenDuongId: tenDuongId, ten: ten,
            diem: diemVe.map { [$0.latitude, $0.longitude] }))
        dangLuu = false
        if r.success {
            huyVe()
            await tai()
            TenDuongCache.shared.lamMoi()
        }
        thongBao = r.message ?? (r.success ? "Đã lưu đường." : "Lưu thất bại.")
    }

    @MainActor
    func xoaNet(_ duong: MapTenDuongDto) async {
        let r = await APIClient.shared.luuDuongVe(LuuDuongVeRequest(tenDuongId: duong.id, ten: nil, diem: []))
        if r.success { await tai() }
        thongBao = r.message ?? (r.success ? "Đã xoá nét vẽ." : "Xoá thất bại.")
    }
}

/// Chọn tên cho nét vừa vẽ: tìm trong danh sách tên đường sẵn có, hoặc thêm tên mới.
private struct ChonTenDuongSheet: View {
    let onChon: (_ id: String?, _ ten: String?) -> Void
    @ObservedObject private var cache = TenDuongCache.shared
    @State private var tim = ""
    @Environment(\.dismiss) private var dismiss

    private var ketQua: [TenDuongDto] {
        let q = tim.boDauTimKiem
        let ds = cache.items.sorted { $0.ten.localizedCompare($1.ten) == .orderedAscending }
        return q.isEmpty ? ds : ds.filter { $0.ten.boDauTimKiem.contains(q) }
    }

    private var tenMoi: String { tim.trimmingCharacters(in: .whitespaces) }
    private var trungTen: Bool { cache.items.contains { $0.ten.boDauTimKiem == tenMoi.boDauTimKiem } }

    var body: some View {
        NavigationStack {
            List {
                if !tenMoi.isEmpty && !trungTen {
                    Button {
                        onChon(nil, tenMoi)
                        dismiss()
                    } label: {
                        Label("Thêm tên mới “\(tenMoi)”", systemImage: "plus.circle.fill")
                    }
                }
                ForEach(ketQua) { d in
                    Button(d.ten) {
                        onChon(d.id, nil)
                        dismiss()
                    }
                    .foregroundColor(.primary)
                }
            }
            .searchable(text: $tim, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm hoặc nhập tên đường")
            .navigationTitle("Tên đường này")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() } }
            }
            .onAppear { cache.ensureLoaded() }
        }
    }
}

private extension String {
    /// Bỏ dấu + chữ thường để tìm tên đường ("giai phong" khớp "Giải Phóng").
    var boDauTimKiem: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "vi_VN"))
            .replacingOccurrences(of: "đ", with: "d")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Nét vẽ tay đã lưu.
private final class TenDuongPolyline: MKPolyline {}
/// Nét đang vẽ dở.
private final class DuongDangVePolyline: MKPolyline {}

private final class TenDuongAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let duong: MapTenDuongDto
    init(coordinate: CLLocationCoordinate2D, duong: MapTenDuongDto) {
        self.coordinate = coordinate
        self.duong = duong
    }
    var title: String? { duong.ten }
}

private final class DiemVeAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    init(coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
}

/// Nhãn chữ nhỏ nền trắng, giống chữ tên đường trên bản đồ. MapKit tự ẩn nhãn chồng nhau (collision).
private final class TenDuongLabelView: MKAnnotationView {
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        addSubview(label)
        collisionMode = .rectangle
        canShowCallout = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var annotation: MKAnnotation? {
        didSet { capNhat() }
    }

    func capNhat() {
        guard let a = annotation as? TenDuongAnnotation else { return }
        label.text = a.duong.ten
        label.textColor = a.duong.tuDong ? streetUIColor : streetDrawnUIColor
        label.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        let size = label.intrinsicContentSize
        let w = size.width + 8, h = size.height + 4
        label.frame = CGRect(x: 0, y: 0, width: w, height: h)
        frame = CGRect(x: 0, y: 0, width: w, height: h)
        centerOffset = .zero
        // Đường vẽ tay ưu tiên hiện hơn nhãn tự suy khi chồng nhau.
        displayPriority = a.duong.tuDong ? .defaultLow : .defaultHigh
        zPriority = .min
    }
}

/// Vị trí đặt nhãn dọc đường: 1 nhãn ở giữa, đường dài thì thêm nhãn mỗi ~700m để kéo bản đồ tới
/// đoạn nào cũng thấy tên.
private func viTriNhan(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
    guard coords.count >= 2 else { return coords }
    let pts = coords.map { MKMapPoint($0) }
    var tichLuy: [Double] = [0]
    for i in 1..<pts.count { tichLuy.append(tichLuy[i - 1] + pts[i - 1].distance(to: pts[i])) }
    let tong = tichLuy.last ?? 0
    guard tong > 0 else { return [coords[0]] }
    let n = max(1, Int(tong / 700))
    return (0..<n).map { k in
        let d = (Double(k) + 0.5) * tong / Double(n)
        var i = 1
        while i < tichLuy.count - 1 && tichLuy[i] < d { i += 1 }
        let doan = tichLuy[i] - tichLuy[i - 1]
        let t = doan > 0 ? (d - tichLuy[i - 1]) / doan : 0
        let p = MKMapPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * t,
                           y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * t)
        return p.coordinate
    }
}

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
    let tenDuong: BanDoTenDuongModel
    /// Chỉ để SwiftUI thấy thay đổi và gọi updateUIView khi lớp tên đường/nét đang vẽ đổi.
    let tenDuongSig: String
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
        map.register(TenDuongLabelView.self, forAnnotationViewWithReuseIdentifier: "tenDuong")
        map.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "diemVe")
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.chamBanDo(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        Task { await context.coordinator.load(into: map) }
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyFilter(on: uiView)
        context.coordinator.applyTenDuong(on: uiView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeMapView
        private var allCustomers: [(coordinate: CLLocationCoordinate2D, isSeasonal: Bool)] = []
        /// Bộ lọc lần vẽ trước — updateUIView bị SwiftUI gọi cả khi màn khác cập nhật, lọc không đổi thì không vẽ lại.
        private var boLocDaVe: String?
        private var allCompetitorAnns: [CompetitorAnnotation] = []
        private var tenDuongDaVe: String?
        private var netVeDaVe: String?

        init(parent: NativeMapView) { self.parent = parent }

        // MARK: Tên đường

        func applyTenDuong(on map: MKMapView) {
            let model = parent.tenDuong
            if model.chuKyDuong != tenDuongDaVe {
                tenDuongDaVe = model.chuKyDuong
                veLopDuong(on: map, model: model)
            }
            if model.chuKyVe != netVeDaVe {
                netVeDaVe = model.chuKyVe
                veNetDangVe(on: map, model: model)
            }
        }

        private func veLopDuong(on map: MKMapView, model: BanDoTenDuongModel) {
            map.removeOverlays(map.overlays.filter { $0 is TenDuongPolyline })
            map.removeAnnotations(map.annotations.filter { $0 is TenDuongAnnotation })

            // Đang vẽ thì vẫn hiện tên đường để vẽ cho khớp, chỉ bỏ đường đang được vẽ lại.
            if model.hien || model.dangVe {
                for d in model.duongs where d.id != model.veLai?.id {
                    let coords = d.diem.compactMap { p -> CLLocationCoordinate2D? in
                        p.count == 2 ? CLLocationCoordinate2D(latitude: p[0], longitude: p[1]) : nil
                    }
                    guard !coords.isEmpty else { continue }
                    // Tự suy: CHỈ đặt nhãn — điểm là nhà khách chứ không phải tim đường, vẽ nét sẽ
                    // cắt ngang dãy nhà (đã thử trên dữ liệu thật 12/11). Bản đồ Apple đã có hình đường.
                    if !d.tuDong && coords.count >= 2 {
                        map.addOverlay(TenDuongPolyline(coordinates: coords, count: coords.count), level: .aboveRoads)
                    }
                    map.addAnnotations(viTriNhan(coords).map { TenDuongAnnotation(coordinate: $0, duong: d) })
                }
            }
        }

        private func veNetDangVe(on map: MKMapView, model: BanDoTenDuongModel) {
            map.removeOverlays(map.overlays.filter { $0 is DuongDangVePolyline })
            map.removeAnnotations(map.annotations.filter { $0 is DiemVeAnnotation })
            if model.dangVe {
                let coords = model.diemVe
                if coords.count >= 2 {
                    map.addOverlay(DuongDangVePolyline(coordinates: coords, count: coords.count), level: .aboveLabels)
                }
                map.addAnnotations(coords.map { DiemVeAnnotation(coordinate: $0) })
            }
        }

        @objc func chamBanDo(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, parent.tenDuong.dangVe, let map = g.view as? MKMapView else { return }
            let coord = map.convert(g.location(in: map), toCoordinateFrom: map)
            parent.tenDuong.diemVe.append(coord)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let a = view.annotation as? TenDuongAnnotation else { return }
            mapView.deselectAnnotation(a, animated: false)
            // Đang vẽ thì chạm trúng nhãn cũng là thêm điểm (chamBanDo lo), không mở hộp chọn.
            guard !parent.tenDuong.dangVe else { return }
            parent.tenDuong.chon = a.duong
        }

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
            if let line = overlay as? DuongDangVePolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = drawingUIColor
                r.lineWidth = 4
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            if let line = overlay as? TenDuongPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = streetDrawnUIColor.withAlphaComponent(0.55)
                r.lineWidth = 4
                r.lineCap = .round
                r.lineJoin = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is TenDuongAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "tenDuong", for: annotation) as! TenDuongLabelView
                view.annotation = annotation
                view.capNhat()
                return view
            }
            if annotation is DiemVeAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "diemVe", for: annotation)
                let d: CGFloat = 12
                view.frame = CGRect(x: 0, y: 0, width: d, height: d)
                view.backgroundColor = drawingUIColor
                view.layer.cornerRadius = d / 2
                view.layer.borderColor = UIColor.white.cgColor
                view.layer.borderWidth = 2
                view.displayPriority = .required
                view.isUserInteractionEnabled = false
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
    }
}
