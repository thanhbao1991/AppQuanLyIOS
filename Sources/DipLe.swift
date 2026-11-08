import SwiftUI
import UIKit

/// Giao diện dịp lễ cho app quản lý (2026-11-08, chủ quán: "đưa giao diện các dịp lễ vào app quản lý" — màu chủ đạo,
/// icon, màn chào). Cùng nguồn với app khách: GET /api/dat-hang/dip-le/hien-thi (AllowAnonymous, server DipLeLich quyết
/// định cửa sổ 2 ngày trước → hết ngày lễ), cùng bộ màu (AppDatHangIOS SeasonalEvent.swift), cùng bộ icon + ảnh màn chào.
/// Đổi màu/ảnh ở app khách thì nhớ đổi ở đây.
enum DipLeTheme: String, CaseIterable, Identifiable {
    case TETDUONG, TETAL, VALENTINE, QTPHUNU, PHUNUVN, GIOTO, GIAIPHONG, THIEUNHI, DOANNGO, THUONGBINH, VULAN,
         QUOCKHANH, TRUNGTHU, NHAGIAO, NOEL

    var id: String { rawValue }
    var ma: String { rawValue }

    /// Màu chủ đạo — thay Color.brandPrimary (navy) trong cửa sổ giao diện dịp.
    var primary: Color {
        switch self {
        case .TETDUONG: return Color(red: 0.09, green: 0.15, blue: 0.35)
        case .TETAL, .QUOCKHANH: return Color(red: 0.80, green: 0.08, blue: 0.1)
        case .VALENTINE: return Color(red: 0.87, green: 0.18, blue: 0.42)
        case .QTPHUNU: return Color(red: 0.45, green: 0.22, blue: 0.66)
        case .PHUNUVN: return Color(red: 0.78, green: 0.27, blue: 0.33)
        case .GIOTO: return Color(red: 0.62, green: 0.13, blue: 0.08)
        case .DOANNGO: return Color(red: 0.13, green: 0.48, blue: 0.25)
        case .VULAN: return Color(red: 0.08, green: 0.32, blue: 0.38)
        case .THIEUNHI: return Color(red: 0.10, green: 0.50, blue: 0.85)
        case .TRUNGTHU: return Color(red: 0.11, green: 0.25, blue: 0.44)
        case .NHAGIAO: return Color(red: 0.09, green: 0.42, blue: 0.40)
        case .NOEL: return Color(red: 0.70, green: 0.07, blue: 0.11)
        case .THUONGBINH: return Color(red: 0.22, green: 0.27, blue: 0.34)
        case .GIAIPHONG: return Color(red: 0.86, green: 0.28, blue: 0.10)
        }
    }

    var ten: String {
        switch self {
        case .TETDUONG: return "Tết Dương lịch"
        case .TETAL: return "Tết Nguyên Đán"
        case .VALENTINE: return "Valentine"
        case .QTPHUNU: return "Quốc tế Phụ nữ 8/3"
        case .PHUNUVN: return "Phụ nữ Việt Nam 20/10"
        case .GIOTO: return "Giỗ Tổ Hùng Vương"
        case .DOANNGO: return "Tết Đoan Ngọ"
        case .THUONGBINH: return "Thương binh - Liệt sĩ 27/7"
        case .VULAN: return "Lễ Vu Lan"
        case .GIAIPHONG: return "30/4 - 1/5"
        case .THIEUNHI: return "Quốc tế Thiếu nhi"
        case .QUOCKHANH: return "Quốc khánh 2/9"
        case .TRUNGTHU: return "Tết Trung Thu"
        case .NHAGIAO: return "Nhà giáo Việt Nam 20/11"
        case .NOEL: return "Giáng sinh"
        }
    }
}

/// GET /api/dat-hang/dip-le/hien-thi — chỉ lấy phần app quản lý cần.
struct DipLeHienThi: Decodable {
    struct GiaoDien: Codable {
        let ma: String
        let ten: String
        let moTa: String?
        let anhManChao: String?
        let doiIcon: Bool?
        let ngayKetThuc: String?
    }
    let maIcon: String?
    let anhManChaoIcon: String?
    /// Icon server đang cho app khách hiện (30 ngày trước → 3 ngày sau lễ, giữa 2 dịp giữ icon dịp vừa qua).
    let maIconHienTai: String?
    let giaoDien: GiaoDien?
}

