import CoreLocation
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
    @State private var hienChonTenNhieu = false

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
            .overlay(alignment: .bottom) { thanhThaoTac().padding(.bottom, 14) }
        }
        .onAppear { m.viTri.batDau() }
        .onDisappear { m.viTri.dung() }
        .alert(m.soNhaNhap?.id == nil ? "Gán số nhà" : "Sửa số nhà", isPresented: Binding(
            get: { m.soNhaNhap != nil }, set: { if !$0 { m.soNhaNhap = nil } })) {
            TextField("VD: 13A", text: $m.soNhaGo)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button("Lưu") { Task { await m.luuSoNha(m.soNhaGo) } }
            Button("Huỷ", role: .cancel) { m.soNhaNhap = nil }
        } message: {
            Text(m.soNhaNhap?.moTa ?? "")
        }
        .confirmationDialog(m.soNhaChon.map { "Số \($0.so)" } ?? "", isPresented: Binding(
            get: { m.soNhaChon != nil }, set: { if !$0 { m.soNhaChon = nil } }),
                            titleVisibility: .visible, presenting: m.soNhaChon) { s in
            Button("Sửa số") {
                m.soNhaGo = s.so
                m.soNhaNhap = SoNhaNhap(id: s.id, toaDo: s.toaDo, moTa: "Giữ nguyên vị trí, chỉ đổi số.")
                m.soNhaChon = nil
            }
            Button("Xoá số này", role: .destructive) { Task { await m.xoaSoNha(s.id) } }
            Button("Đóng", role: .cancel) { m.soNhaChon = nil }
        } message: { _ in
            Text("Số nhà do nhân viên gán tay.")
        }
        .confirmationDialog(m.goiYChon.map { "Gợi ý: \($0.ten)" } ?? "", isPresented: Binding(
            get: { m.goiYChon != nil }, set: { if !$0 { m.goiYChon = nil } }),
                            titleVisibility: .visible, presenting: m.goiYChon) { g in
            Button("Lưu thành đường") { Task { await m.luuGoiY(g) } }
            Button("Sửa nét rồi lưu") { m.vaoVe(tuGoiY: g) }
            Button("Đóng", role: .cancel) { m.goiYChon = nil }
        } message: { g in
            Text("Đoán từ \(g.soNha) số nhà cùng hẻm nằm xa đường có sẵn. Nét đứt cam là vị trí đoán — sai thì chọn \"Sửa nét\".")
        }
        .sheet(isPresented: $hienChonTenNhieu) {
            ChonTenDuongSheet { id, ten in
                Task { await m.ganTenNhieuKhuc(tenDuongId: id, ten: ten) }
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
            if let ten = c.ten, c.nguon == "tu" || c.nguon == "osm" {
                // Xác nhận tên đoán/tên OSM là đúng → thành tên gán tay (khoá, không bị tự suy đổi nữa).
                Button("✓ Tên đúng — khoá khúc này") {
                    m.noiDaiKhiDatTen = false
                    Task { await m.ganTen(c, tenDuongId: nil, ten: ten, khongTen: false) }
                }
            }
            Button(c.ten == nil ? "Đặt tên khúc này" : "Đổi tên khúc này") { m.noiDaiKhiDatTen = false; hienChonTen = true }
            Button("Đặt tên cả đoạn thẳng nối tiếp") { m.noiDaiKhiDatTen = true; hienChonTen = true }
            if c.nguon == "tay" {
                Button("Xoá tên đã đặt", role: .destructive) { Task { await m.boGanTen(c) } }
            }
            if c.nguon == "tu" {
                Button("Tên này sai — bỏ tên", role: .destructive) { Task { await m.ganTen(c, tenDuongId: nil, ten: nil, khongTen: true) } }
            }
            if c.duongVeId != nil {
                Button("Xoá đường đã vẽ này", role: .destructive) { Task { await m.xoaDuongVe(c) } }
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
        case "tay": return "✓ Đã xác nhận (khoá) — nhân viên đặt/duyệt, không bị tự đoán đổi."
        case "tu": return "Tên tự đoán từ địa chỉ khách — có thể sai. Đặt lại tên nếu cần."
        case "osm": return "Tên có sẵn trong dữ liệu bản đồ."
        default: return "Khúc = từ ngã giao này tới ngã giao kế tiếp. Đặt tên từng khúc cho chắc, hoặc cả đoạn thẳng nối tiếp."
        }
    }

    /// Nút dưới bản đồ: gán số nhà / xác nhận khúc tại chỗ đang đứng (GPS live), chọn nhiều khúc.
    @ViewBuilder
    private func thanhThaoTac() -> some View {
        if m.cheDoVe {
            VStack(alignment: .leading, spacing: 8) {
                if let ten = m.tenVe {
                    Text(ten).font(.subheadline.bold()).foregroundColor(.brandPrimary)
                }
                Text(m.soDiemVe == 0
                     ? "Chạm từng điểm dọc theo hẻm/đường còn thiếu (chỗ cong chạm thêm), hoặc bấm 📍 khi đang đứng tại đó."
                     : "Đã chấm \(m.soDiemVe) điểm\(m.soDiemVe < 2 ? " — cần ít nhất 2" : "")")
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { m.boDiemVeCuoi() } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                        .disabled(m.soDiemVe == 0)
                        .accessibilityLabel("Bỏ điểm cuối")
                    Button { m.themDiemVeTaiCho() } label: { Image(systemName: "location.fill") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Thêm điểm tại chỗ đang đứng")
                    Spacer(minLength: 4)
                    Button("Huỷ") { m.huyVe() }
                        .buttonStyle(.bordered)
                    Button {
                        Task { await m.luuDuongVe() }
                    } label: {
                        if m.dangLuuVe { ProgressView() } else { Text("Lưu đường") }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(m.soDiemVe < 2 || m.dangLuuVe)
                }
            }
            .tint(.brandPrimary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)).shadow(radius: 4))
            .padding(.horizontal, 12)
        } else if m.cheDoNhieuKhuc {
            HStack(spacing: 10) {
                Text(m.soKhucChon == 0 ? "Chạm các khúc cùng 1 đường" : "Đã chọn \(m.soKhucChon) khúc")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 4)
                Button("Huỷ") { m.thoatNhieuKhuc() }
                    .buttonStyle(.bordered)
                Button("Đặt tên") { hienChonTenNhieu = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(m.soKhucChon == 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)).shadow(radius: 4))
            .padding(.horizontal, 12)
        } else {
            HStack(spacing: 8) {
                nutThaoTac("Số nhà tại đây", icon: "mappin.and.ellipse") { batDauSoNhaTaiCho() }
                nutThaoTac("Khúc đang đứng", icon: "road.lanes") { m.timKhucTaiCho() }
                nutThaoTac("Nhiều khúc", icon: "checklist") { m.vaoNhieuKhuc() }
                nutThaoTac("Vẽ đường", icon: "scribble.variable") { m.vaoVe() }
            }
            .padding(.horizontal, 12)
        }
    }

    /// 4 nút 1 hàng: icon trên, chữ dưới (bản 3 nút chữ ngang bị cắt "Khúc đang đứ…").
    private func nutThaoTac(_ ten: String, icon: String, _ hanhDong: @escaping () -> Void) -> some View {
        Button(action: hanhDong) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                Text(ten)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 6).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .systemBackground)).shadow(radius: 3))
        }
        .buttonStyle(.plain)
        .foregroundColor(.brandPrimary)
    }

    private func batDauSoNhaTaiCho() {
        guard let vt = m.viTri.hienTai else {
            m.thongBao = m.viTri.biTuChoi ? "Chưa cho phép vị trí — bật trong Cài đặt." : "Đang lấy vị trí, thử lại sau vài giây."
            m.viTri.batDau()
            return
        }
        m.soNhaGo = ""
        m.soNhaNhap = SoNhaNhap(id: nil, toaDo: vt.coordinate,
                                moTa: "Lấy vị trí đang đứng (sai số ~\(Int(vt.horizontalAccuracy.rounded()))m).")
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
                    Text("0").font(.caption2).foregroundColor(.textMuted)
                    Slider(value: $m.banKinhKm, in: 0...10, step: 0.1).tint(.brandPrimary)
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

/// Đang nhập số nhà (id nil = thêm mới).
struct SoNhaNhap {
    let id: String?
    let toaDo: CLLocationCoordinate2D
    let moTa: String
}

/// Số nhà gán tay vừa chạm.
struct SoNhaDaChon {
    let id: String
    let so: String
    let toaDo: CLLocationCoordinate2D
}

/// Vị trí GPS live khi đang mở bản đồ (đứng tại nhà khách để gán số / xác nhận khúc đường).
final class ViTriHienTai: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let ql = CLLocationManager()
    @Published private(set) var hienTai: CLLocation?
    @Published private(set) var biTuChoi = false

    override init() {
        super.init()
        ql.delegate = self
        ql.desiredAccuracy = kCLLocationAccuracyBest
        ql.distanceFilter = 2
    }

    func batDau() {
        switch ql.authorizationStatus {
        case .notDetermined: ql.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: ql.startUpdatingLocation()
        default: biTuChoi = true
        }
    }

    func dung() { ql.stopUpdatingLocation() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: biTuChoi = false; manager.startUpdatingLocation()
        case .denied, .restricted: biTuChoi = true
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last, l.horizontalAccuracy >= 0 else { return }
        hienTai = l
    }
}

