import MapLibre
import SwiftUI

/// Bản đồ khách hàng OFFLINE (12/11/2026, user chọn thay cho lớp tên đè lên Apple Maps): nền tự dựng từ
/// OpenStreetMap (scripts/vps/build-ban-do-nen.py → https://api.denncoffee.com/ban-do/nen.geojson), vẽ bằng
/// MapLibre. OSM ở Krông Pắc đủ HÌNH đường nhưng gần như không có tên → tên đường của quán do backend gắn
/// lên đúng đoạn đường (BanDoOsmService: tự suy từ địa chỉ khách + nhân viên chạm đường để đặt tên).
/// Mọi dữ liệu (nền, tên, khách, đối thủ) lưu lại trên máy → mất mạng vẫn mở được bản đã tải.
/// Màn Apple Maps cũ (BanDoKhachHangView) vẫn giữ, mở bằng nút trên thanh tiêu đề.
struct BanDoOfflineView: View {
    @StateObject private var m = BanDoOfflineModel()
    @State private var hienChonTen = false

    var body: some View {
        VStack(spacing: 0) {
            thanhLoc()
            ZStack(alignment: .top) {
                BanDoMapLibreView(m: m, chuKy: m.chuKy)
                    .ignoresSafeArea(edges: .bottom)
                if let tb = m.thongBao {
                    Text(tb)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(.regularMaterial))
                        .padding(.top, 10)
                        .task(id: tb) {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            if m.thongBao == tb { m.thongBao = nil }
                        }
                } else if m.dangDungBanLuu {
                    Text("Đang dùng dữ liệu đã lưu (không có mạng)")
                        .font(.caption2)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(.regularMaterial))
                        .padding(.top, 8)
                }
                if m.dangTai {
                    ProgressView().padding(.top, 60)
                }
            }
        }
        .navigationTitle("Bản đồ khách hàng")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    BanDoKhachHangView()
                } label: {
                    Image(systemName: "apple.logo")
                }
                .accessibilityLabel("Mở bản đồ Apple")
            }
        }
        .task { await m.taiTatCa() }
        .confirmationDialog(m.chon.map { $0.ten ?? "Đoạn đường chưa có tên" } ?? "",
                            isPresented: Binding(get: { m.chon != nil && !hienChonTen },
                                                 set: { if !$0 && !hienChonTen { m.boChon() } }),
                            titleVisibility: .visible, presenting: m.chon) { c in
            Button(c.ten == nil ? "Đặt tên đường này" : "Đổi tên đường này") { hienChonTen = true }
            if c.nguon == "tay" {
                Button("Xoá tên đã đặt", role: .destructive) { Task { await m.boGanTen(c) } }
            }
            if c.nguon == "tu" {
                Button("Tên này sai — bỏ tên", role: .destructive) { Task { await m.ganTen(c, tenDuongId: nil, ten: nil, khongTen: true) } }
            }
            Button("Đóng", role: .cancel) { m.boChon() }
        } message: { c in
            Text(moTa(c))
        }
        .sheet(isPresented: $hienChonTen, onDismiss: { m.boChon() }) {
            ChonTenDuongSheet { id, ten in
                if let c = m.chon {
                    Task { await m.ganTen(c, tenDuongId: id, ten: ten, khongTen: false) }
                }
            }
        }
    }

    private func moTa(_ c: DuongDangChon) -> String {
        switch c.nguon {
        case "tay": return "Tên do nhân viên đặt. Áp dụng cho cả các đoạn thẳng nối tiếp."
        case "tu": return "Tên tự đoán từ địa chỉ khách — có thể sai. Đặt lại tên nếu cần."
        case "osm": return "Tên có sẵn trong dữ liệu bản đồ."
        default: return "Chạm \"Đặt tên\" để gắn tên — áp dụng cho cả các đoạn thẳng nối tiếp."
        }
    }

    private func thanhLoc() -> some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Dân địa phương", mau: Color(uiColor: mauDanDiaPhuong), bat: $m.hienDiaPhuong)
                    chip("Kho / đại lý (mùa vụ)", mau: Color(uiColor: mauMuaVu), bat: $m.hienMuaVu)
                    chip("Đối thủ", mau: Color(uiColor: mauDoiThu), bat: $m.hienDoiThu)
                    chip("Tên đường", mau: Color(uiColor: mauTenTay), bat: $m.hienTenDuong)
                }
                .padding(.horizontal, 12)
            }
            Toggle(isOn: $m.anBanKinh) {
                Text("Ẩn trong bán kính \(String(format: "%.1f", m.banKinhKm))km quanh quán").font(.caption)
            }
            .toggleStyle(.switch)
            .tint(.brandPrimary)
            .padding(.horizontal, 12)
            if m.anBanKinh {
                HStack(spacing: 8) {
                    Text("0.5").font(.caption2).foregroundColor(.textMuted)
                    Slider(value: $m.banKinhKm, in: 0.5...10, step: 0.1).tint(.brandPrimary)
                    Text("10").font(.caption2).foregroundColor(.textMuted)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func chip(_ title: String, mau: Color, bat: Binding<Bool>) -> some View {
        Button {
            bat.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle().fill(bat.wrappedValue ? mau : Color.textMuted.opacity(0.3)).frame(width: 9, height: 9)
                Text(title).font(.caption.weight(.medium))
                    .foregroundColor(bat.wrappedValue ? .primary : .textMuted)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(bat.wrappedValue ? mau.opacity(0.12) : Color.textMuted.opacity(0.08)))
            .overlay(Capsule().strokeBorder(bat.wrappedValue ? mau.opacity(0.5) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private let mauDanDiaPhuong = UIColor(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255, alpha: 1)
private let mauMuaVu = UIColor(red: 0xF0 / 255, green: 0x8A / 255, blue: 0x00 / 255, alpha: 1)
private let mauDoiThu = UIColor(red: 0xB0 / 255, green: 0x30 / 255, blue: 0x30 / 255, alpha: 1)
private let mauTenTay = UIColor(red: 0x1B / 255, green: 0x6B / 255, blue: 0x5F / 255, alpha: 1)

/// Đoạn đường vừa chạm.
struct DuongDangChon: Equatable {
    let wayId: Int64
    let ten: String?
    /// "tay" | "tu" | "osm" | nil (chưa có tên)
    let nguon: String?
}

// MARK: - Model

/// Không đánh dấu @MainActor cả lớp — Coordinator (UIKit) đọc thuộc tính đồng bộ trên main thread; các hàm
/// async gọi mạng đánh dấu @MainActor riêng (cùng cách BanDoTenDuongModel).
final class BanDoOfflineModel: ObservableObject {
    @Published var hienDiaPhuong = true
    @Published var hienMuaVu = true
    @Published var hienDoiThu = true
    @Published var hienTenDuong = true
    @Published var anBanKinh = true
    @Published var banKinhKm: Double = 2.2

    @Published var nen: Data?
    @Published var tenDuong: Data?
    @Published var khach: [MapCustomerDto] = []
    @Published var doiThu: [CompetitorLocation] = []
    /// Bản đã nạp — tăng mỗi lần dữ liệu đổi để bản đồ biết nạp lại source.
    @Published var phienBanDuLieu = 0

    @Published var chon: DuongDangChon?
    @Published var dangTai = false
    @Published var dangDungBanLuu = false
    @Published var thongBao: String?

    /// way id → (tên, nguồn) của lớp tên quán; "an" = way đã gán tay (ẩn tên OSM gốc).
    private(set) var tenTheoWay: [Int64: (ten: String, nguon: String)] = [:]
    private(set) var wayAnTenOsm: [Int64] = []

    var chuKy: String {
        "\(hienDiaPhuong)|\(hienMuaVu)|\(hienDoiThu)|\(hienTenDuong)|\(anBanKinh)|\(banKinhKm)|\(phienBanDuLieu)|\(chon?.wayId ?? 0)"
    }

    private static let nenURL = URL(string: "https://api.denncoffee.com/ban-do/nen.geojson")!
    private static var thuMuc: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ban-do", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private static func file(_ ten: String) -> URL { thuMuc.appendingPathComponent(ten) }
    private static func doc(_ ten: String) -> Data? { try? Data(contentsOf: file(ten)) }
    private static func ghi(_ data: Data, _ ten: String) { try? data.write(to: file(ten), options: .atomic) }

    @MainActor
    func taiTatCa() async {
        // Hiện ngay bản đã lưu (offline/mở nhanh), rồi làm mới từ mạng.
        nen = Self.doc("nen.geojson")
        if let t = Self.doc("ten-duong.geojson") { datTenDuong(t) }
        if let d = Self.doc("khach.json"), let k = try? JSONDecoder().decode([MapCustomerDto].self, from: d) { khach = k }
        if let d = Self.doc("doi-thu.json"), let r = try? JSONDecoder().decode(MapDataResponse.self, from: d) { doiThu = r.competitors ?? [] }
        phienBanDuLieu += 1
        dangTai = nen == nil

        async let nenMoi = taiNen()
        async let tenMoi = APIClient.shared.getBanDoTenDuongGeoJson()
        async let khachMoi = APIClient.shared.getMapCustomers()
        async let doiThuMoi = taiDoiThu()
        let (n, t, k, d) = await (nenMoi, tenMoi, khachMoi, doiThuMoi)

        var loi = false
        if let n { nen = n; Self.ghi(n, "nen.geojson") } else if nen != nil { loi = true }
        if let t { datTenDuong(t); Self.ghi(t, "ten-duong.geojson") } else { loi = true }
        if !k.isEmpty {
            khach = k
            if let d = try? JSONEncoder().encode(k) { Self.ghi(d, "khach.json") }
        } else { loi = true }
        if let d {
            doiThu = d.competitors ?? []
            if let e = try? JSONEncoder().encode(d) { Self.ghi(e, "doi-thu.json") }
        }
        dangDungBanLuu = loi && nen != nil
        dangTai = false
        if nen == nil { thongBao = "Chưa tải được bản đồ — cần mạng cho lần mở đầu tiên." }
        phienBanDuLieu += 1
    }

    /// Nền ~3,5MB — chỉ tải lại khi máy chủ đổi (If-None-Match/ETag).
    private func taiNen() async -> Data? {
        var req = URLRequest(url: Self.nenURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let co = Self.doc("nen.geojson") != nil
        if co, let etag = UserDefaults.standard.string(forKey: "banDo.nen.etag") {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let ketQua = try? await URLSession.shared.data(for: req), let http = ketQua.1 as? HTTPURLResponse else { return nil }
        let data = ketQua.0
        if http.statusCode == 304 { return Self.doc("nen.geojson") }
        guard http.statusCode == 200, !data.isEmpty else { return nil }
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(etag, forKey: "banDo.nen.etag")
        }
        return data
    }

    private func taiDoiThu() async -> MapDataResponse? {
        guard let ketQua = try? await URLSession.shared.data(from: competitorsDataURL) else { return nil }
        return try? JSONDecoder().decode(MapDataResponse.self, from: ketQua.0)
    }

    private func datTenDuong(_ data: Data) {
        tenDuong = data
        var map: [Int64: (ten: String, nguon: String)] = [:]
        var an: [Int64] = []
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for f in (obj["features"] as? [[String: Any]]) ?? [] {
                guard let p = f["properties"] as? [String: Any],
                      let w = (p["w"] as? NSNumber)?.int64Value,
                      let n = p["n"] as? String else { continue }
                map[w] = (n, (p["g"] as? String) ?? "tu")
            }
            an = ((obj["an"] as? [NSNumber]) ?? []).map { $0.int64Value }
        }
        tenTheoWay = map
        wayAnTenOsm = an
    }

    func chonDuong(wayId: Int64, tenOsm: String?) {
        if let t = tenTheoWay[wayId] {
            chon = DuongDangChon(wayId: wayId, ten: t.ten, nguon: t.nguon)
        } else if wayAnTenOsm.contains(wayId) {
            chon = DuongDangChon(wayId: wayId, ten: nil, nguon: nil)
        } else if let tenOsm, !tenOsm.isEmpty {
            chon = DuongDangChon(wayId: wayId, ten: tenOsm, nguon: "osm")
        } else {
            chon = DuongDangChon(wayId: wayId, ten: nil, nguon: nil)
        }
    }

    func boChon() { chon = nil }

    @MainActor
    func ganTen(_ c: DuongDangChon, tenDuongId: String?, ten: String?, khongTen: Bool) async {
        let r = await APIClient.shared.ganTenDuongOsm(GanTenDuongOsmRequest(
            wayId: c.wayId, noiDai: true, tenDuongId: tenDuongId, ten: ten, khongTen: khongTen))
        thongBao = r.message ?? (r.success ? "Đã lưu." : "Lưu thất bại.")
        if r.success {
            if !khongTen { TenDuongCache.shared.lamMoi() }
            await taiLaiTen()
        }
        chon = nil
    }

    @MainActor
    func boGanTen(_ c: DuongDangChon) async {
        let r = await APIClient.shared.boGanTenDuongOsm(wayId: c.wayId)
        thongBao = r.message ?? (r.success ? "Đã xoá." : "Xoá thất bại.")
        if r.success { await taiLaiTen() }
        chon = nil
    }

    @MainActor
    private func taiLaiTen() async {
        if let t = await APIClient.shared.getBanDoTenDuongGeoJson() {
            datTenDuong(t)
            Self.ghi(t, "ten-duong.geojson")
            phienBanDuLieu += 1
        }
    }
}

// MARK: - MapLibre

private struct BanDoMapLibreView: UIViewRepresentable {
    @ObservedObject var m: BanDoOfflineModel
    /// Chỉ để SwiftUI gọi updateUIView khi bộ lọc/dữ liệu đổi.
    let chuKy: String

    func makeCoordinator() -> Coordinator { Coordinator(m: m) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: Self.styleURL())
        map.delegate = context.coordinator
        map.setCenter(storeCoordinate, zoomLevel: 14, animated: false)
        map.minimumZoomLevel = 10
        map.maximumZoomLevel = 19
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.cham(_:)))
        // Chạm đúp để phóng to không bị tính là chạm chọn đường.
        for g in map.gestureRecognizers ?? [] {
            if let t = g as? UITapGestureRecognizer, t.numberOfTapsRequired == 2 { tap.require(toFail: t) }
        }
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.m = m
        context.coordinator.capNhat(map)
    }

    /// Style viết sẵn ra file (nguồn để trống, nạp dữ liệu sau khi style load xong).
    static func styleURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ban-do-style-v1.json")
        try? styleJSON.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var m: BanDoOfflineModel
        private var styleSanSang = false
        private var phienBanDaNap = -1
        private var locDaApDung = ""

        init(m: BanDoOfflineModel) { self.m = m }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleSanSang = true
            phienBanDaNap = -1
            locDaApDung = ""
            capNhat(mapView)
        }

        func capNhat(_ map: MLNMapView) {
            guard styleSanSang, let style = map.style else { return }

            if phienBanDaNap != m.phienBanDuLieu {
                phienBanDaNap = m.phienBanDuLieu
                datShape(style, "nen", m.nen)
                datShape(style, "ten", m.tenDuong)
                (style.layer(withIdentifier: "duong-ten-osm") as? MLNVectorStyleLayer)?.predicate =
                    m.wayAnTenOsm.isEmpty
                        ? NSPredicate(format: "k == 'road' AND n != nil")
                        : NSPredicate(format: "k == 'road' AND n != nil AND NOT (w IN %@)", m.wayAnTenOsm.map { NSNumber(value: $0) })
                (style.source(withIdentifier: "quan") as? MLNShapeSource)?.shape = {
                    let f = MLNPointFeature()
                    f.coordinate = storeCoordinate
                    f.attributes = ["n": "Quán"]
                    return f
                }()
                locDaApDung = ""
            }

            let loc = m.chuKy
            guard loc != locDaApDung else { return }
            locDaApDung = loc

            let quan = CLLocation(latitude: storeCoordinate.latitude, longitude: storeCoordinate.longitude)
            let r = m.banKinhKm * 1000
            func ngoaiBanKinh(_ lat: Double, _ lng: Double) -> Bool {
                !m.anBanKinh || CLLocation(latitude: lat, longitude: lng).distance(from: quan) >= r
            }

            let khach: [MLNShape & MLNFeature] = m.khach.compactMap { k -> (MLNShape & MLNFeature)? in
                guard (k.seasonal ? m.hienMuaVu : m.hienDiaPhuong), ngoaiBanKinh(k.lat, k.long) else { return nil }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: k.lat, longitude: k.long)
                f.attributes = ["s": k.seasonal ? 1 : 0]
                return f
            }
            (style.source(withIdentifier: "khach") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: khach)

            let doiThu: [MLNShape & MLNFeature] = m.hienDoiThu ? m.doiThu.compactMap { d -> (MLNShape & MLNFeature)? in
                guard ngoaiBanKinh(d.lat, d.lon) else { return nil }
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: d.lat, longitude: d.lon)
                f.attributes = ["n": d.name]
                return f
            } : []
            (style.source(withIdentifier: "doithu") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: doiThu)

            for id in ["duong-ten-osm", "ten-tu", "ten-tay", "ten-khu"] {
                style.layer(withIdentifier: id)?.isVisible = m.hienTenDuong
            }
            if m.chon == nil {
                (style.source(withIdentifier: "chon") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: [])
            }
        }

        private func datShape(_ style: MLNStyle, _ id: String, _ data: Data?) {
            guard let src = style.source(withIdentifier: id) as? MLNShapeSource else { return }
            if let data, let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
                src.shape = shape
            }
        }

        @objc func cham(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let map = g.view as? MLNMapView else { return }
            let p = g.location(in: map)
            let vung = CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)
            let fs = map.visibleFeatures(in: vung, styleLayerIdentifiers: ["duong"])
            guard let f = fs.first(where: { $0.attribute(forKey: "w") != nil }),
                  let w = (f.attribute(forKey: "w") as? NSNumber)?.int64Value else {
                m.boChon()
                return
            }
            m.chonDuong(wayId: w, tenOsm: f.attribute(forKey: "n") as? String)
            if let shape = f as? MLNShape, let style = map.style {
                (style.source(withIdentifier: "chon") as? MLNShapeSource)?.shape = shape
            }
        }
    }
}