/// Trạng thái dịp lễ toàn app. `Color.brandPrimary` đọc `DipLeMau.hienTai` (static, đọc được ở mọi nơi kể cả ngoài
/// MainActor); ContentView quan sát `phienBan` và dựng lại cây view khi đổi dịp để mọi màn ăn màu mới.
@MainActor
final class DipLe: ObservableObject {
    static let shared = DipLe()

    static let mauMacDinh = Color(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255)

    /// Dịp dipThat từ server (đã lưu máy để mở app là đúng màu ngay, không nháy navy → màu dịp).
    @Published private(set) var dipThat: DipLeHienThi.GiaoDien?
    /// Xem thử (Menu → Giao diện dịp lễ), không lưu — mở lại app là hết.
    @Published var xemThu: DipLeTheme? { didSet { apDung() } }
    /// Đổi mỗi khi màu chủ đạo đổi — ContentView dùng làm .id để vẽ lại toàn bộ.
    @Published private(set) var phienBan = 0

    var active: DipLeTheme? { xemThu ?? dipThat.flatMap { DipLeTheme(rawValue: $0.ma) } }
    var tieuDe: String { xemThu?.ten ?? dipThat?.ten ?? "" }
    var moTa: String? { xemThu != nil ? nil : dipThat?.moTa }

    private static let khoaLuu = "dipLe.giaoDien"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.khoaLuu),
           let gd = try? JSONDecoder().decode(DipLeHienThi.GiaoDien.self, from: data),
           !Self.daHet(gd) {
            dipThat = gd
        }
        apDung()
    }

    /// Bản lưu máy đã quá ngày kết thúc (lâu không mở app) thì bỏ, khỏi hiện màu dịp cũ trong lúc chờ server.
    private static func daHet(_ gd: DipLeHienThi.GiaoDien) -> Bool {
        guard let kt = gd.ngayKetThuc?.prefix(10) else { return false }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 7 * 3600)
        guard let ngay = f.date(from: String(kt)) else { return false }
        return Date() >= ngay.addingTimeInterval(86_400)
    }

    private var daApDung: DipLeTheme?

    private func apDung() {
        DipLeMau.hienTai = active?.primary ?? Self.mauMacDinh
        if daApDung != active { daApDung = active; phienBan += 1 }
    }

    /// Gọi lúc mở app và mỗi lần quay lại app. Lỗi mạng: giữ nguyên trạng thái cũ.
    func load() async {
        guard let url = URL(string: Prefs.apiBase + "/api/dat-hang/dip-le/hien-thi") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let env = try? JSONDecoder().decode(ApiEnvelope<DipLeHienThi>.self, from: data),
              env.isSuccess, let kq = env.data else { return }
        dipThat = kq.giaoDien.flatMap { DipLeTheme(rawValue: $0.ma) != nil ? $0 : nil }
        if let gd = dipThat, let luu = try? JSONEncoder().encode(gd) {
            UserDefaults.standard.set(luu, forKey: Self.khoaLuu)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.khoaLuu)
        }
        apDung()
        maIconServer = kq.maIconHienTai
        if xemThu == nil { doiIconTheoLich() }
        // Ảnh màn chào dịp sắp tới tải sẵn ngầm; dịp đang hiện thì chờ tải (tối đa 3s) để màn chào có ảnh ngay.
        if let ma = kq.maIcon, let u = kq.anhManChaoIcon, ma != kq.giaoDien?.ma {
            Task { await ManChaoCache.taiNeuCan(ma: ma, duongDan: u) }
        }
        if let gd = dipThat, gd.anhManChao != nil { await ManChaoCache.taiNeuCan(ma: gd.ma, duongDan: gd.anhManChao) }
    }

    /// Đổi icon SAU màn chào (giống app khách): dịp có doiIcon mà icon trên máy chưa khớp. Hết dịp KHÔNG đổi về icon
    /// thường — giữ tới dịp sau (mỗi lần đổi iOS hiện popup, đổi về rồi lại đổi = gấp đôi popup).
    func doiIconSauManChao() {
        if let xemThu { DipLeIcon.capNhat(ma: xemThu.ma, boQuaGianCach: true); return }
        doiIconTheoLich()
    }

    /// Icon theo lịch icon của server (cùng icon app khách đang hiện — 2026-11-08 chủ quán: "chưa đổi icon" khi app khách
    /// đã lên icon Nhà giáo mà app quản lý vẫn icon thường). iOS chỉ cho đổi khi app đang active → chờ chút sau khi mở.
    private var maIconServer: String? {
        get { UserDefaults.standard.string(forKey: "dipLe.maIconServer") }
        set { UserDefaults.standard.set(newValue, forKey: "dipLe.maIconServer") }
    }

    func doiIconTheoLich() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard xemThu == nil, UIApplication.shared.applicationState == .active else { return }
            DipLeIcon.capNhat(ma: maIconServer)
        }
    }

    /// Tắt xem thử → icon về theo dịp dipThat (không có dịp thì icon app quản lý).
    func tatXemThu() {
        xemThu = nil
        DipLeIcon.capNhat(ma: maIconServer, boQuaGianCach: true)
    }
}