/// Gợi ý hẻm còn thiếu (backend suy từ số nhà "N/x" 2 bên — feature g = "gy") vừa chạm.
struct GoiYHemChon {
    let ten: String
    let soNha: Int
    let diem: [CLLocationCoordinate2D]
}

/// Đoạn đường vừa chạm.
struct DuongDangChon: Equatable {
    let wayId: Int64
    let ten: String?
    /// "tay" | "tu" | "osm" | nil (chưa có tên)
    let nguon: String?
    /// Khác nil = đường nhân viên tự vẽ (OSM thiếu) → xoá được.
    var duongVeId: String? = nil
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
    /// 0km (13/11/2026 user yêu cầu; trước 0.5km, trước nữa 2.2km): mặc định hiện cả khách sát quán.
    @Published var banKinhKm: Double = 0

    @Published var nen: Data?
    @Published var tenDuong: Data?
    @Published var khach: [MapCustomerDto] = []
    @Published var doiThu: [CompetitorLocation] = []
    /// Bản đã nạp — tăng mỗi lần dữ liệu đổi để bản đồ biết nạp lại source.
    @Published var phienBanDuLieu = 0

    @Published var chon: DuongDangChon?
    /// Nút "Đặt tên khúc này" (false) hay "cả đoạn thẳng nối tiếp" (true).
    var noiDaiKhiDatTen = false