// MARK: - Style

/// Màu/độ rộng đường theo cấp OSM (c = highway). Tên OSM (ít) + tên quán (lớp "ten": g = tu|tay, điểm g = khu).
private let styleJSON = #"""
{
  "version": 8,
  "name": "denn-ban-do",
  "glyphs": "https://api.denncoffee.com/ban-do/fonts/{fontstack}/{range}.pbf",
  "sources": {
    "nen": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []},
            "attribution": "© OpenStreetMap contributors"},
    "ten": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}},
    "chon": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}},
    "khach": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}},
    "doithu": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}},
    "quan": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}}
  },
  "layers": [
    {"id": "nen-mau", "type": "background", "paint": {"background-color": "#F2EFE9"}},
    {"id": "vung", "type": "fill", "source": "nen", "filter": ["==", ["get", "k"], "landuse"],
     "paint": {"fill-color": ["match", ["get", "c"], ["forest", "wood"], "#DCE9CF", "residential", "#E9E5DC", "#ECEAD8"], "fill-opacity": 0.7}},
    {"id": "nuoc", "type": "fill", "source": "nen", "filter": ["==", ["get", "k"], "water"],
     "paint": {"fill-color": "#AAD3DF"}},
    {"id": "song", "type": "line", "source": "nen", "filter": ["==", ["get", "k"], "waterway"],
     "paint": {"line-color": "#AAD3DF", "line-width": ["interpolate", ["linear"], ["zoom"], 12, 1, 17, 3]}},
    {"id": "duong-vien", "type": "line", "source": "nen",
     "filter": ["all", ["==", ["get", "k"], "road"], ["!", ["in", ["get", "c"], ["literal", ["track", "path", "footway", "steps", "cycleway", "bridleway"]]]]],
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": "#D6CEC0",
               "line-width": ["interpolate", ["exponential", 1.6], ["zoom"],
                 12, ["match", ["get", "c"], ["motorway", "trunk", "primary"], 3.5, ["secondary", "tertiary"], 2.5, 1.2],
                 18, ["match", ["get", "c"], ["motorway", "trunk", "primary"], 26, ["secondary", "tertiary"], 22, 16]]}},
    {"id": "duong", "type": "line", "source": "nen", "filter": ["==", ["get", "k"], "road"],
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": ["match", ["get", "c"],
                 ["motorway", "motorway_link"], "#E892A2",
                 ["trunk", "trunk_link", "primary", "primary_link"], "#FCD6A4",
                 ["secondary", "secondary_link"], "#F7FABF",
                 ["track", "path", "footway", "steps", "cycleway", "bridleway"], "#B9A68C",
                 "#FFFFFF"],
               "line-width": ["interpolate", ["exponential", 1.6], ["zoom"],
                 12, ["match", ["get", "c"], ["motorway", "trunk", "primary"], 2.5, ["secondary", "tertiary"], 1.8, ["track", "path", "footway"], 0.6, 0.8],
                 18, ["match", ["get", "c"], ["motorway", "trunk", "primary"], 22, ["secondary", "tertiary"], 18, ["track", "path", "footway"], 3, 13]]}},
    {"id": "duong-chon", "type": "line", "source": "chon",
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": "#E53935", "line-opacity": 0.55,
               "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 12, 4, 18, 22]}},
    {"id": "khach", "type": "circle", "source": "khach",
     "paint": {"circle-color": ["match", ["get", "s"], 1, "#F08A00", "#1E4E8C"], "circle-opacity": 0.6,
               "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, 2.5, 16, 5]}},
    {"id": "duong-ten-osm", "type": "symbol", "source": "nen", "minzoom": 13,
     "filter": ["all", ["==", ["get", "k"], "road"], ["has", "n"]],
     "layout": {"symbol-placement": "line", "text-field": ["get", "n"], "text-font": ["Noto Sans Regular"],
                "text-size": ["interpolate", ["linear"], ["zoom"], 13, 10, 18, 14], "text-max-angle": 30,
                "symbol-spacing": 350},
     "paint": {"text-color": "#5F5F5F", "text-halo-color": "#FFFFFF", "text-halo-width": 1.6}},
    {"id": "ten-tu", "type": "symbol", "source": "ten", "minzoom": 13,
     "filter": ["==", ["get", "g"], "tu"],
     "layout": {"symbol-placement": "line", "text-field": ["get", "n"], "text-font": ["Noto Sans Regular"],
                "text-size": ["interpolate", ["linear"], ["zoom"], 13, 10, 18, 14], "text-max-angle": 30,
                "symbol-spacing": 350},
     "paint": {"text-color": "#4A4A4A", "text-halo-color": "#FFFFFF", "text-halo-width": 1.6}},
    {"id": "ten-tay", "type": "symbol", "source": "ten", "minzoom": 12,
     "filter": ["==", ["get", "g"], "tay"],
     "layout": {"symbol-placement": "line", "text-field": ["get", "n"], "text-font": ["Noto Sans Bold"],
                "text-size": ["interpolate", ["linear"], ["zoom"], 12, 10, 18, 15], "text-max-angle": 30,
                "symbol-spacing": 350},
     "paint": {"text-color": "#1B6B5F", "text-halo-color": "#FFFFFF", "text-halo-width": 1.8}},
    {"id": "ten-khu", "type": "symbol", "source": "ten", "minzoom": 12,
     "filter": ["==", ["get", "g"], "khu"],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Italic"], "text-size": 12},
     "paint": {"text-color": "#6B5B8A", "text-halo-color": "#FFFFFF", "text-halo-width": 1.5}},
    {"id": "dia-danh", "type": "symbol", "source": "nen", "filter": ["==", ["get", "k"], "place"],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Italic"],
                "text-size": ["match", ["get", "c"], "town", 15, ["village", "suburb"], 13, 11]},
     "paint": {"text-color": "#6B5B8A", "text-halo-color": "#FFFFFF", "text-halo-width": 1.5}},
    {"id": "dia-diem", "type": "symbol", "source": "nen", "minzoom": 15, "filter": ["==", ["get", "k"], "poi"],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Regular"], "text-size": 10, "text-optional": true},
     "paint": {"text-color": "#8A6A3A", "text-halo-color": "#FFFFFF", "text-halo-width": 1.2}},
    {"id": "doithu", "type": "circle", "source": "doithu",
     "paint": {"circle-color": "#B03030", "circle-radius": 6, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 1.5}},
    {"id": "doithu-ten", "type": "symbol", "source": "doithu", "minzoom": 14,
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Bold"], "text-size": 11,
                "text-offset": [0, 1.1], "text-anchor": "top", "text-optional": true},
     "paint": {"text-color": "#B03030", "text-halo-color": "#FFFFFF", "text-halo-width": 1.5}},
    {"id": "quan", "type": "circle", "source": "quan",
     "paint": {"circle-color": "#1E4E8C", "circle-radius": 9, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2.5}},
    {"id": "quan-ten", "type": "symbol", "source": "quan",
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Bold"], "text-size": 12,
                "text-offset": [0, 1.3], "text-anchor": "top", "text-allow-overlap": true},
     "paint": {"text-color": "#1E4E8C", "text-halo-color": "#FFFFFF", "text-halo-width": 1.8}}
  ]
}
"""#