/// Màu chủ đạo hiện tại — để ngoài DipLe (MainActor) cho mọi nơi đọc được, chỉ DipLe.apDung ghi.
enum DipLeMau {
    static var hienTai = Color(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255)
}

extension Color {
    /// Màu chủ đạo app — navy, hoặc màu dịp lễ trong cửa sổ giao diện (xem DipLe).
    static var brandPrimary: Color { DipLeMau.hienTai }
}

/// Đổi icon app sang AppIcon-<MA> (đóng gói sẵn, khai ở project.yml). iOS luôn hiện popup khi đổi, không tắt được —
/// giãn ≥7 ngày giữa 2 lần đổi dipThat (xem thử bỏ qua giãn cách).
enum DipLeIcon {
    static let soNgayToiThieu = 7
    private static let khoaLanDoiCuoi = "dipLe.iconLanDoiCuoi"
    private static let khoaLoi = "dipLe.iconLoi"
    /// Lỗi lần đổi icon gần nhất (hiện ở màn "Giao diện dịp lễ" để biết vì sao không đổi).
    static var loiGanNhat: String? { UserDefaults.standard.string(forKey: khoaLoi) }
    static let maCoIcon = Set(DipLeTheme.allCases.map(\.ma))

    @MainActor
    static func capNhat(ma: String?, boQuaGianCach: Bool = false) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let muon = ma.flatMap { maCoIcon.contains($0) ? "AppIcon-\($0)" : nil }
        guard UIApplication.shared.alternateIconName != muon else { return }
        if !boQuaGianCach, let cuoi = UserDefaults.standard.object(forKey: khoaLanDoiCuoi) as? Date,
           Date().timeIntervalSince(cuoi) < Double(soNgayToiThieu) * 86_400 { return }
        UIApplication.shared.setAlternateIconName(muon) { error in
            DispatchQueue.main.async {
                if let error {
                    UserDefaults.standard.set("\(muon ?? "icon chính"): \(error.localizedDescription)", forKey: khoaLoi)
                    return
                }
                UserDefaults.standard.removeObject(forKey: khoaLoi)
                UserDefaults.standard.set(Date(), forKey: khoaLanDoiCuoi)
            }
        }
    }
}

/// Ảnh màn chào tải từ server (/man-chao-dip-le/<MA>.jpg?v=hash), lưu Caches — cùng ảnh app khách.
enum ManChaoCache {
    private static func thuMuc() -> URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("man-chao", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func file(_ ma: String) -> URL { thuMuc().appendingPathComponent("\(ma).jpg") }
    private static func khoaPhienBan(_ ma: String) -> String { "manChao.v.\(ma)" }

    static func anh(ma: String) -> UIImage? { UIImage(contentsOfFile: file(ma).path) }

    /// `duongDan` nil = xem thử: luôn tải lại (thêm ?t= vượt cache Cloudflare).
    static func taiNeuCan(ma: String, duongDan: String?) async {
        let ud = UserDefaults.standard
        let coSan = FileManager.default.fileExists(atPath: file(ma).path)
        let path = duongDan ?? "/man-chao-dip-le/\(ma).jpg?t=\(Int(Date().timeIntervalSince1970))"
        let phienBan = URLComponents(string: path)?.queryItems?.first(where: { $0.name == "v" })?.value
        if coSan, duongDan != nil, ud.string(forKey: khoaPhienBan(ma)) == phienBan { return }
        guard let goc = URL(string: Prefs.apiBase), let url = URL(string: path, relativeTo: goc)?.absoluteURL else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              UIImage(data: data) != nil else { return }
        guard (try? data.write(to: file(ma), options: .atomic)) != nil else { return }
        if let phienBan { ud.set(phienBan, forKey: khoaPhienBan(ma)) }
    }
}

/// Màn chào 1,5s lúc mở app trong cửa sổ dịp lễ — giống app khách: ảnh nền từ server + logo + câu chúc; chưa có ảnh thì
/// icon dịp bo góc trên nền nhoè. Chạm để tắt.
struct DipLeManChaoView: View {
    let theme: DipLeTheme
    let tieuDe: String
    let moTa: String?
    let onDone: () -> Void