    let viTri = ViTriHienTai()
    @Published var soNhaNhap: SoNhaNhap? {
        didSet { if soNhaNhap?.id == nil, oldValue == nil { soNhaGo = "" } }
    }
    @Published var soNhaGo = ""
    @Published var soNhaChon: SoNhaDaChon?

    /// Chọn nhiều khúc rồi đặt 1 tên cho tất cả (gán đúng từng khúc, không nối dài).
    @Published var cheDoNhieuKhuc = false
    @Published private(set) var soKhucChon = 0
    private(set) var khucChon: [Int64: MLNShape] = [:]
    /// Coordinator đọc rồi xoá: cần tìm khúc gần vị trí này nhất.
    var yeuCauTimKhuc: CLLocationCoordinate2D?
    @Published var phienYeuCau = 0

    /// Vẽ đường/hẻm OSM còn thiếu: chạm từng điểm dọc hẻm (hoặc bấm 📍 thêm điểm tại chỗ đang đứng).
    @Published var cheDoVe = false
    @Published private(set) var soDiemVe = 0
    private(set) var diemVe: [CLLocationCoordinate2D] = []
    @Published var dangLuuVe = false
    /// Tên gửi kèm khi lưu (vẽ tiếp từ gợi ý hẻm).
    @Published private(set) var tenVe: String?
    @Published var goiYChon: GoiYHemChon?

    @Published var dangTai = false
    @Published var dangDungBanLuu = false
    @Published var thongBao: String?

