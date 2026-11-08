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

/// GET /api/dat-hang/dip-le/hien-thi — app quản lý chỉ dùng `dipQuanLy`.
struct DipLeHienThi: Decodable {
    struct Dip: Codable {
        let ma: String
        let ten: String
        let moTa: String?
        let anhManChao: String?
        let ngayKetThuc: String?
    }
    /// Dịp CHƯA KẾT THÚC gần nhất (server DipLeLich.QuanLy) — chủ quán 2026-11-08: "hiện icon, giao diện, màn chào từ đây
    /// đến hết 20/11, sau 20/11 thì hiện Noel", không chờ cửa sổ 2 ngày như app khách.
    let dipQuanLy: Dip?
}

/// Trạng thái dịp lễ toàn app. `Color.brandPrimary` đọc `DipLeMau.hienTai` (static, đọc được ở mọi nơi kể cả ngoài
/// MainActor); ContentView quan sát `phienBan` và dựng lại cây view khi đổi dịp để mọi màn ăn màu mới.
@MainActor
final class DipLe: ObservableObject {
    static let shared = DipLe()

    static let mauMacDinh = Color(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255)

    /// Dịp từ server (lưu máy để mở app là đúng màu ngay, không nháy navy → màu dịp).
    @Published private(set) var dip: DipLeHienThi.Dip?
    /// Đổi mỗi khi màu chủ đạo đổi — ContentView dùng làm .id để vẽ lại toàn bộ.
    @Published private(set) var phienBan = 0

    private var dipTheme: DipLeTheme? { dip.flatMap { DipLeTheme(rawValue: $0.ma) } }
    var active: DipLeTheme? { dipTheme }
    var tieuDe: String { dip?.ten ?? "" }
    var moTa: String? { dip?.moTa }

    private static let khoaLuu = "dipLe.dipQuanLy"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.khoaLuu),
           let d = try? JSONDecoder().decode(DipLeHienThi.Dip.self, from: data),
           !Self.daHet(d) {
            dip = d
        }
        apDung()
    }

    /// Bản lưu máy đã quá ngày kết thúc (lâu không mở app) thì bỏ, khỏi hiện dịp cũ trong lúc chờ server.
    private static func daHet(_ d: DipLeHienThi.Dip) -> Bool {
        guard let kt = d.ngayKetThuc?.prefix(10) else { return false }
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
        dip = kq.dipQuanLy.flatMap { DipLeTheme(rawValue: $0.ma) != nil ? $0 : nil }
        if let d = dip, let luu = try? JSONEncoder().encode(d) {
            UserDefaults.standard.set(luu, forKey: Self.khoaLuu)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.khoaLuu)
        }
        apDung()
        doiIconTheoDip()
        // Chờ tải ảnh màn chào (tối đa 3s) để màn chào lúc mở app có ảnh ngay.
        if let d = dip { await ManChaoCache.taiNeuCan(ma: d.ma, duongDan: d.anhManChao ?? "/man-chao-dip-le/\(d.ma).jpg") }
    }

    /// Icon theo dịp server trả. iOS chỉ cho đổi khi app đang active → chờ chút sau khi mở.
    func doiIconTheoDip() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard UIApplication.shared.applicationState == .active else { return }
            DipLeIcon.capNhat(ma: dip?.ma)
        }
    }
}

/// Màu chủ đạo hiện tại — để ngoài DipLe (MainActor) cho mọi nơi đọc được, chỉ DipLe.apDung ghi.
enum DipLeMau {
    static var hienTai = Color(red: 0x1E / 255, green: 0x4E / 255, blue: 0x8C / 255)
}

extension Color {
    /// Màu chủ đạo app — navy, hoặc màu dịp lễ (xem DipLe.active).
    static var brandPrimary: Color { DipLeMau.hienTai }
}

/// Đổi icon app sang AppIcon-<MA> (đóng gói sẵn, khai ở project.yml). iOS luôn hiện popup khi đổi, không tắt được.
/// Không giãn cách như app khách — app quản lý đổi đúng ngày sang dịp (chủ quán 2026-11-08).
enum DipLeIcon {
    static let maCoIcon = Set(DipLeTheme.allCases.map(\.ma))

    @MainActor
    static func capNhat(ma: String?) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let muon = ma.flatMap { maCoIcon.contains($0) ? "AppIcon-\($0)" : nil }
        guard UIApplication.shared.alternateIconName != muon else { return }
        UIApplication.shared.setAlternateIconName(muon) { error in
            if let error { print("[DipLeIcon] đổi icon \(muon ?? "chính") lỗi: \(error)") }
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