    @State private var visible = false

    var body: some View {
        ZStack {
            if let anh = ManChaoCache.anh(ma: theme.ma) {
                anhRieng(anh)
            } else {
                duPhong
            }
        }
        .opacity(visible ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { visible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { dismiss() }
        }
    }

    private func anhRieng(_ anh: UIImage) -> some View {
        GeometryReader { geo in
            Image(uiImage: anh).resizable().scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height).clipped()
            Image("LogoDenn").resizable().scaledToFit()
                .frame(width: geo.size.width * 0.58)
                .shadow(color: .black.opacity(0.28), radius: 6, y: 1)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.30)
            chuChuc
                .frame(width: geo.size.width)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.50)
        }
        .ignoresSafeArea()
    }

    private var duPhong: some View {
        ZStack {
            if let nen = UIImage(named: "DipLeNen-\(theme.ma)") {
                Color.clear.overlay(Image(uiImage: nen).resizable().scaledToFill()).clipped().ignoresSafeArea()
                LinearGradient(colors: [.black.opacity(0.25), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            } else {
                theme.primary.ignoresSafeArea()
            }
            VStack(spacing: 14) {
                if let anh = UIImage(named: "DipLe-\(theme.ma)") {
                    Image(uiImage: anh).resizable().scaledToFit()
                        .frame(maxWidth: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
                        .padding(.bottom, 10)
                }
                chuChuc
            }
        }
    }

    private var chuChuc: some View {
        VStack(spacing: 10) {
            Text(tieuDe)
                .font(.system(size: 28, weight: .heavy))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            if let moTa, !moTa.isEmpty {
                Text(moTa)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 36)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    private func dismiss() {
        guard visible else { return }
        withAnimation(.easeIn(duration: 0.25)) { visible = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { onDone() }
    }
}

/// Menu → "Giao diện dịp lễ": xem thử màu + màn chào + icon của 15 dịp (không lưu, mở lại app là về dịp dipThat).
struct DipLeXemThuView: View {
    @ObservedObject private var dipLe = DipLe.shared

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Đang dùng")
                    Spacer()
                    Text(dipLe.active?.ten ?? "Giao diện thường").foregroundStyle(.secondary)
                }
                if dipLe.xemThu != nil {
                    Button("Tắt xem thử") { dipLe.tatXemThu() }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Màu và màn chào: từ 2 ngày trước lễ đến hết ngày lễ. Icon: cùng icon app khách đang hiện (đổi trước lễ ~30 ngày). Chạm một dịp để xem thử (đổi cả icon).")
                    Text("Icon hiện tại: \(UIApplication.shared.alternateIconName ?? "icon chính")")
                    if let loi = DipLeIcon.loiGanNhat { Text("Lỗi đổi icon: \(loi)").foregroundStyle(.red) }
                }
            }
            Section("Xem thử") {
                ForEach(DipLeTheme.allCases) { t in
                    Button {
                        Task {
                            await ManChaoCache.taiNeuCan(ma: t.ma, duongDan: nil)
                            dipLe.xemThu = t
                            NotificationCenter.default.post(name: .xemThuManChaoDipLe, object: nil)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Circle().fill(t.primary).frame(width: 18, height: 18)
                            Text(t.ten).foregroundStyle(.primary)
                            Spacer()
                            if dipLe.xemThu == t { Image(systemName: "checkmark").foregroundStyle(t.primary) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Giao diện dịp lễ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Notification.Name {
    static let xemThuManChaoDipLe = Notification.Name("xemThuManChaoDipLe")
}