    /// way id → (tên, nguồn) của lớp tên quán; "an" = way đã gán tay (ẩn tên OSM gốc).
    private(set) var tenTheoWay: [Int64: (ten: String, nguon: String)] = [:]
    private(set) var wayAnTenOsm: [Int64] = []
    /// way id (âm) của đường tự vẽ → id bản ghi (để xoá).
    private(set) var duongVeTheoWay: [Int64: String] = [:]

    var chuKy: String {
        "\(hienDiaPhuong)|\(hienMuaVu)|\(hienDoiThu)|\(hienTenDuong)|\(anBanKinh)|\(banKinhKm)|\(phienBanDuLieu)|\(chon?.wayId ?? 0)|\(cheDoNhieuKhuc)|\(soKhucChon)|\(phienYeuCau)|\(cheDoVe)|\(soDiemVe)"
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
        var ve: [Int64: String] = [:]
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for f in (obj["features"] as? [[String: Any]]) ?? [] {
                guard let p = f["properties"] as? [String: Any],
                      let w = (p["w"] as? NSNumber)?.int64Value else { continue }
                if p["g"] as? String == "ve" {
                    if let id = p["id"] as? String { ve[w] = id }
                    continue
                }
                guard let n = p["n"] as? String else { continue }
                map[w] = (n, (p["g"] as? String) ?? "tu")
            }
            an = ((obj["an"] as? [NSNumber]) ?? []).map { $0.int64Value }
        }
        tenTheoWay = map
        wayAnTenOsm = an
        duongVeTheoWay = ve
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
        chon?.duongVeId = duongVeTheoWay[wayId]
    }

    // MARK: Vẽ đường còn thiếu

    /// tuGoiY: vẽ tiếp từ gợi ý hẻm (điểm + tên có sẵn, sửa bằng ↶ / chạm thêm rồi lưu).
    func vaoVe(tuGoiY g: GoiYHemChon? = nil) {
        chon = nil
        goiYChon = nil
        thoatNhieuKhuc()
        diemVe = g?.diem ?? []
        soDiemVe = diemVe.count
        tenVe = g?.ten
        cheDoVe = true
    }

    func huyVe() {
        diemVe = []
        soDiemVe = 0
        tenVe = nil
        cheDoVe = false
    }

    /// Lưu thẳng gợi ý hẻm thành đường vẽ + đặt tên luôn.
    @MainActor
    func luuGoiY(_ g: GoiYHemChon) async {
        goiYChon = nil
        let r = await APIClient.shared.luuDuongVeBanDo(LuuDuongVeBanDoRequest(
            id: nil, diem: g.diem.map { [$0.latitude, $0.longitude] }, ten: g.ten))
        thongBao = r.message ?? (r.success ? "Đã thêm đường." : "Lưu thất bại.")
        if r.success {
            TenDuongCache.shared.lamMoi()
            await taiLaiTen()
        }
    }

    func themDiemVe(_ c: CLLocationCoordinate2D) {
        diemVe.append(c)
        soDiemVe = diemVe.count
    }

    func boDiemVeCuoi() {
        guard !diemVe.isEmpty else { return }
        diemVe.removeLast()
        soDiemVe = diemVe.count
    }

    /// Thêm điểm tại chỗ đang đứng (đi dọc hẻm, mỗi đoạn cong bấm 1 lần).
    func themDiemVeTaiCho() {
        guard let vt = viTri.hienTai else {
            thongBao = viTri.biTuChoi ? "Chưa cho phép vị trí — bật trong Cài đặt." : "Đang lấy vị trí, thử lại sau vài giây."
            viTri.batDau()
            return
        }
        themDiemVe(vt.coordinate)
    }

    @MainActor
    func luuDuongVe() async {
        guard diemVe.count >= 2, !dangLuuVe else { return }
        dangLuuVe = true
        let coTen = tenVe != nil
        let r = await APIClient.shared.luuDuongVeBanDo(LuuDuongVeBanDoRequest(
            id: nil, diem: diemVe.map { [$0.latitude, $0.longitude] }, ten: tenVe))
        dangLuuVe = false
        thongBao = r.message ?? (r.success ? "Đã thêm đường." : "Lưu thất bại.")
        if r.success {
            if coTen { TenDuongCache.shared.lamMoi() }
            huyVe()
            await taiLaiTen()
        }
    }

    @MainActor
    func xoaDuongVe(_ c: DuongDangChon) async {
        guard let id = c.duongVeId else { return }
        let r = await APIClient.shared.xoaDuongVeBanDo(id: id)
        thongBao = r.message ?? (r.success ? "Đã xoá." : "Xoá thất bại.")
        chon = nil
        if r.success { await taiLaiTen() }
    }

    func boChon() { chon = nil }

    @MainActor
    func ganTen(_ c: DuongDangChon, tenDuongId: String?, ten: String?, khongTen: Bool) async {
        let r = await APIClient.shared.ganTenDuongOsm(GanTenDuongOsmRequest(
            wayId: c.wayId, noiDai: khongTen ? false : noiDaiKhiDatTen, tenDuongId: tenDuongId, ten: ten, khongTen: khongTen))
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

    // MARK: Chọn nhiều khúc / khúc tại chỗ đứng

    func vaoNhieuKhuc() {
        chon = nil
        khucChon = [:]
        soKhucChon = 0
        cheDoNhieuKhuc = true
    }

    func thoatNhieuKhuc() {
        khucChon = [:]
        soKhucChon = 0
        cheDoNhieuKhuc = false
    }

    func batTatKhuc(_ wayId: Int64, shape: MLNShape) {
        if khucChon.removeValue(forKey: wayId) == nil { khucChon[wayId] = shape }
        soKhucChon = khucChon.count
    }

    func timKhucTaiCho() {
        guard let vt = viTri.hienTai else {
            thongBao = viTri.biTuChoi ? "Chưa cho phép vị trí — bật trong Cài đặt." : "Đang lấy vị trí, thử lại sau vài giây."
            viTri.batDau()
            return
        }
        yeuCauTimKhuc = vt.coordinate
        phienYeuCau += 1
    }

    @MainActor
    func ganTenNhieuKhuc(tenDuongId: String?, ten: String?) async {
        let ids = Array(khucChon.keys)
        guard let dau = ids.first else { return }
        let r = await APIClient.shared.ganTenDuongOsm(GanTenDuongOsmRequest(
            wayId: dau, noiDai: false, tenDuongId: tenDuongId, ten: ten, khongTen: false, wayIds: ids))
        thongBao = r.message ?? (r.success ? "Đã lưu." : "Lưu thất bại.")
        if r.success {
            TenDuongCache.shared.lamMoi()
            thoatNhieuKhuc()
            await taiLaiTen()
        }
    }

    // MARK: Số nhà gán tay

    func nhapSoNha(tai toaDo: CLLocationCoordinate2D) {
        soNhaNhap = SoNhaNhap(id: nil, toaDo: toaDo, moTa: "Gán tại điểm vừa nhấn giữ trên bản đồ.")
    }

    @MainActor
    func luuSoNha(_ so: String) async {
        guard let n = soNhaNhap else { return }
        soNhaNhap = nil
        let s = so.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return }
        let r = await APIClient.shared.luuSoNhaBanDo(LuuSoNhaBanDoRequest(
            id: n.id, so: s, lat: n.toaDo.latitude, long: n.toaDo.longitude))
        thongBao = r.message ?? (r.success ? "Đã lưu." : "Lưu thất bại.")
        if r.success { await taiLaiTen() }
    }

    @MainActor
    func xoaSoNha(_ id: String) async {
        soNhaChon = nil
        let r = await APIClient.shared.xoaSoNhaBanDo(id: id)
        thongBao = r.message ?? (r.success ? "Đã xoá." : "Xoá thất bại.")
        if r.success { await taiLaiTen() }
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
        // Nhấn giữ = gán số nhà tại điểm đó (không cần đứng tại nhà).
        let giu = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.nhanGiu(_:)))
        giu.minimumPressDuration = 0.5
        map.addGestureRecognizer(giu)
        map.showsUserLocation = true
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
                // Tên OSM giờ do backend trả (g = "nhan-osm", đã bỏ khúc gán tay) — không lọc "an" ở đây nữa.
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
                f.attributes = ["n": d.soNha.map { "\(d.name)\nSố \($0)" } ?? d.name]
                return f
            } : []
            (style.source(withIdentifier: "doithu") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: doiThu)

            for id in ["ten-diem", "ten-diem-tay", "ten-khu", "so-nha", "goi-y", "goi-y-ten"] {
                style.layer(withIdentifier: id)?.isVisible = m.hienTenDuong
            }
            if m.cheDoNhieuKhuc {
                (style.source(withIdentifier: "chon") as? MLNShapeSource)?.shape =
                    MLNShapeCollection(shapes: Array(m.khucChon.values))
            } else if m.chon == nil {
                (style.source(withIdentifier: "chon") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: [])
            }

            // Nét đang vẽ (chưa lưu): đường nối các điểm + chấm từng điểm.
            var nhap: [MLNShape & MLNFeature] = []
            if m.cheDoVe {
                var ds = m.diemVe
                if ds.count >= 2 { nhap.append(MLNPolylineFeature(coordinates: &ds, count: UInt(ds.count))) }
                for c in m.diemVe {
                    let p = MLNPointFeature()
                    p.coordinate = c
                    nhap.append(p)
                }
            }
            (style.source(withIdentifier: "venhap") as? MLNShapeSource)?.shape = MLNShapeCollectionFeature(shapes: nhap)

            if let toaDo = m.yeuCauTimKhuc {
                m.yeuCauTimKhuc = nil
                timKhucGanNhat(map, toaDo)
            }
        }

        /// Khúc đường (1 đoạn OSM, giữa 2 ngã giao) gần vị trí đang đứng nhất: đưa bản đồ về đó rồi chọn khúc.
        private func timKhucGanNhat(_ map: MLNMapView, _ toaDo: CLLocationCoordinate2D) {
            map.setCenter(toaDo, zoomLevel: max(map.zoomLevel, 17), animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak map] in
                guard let self, let map else { return }
                let p = map.convert(toaDo, toPointTo: map)
                let vung = CGRect(x: p.x - 90, y: p.y - 90, width: 180, height: 180)
                let ds = map.visibleFeatures(in: vung, styleLayerIdentifiers: Self.lopDuong)
                var tot: (f: MLNFeature, d: Double)?
                for f in ds {
                    guard f.attribute(forKey: "w") != nil, let line = f as? MLNPolyline else { continue }
                    let d = Self.khoangCachToiDuong(toaDo, line)
                    if tot == nil || d < tot!.d { tot = (f, d) }
                }
                guard let tot, tot.d < 60, let w = (tot.f.attribute(forKey: "w") as? NSNumber)?.int64Value else {
                    self.m.thongBao = "Không thấy khúc đường nào trong 60m quanh bạn."
                    return
                }
                if self.m.cheDoNhieuKhuc, let shape = tot.f as? MLNShape {
                    if self.m.khucChon[w] == nil { self.m.batTatKhuc(w, shape: shape) }
                    return
                }
                self.m.chonDuong(wayId: w, tenOsm: tot.f.attribute(forKey: "n") as? String)
                if let shape = tot.f as? MLNShape, let style = map.style {
                    (style.source(withIdentifier: "chon") as? MLNShapeSource)?.shape = shape
                }
            }
        }

        /// Lớp chạm chọn được khúc: đường OSM + đường nhân viên tự vẽ.
        static let lopDuong: Set<String> = ["duong", "duong-ve"]

        /// Khoảng cách (m) từ 1 điểm tới đường gấp khúc (xấp xỉ phẳng — đủ cho vài chục mét).
        static func khoangCachToiDuong(_ c: CLLocationCoordinate2D, _ line: MLNPolyline) -> Double {
            let n = Int(line.pointCount)
            guard n > 0 else { return .infinity }
            var pts = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: n)
            line.getCoordinates(&pts, range: NSRange(location: 0, length: n))
            let kx = cos(c.latitude * .pi / 180) * 111_320, ky = 110_574.0
            func xy(_ q: CLLocationCoordinate2D) -> (Double, Double) { ((q.longitude - c.longitude) * kx, (q.latitude - c.latitude) * ky) }
            if n == 1 { let a = xy(pts[0]); return hypot(a.0, a.1) }
            var best = Double.infinity
            for i in 0..<(n - 1) {
                let a = xy(pts[i]), b = xy(pts[i + 1])
                let dx = b.0 - a.0, dy = b.1 - a.1
                let len2 = dx * dx + dy * dy
                let t = len2 == 0 ? 0 : max(0, min(1, -(a.0 * dx + a.1 * dy) / len2))
                best = min(best, hypot(a.0 + t * dx, a.1 + t * dy))
            }
            return best
        }

        @objc func nhanGiu(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MLNMapView, !m.cheDoNhieuKhuc, !m.cheDoVe else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            m.nhapSoNha(tai: map.convert(g.location(in: map), toCoordinateFrom: map))
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
            // Đang vẽ đường: mỗi chạm = 1 điểm.
            if m.cheDoVe {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                m.themDiemVe(map.convert(p, toCoordinateFrom: map))
                return
            }
            let vung = CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)
            // Chạm số nhà gán tay → sửa/xoá.
            if !m.cheDoNhieuKhuc,
               let sn = map.visibleFeatures(in: vung, styleLayerIdentifiers: ["so-nha"])
                .first(where: { $0.attribute(forKey: "id") != nil }),
               let id = sn.attribute(forKey: "id") as? String {
                m.soNhaChon = SoNhaDaChon(id: id, so: (sn.attribute(forKey: "n") as? String) ?? "", toaDo: sn.coordinate)
                return
            }
            // Chạm gợi ý hẻm (nét đứt cam) → lưu / sửa rồi lưu.
            if !m.cheDoNhieuKhuc,
               let gy = map.visibleFeatures(in: vung, styleLayerIdentifiers: ["goi-y"]).first,
               let line = gy as? MLNPolyline, line.pointCount >= 2 {
                var pts = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: Int(line.pointCount))
                line.getCoordinates(&pts, range: NSRange(location: 0, length: pts.count))
                m.goiYChon = GoiYHemChon(ten: (gy.attribute(forKey: "n") as? String) ?? "Hẻm",
                                         soNha: (gy.attribute(forKey: "sl") as? NSNumber)?.intValue ?? 0,
                                         diem: pts)
                return
            }
            let fs = map.visibleFeatures(in: vung, styleLayerIdentifiers: Self.lopDuong)
            guard let f = fs.first(where: { $0.attribute(forKey: "w") != nil }),
                  let w = (f.attribute(forKey: "w") as? NSNumber)?.int64Value else {
                if !m.cheDoNhieuKhuc { m.boChon() }
                return
            }
            if m.cheDoNhieuKhuc {
                if let shape = f as? MLNShape { m.batTatKhuc(w, shape: shape) }
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

/// Màu/độ rộng đường theo cấp OSM (c = highway). Tên OSM (ít) + tên quán (lớp "ten": g = tu|tay, điểm g = khu,
/// g = sn là SỐ NHÀ). Tên địa điểm OSM (đa số "QT …" = quầy thuốc) KHÔNG hiện — user chỉ cần số nhà (12/11/2026).
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
    "venhap": {"type": "geojson", "data": {"type": "FeatureCollection", "features": []}},
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
    {"id": "duong-ve-vien", "type": "line", "source": "ten", "filter": ["==", ["get", "g"], "ve"],
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": "#D6CEC0", "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 12, 1.2, 18, 16]}},
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
    {"id": "duong-ve", "type": "line", "source": "ten", "filter": ["==", ["get", "g"], "ve"],
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": "#FFFFFF", "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 12, 0.8, 18, 13]}},
    {"id": "goi-y", "type": "line", "source": "ten", "minzoom": 14, "filter": ["==", ["get", "g"], "gy"],
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": "#F08A00", "line-opacity": 0.85, "line-dasharray": [1.5, 1.2],
               "line-width": ["interpolate", ["linear"], ["zoom"], 14, 2, 18, 6]}},
    {"id": "goi-y-ten", "type": "symbol", "source": "ten", "minzoom": 15, "filter": ["==", ["get", "g"], "gy"],
     "layout": {"symbol-placement": "line", "text-field": ["concat", ["get", "n"], " ?"], "text-font": ["Noto Sans Italic"],
                "text-size": 11, "text-max-angle": 30, "symbol-spacing": 300},
     "paint": {"text-color": "#B86A00", "text-halo-color": "#FFFFFF", "text-halo-width": 1.6}},
    {"id": "ve-nhap", "type": "line", "source": "venhap", "filter": ["==", ["geometry-type"], "LineString"],
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": "#1B6B5F", "line-width": 4, "line-dasharray": [2, 1]}},
    {"id": "ve-nhap-diem", "type": "circle", "source": "venhap", "filter": ["==", ["geometry-type"], "Point"],
     "paint": {"circle-color": "#1B6B5F", "circle-radius": 5, "circle-stroke-color": "#FFFFFF", "circle-stroke-width": 2}},
    {"id": "duong-chon", "type": "line", "source": "chon",
     "layout": {"line-cap": "round", "line-join": "round"},
     "paint": {"line-color": "#E53935", "line-opacity": 0.55,
               "line-width": ["interpolate", ["exponential", 1.6], ["zoom"], 12, 4, 18, 22]}},
    {"id": "khach", "type": "circle", "source": "khach",
     "paint": {"circle-color": ["match", ["get", "s"], 1, "#F08A00", "#1E4E8C"], "circle-opacity": 0.6,
               "circle-radius": ["interpolate", ["linear"], ["zoom"], 11, 2.5, 16, 5]}},
    {"id": "ten-khu", "type": "symbol", "source": "ten", "minzoom": 12,
     "filter": ["==", ["get", "g"], "khu"],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Italic"], "text-size": 12},
     "paint": {"text-color": "#6B5B8A", "text-halo-color": "#FFFFFF", "text-halo-width": 1.5}},
    {"id": "dia-danh", "type": "symbol", "source": "nen", "filter": ["==", ["get", "k"], "place"],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Italic"],
                "text-size": ["match", ["get", "c"], "town", 15, ["village", "suburb"], 13, 11]},
     "paint": {"text-color": "#6B5B8A", "text-halo-color": "#FFFFFF", "text-halo-width": 1.5}},
    {"id": "so-nha", "type": "symbol", "source": "ten", "minzoom": 15.5, "filter": ["==", ["get", "g"], "sn"],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Regular"],
                "text-size": ["interpolate", ["linear"], ["zoom"], 15.5, 9, 18, 12]},
     "paint": {"text-color": ["case", ["has", "t"], "#1B6B5F", "#8A6A3A"], "text-halo-color": "#FFFFFF", "text-halo-width": 1.4}},
    {"id": "ten-diem", "type": "symbol", "source": "ten", "minzoom": 12,
     "filter": ["in", ["get", "g"], ["literal", ["nhand-tu", "nhand-osm"]]],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Regular"],
                "text-size": ["interpolate", ["linear"], ["zoom"], 12, 6.5, 14, 8, 16, 9.5, 18, 12],
                "text-rotate": ["get", "r"], "text-rotation-alignment": "map", "text-allow-overlap": true},
     "paint": {"text-color": ["match", ["get", "g"], "nhand-osm", "#555555", "#6E6E6E"],
               "text-halo-color": "#FFFFFF", "text-halo-width": 1.5}},
    {"id": "ten-diem-tay", "type": "symbol", "source": "ten", "minzoom": 12,
     "filter": ["==", ["get", "g"], "nhand-tay"],
     "layout": {"text-field": ["get", "n"], "text-font": ["Noto Sans Bold"],
                "text-size": ["interpolate", ["linear"], ["zoom"], 12, 6.5, 14, 8, 16, 9.5, 18, 12],
                "text-rotate": ["get", "r"], "text-rotation-alignment": "map", "text-allow-overlap": true},
     "paint": {"text-color": "#1B6B5F", "text-halo-color": "#FFFFFF", "text-halo-width": 1.5}},
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
