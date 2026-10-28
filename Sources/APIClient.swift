import Foundation
import UIKit

/// Port 1:1 từ AppMobileAndroid/ApiClient.kt (OkHttp+Gson → URLSession+Codable). Bearer token
/// tự đính kèm, tự refresh 1 lần khi gặp 401 rồi retry đúng request gốc — khớp hành vi
/// authenticator bên Android.
actor APIClient {
    static let shared = APIClient()

    private func jsonBody<T: Encodable>(_ obj: T) -> Data {
        try! JSONEncoder().encode(obj)
    }

    private func makeRequest(_ path: String, method: String = "GET", body: Data? = nil, authorized: Bool = true) -> URLRequest {
        var req = URLRequest(url: URL(string: Prefs.apiBase + path)!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authorized, let token = Prefs.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }

    // Refresh đang chạy dở (nếu có) — nhiều màn hình bắn request song song trên cùng actor này (vd.
    // ThongKeView.load() gọi 8 endpoint /api/ThongKe cùng lúc bằng "async let"). actor Swift MẶC ĐỊNH
    // reentrant tại các điểm await — nếu cả 8 request cùng dính 401 (token hết hạn), mỗi request tự
    // gọi doRefresh() riêng thì y hệt lỗi từng gặp bên AppShipperAndroid: backend xoay vòng refresh
    // token kiểu one-time-use (AuthService.RefreshAsync ghi đè TokenHash ngay khi dùng), request thắng
    // race lưu token mới xong thì các request thua bị BE từ chối refresh token cũ (đã tiêu) → 401 →
    // Prefs.clear() xoá sạch luôn token mới vừa refresh thành công, bắt đăng xuất dù phiên còn sống.
    // Gộp lại 1 Task refresh dùng chung: request đến sau thấy đang có refresh dở thì CHỜ kết quả đó
    // thay vì tự gọi network riêng.
    private var refreshTask: Task<String?, Never>?

    private func send(_ req: URLRequest, allowRefresh: Bool = true) async -> (Data?, HTTPURLResponse?) {
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let http = resp as? HTTPURLResponse
            // Thanh "Không kết nối được máy chủ" (KetNoiMayChu) — 52x/502-504 = Cloudflare không tới được VPS.
            if let song = KetNoiMayChu.phanLoai(status: http?.statusCode, error: nil) {
                song ? KetNoiMayChu.baoThanhCong() : KetNoiMayChu.baoThatBai()
            }
            if http?.statusCode == 401, allowRefresh {
                let usedToken = req.value(forHTTPHeaderField: "Authorization")?
                    .replacingOccurrences(of: "Bearer ", with: "")
                if let newToken = await refreshTokenCoalesced(previousToken: usedToken) {
                    var retried = req
                    retried.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    return await send(retried, allowRefresh: false)
                }
                // Refresh thất bại thật (token bị thu hồi/hết hạn ở nơi khác) — không có gì tự cứu
                // được nữa, phải đưa app quay về màn hình login thay vì để lỗi 401 lặng lẽ.
                Prefs.clear()
                NotificationCenter.default.post(name: .sessionExpired, object: nil)
            }
            return (data, http)
        } catch {
            if KetNoiMayChu.phanLoai(status: nil, error: error) == false { KetNoiMayChu.baoThatBai() }
            return (nil, nil)
        }
    }

    /// Double-check trước khi refresh: nếu token hiện tại đã khác token vừa dùng lúc 401 nghĩa là 1
    /// request khác vừa refresh xong — dùng luôn, khỏi gọi /api/auth/refresh thừa. Nếu chưa có ai
    /// refresh, request đầu tiên tạo Task, các request đến sau (kể cả do actor reentrant) chỉ await
    /// chung Task đó thay vì tạo Task/network call mới.
    private func refreshTokenCoalesced(previousToken: String?) async -> String? {
        if let current = Prefs.token, !current.isEmpty, current != previousToken { return current }

        if let existing = refreshTask {
            return await existing.value
        }

        guard let refreshToken = Prefs.refreshToken else { return nil }
        let task = Task<String?, Never> { await self.doRefresh(refreshToken) }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func doRefresh(_ refreshToken: String) async -> String? {
        let req = makeRequest("/api/auth/refresh", method: "POST",
                               body: jsonBody(RefreshRequest(refreshToken: refreshToken, thietBi: deviceName(), nenTang: "iOS", thietBiId: deviceId())),
                               authorized: false)
        let (data, http) = await send(req, allowRefresh: false)
        guard let data, http?.statusCode == 200,
              let env = try? JSONDecoder().decode(ApiEnvelope<LoginResponse>.self, from: data),
              env.isSuccess, let resp = env.data, let token = resp.token else { return nil }
        Prefs.saveSession(token: token, refreshToken: resp.refreshToken, displayName: resp.tenHienThi)
        return token
    }

    func login(taiKhoan: String, matKhau: String) async -> LoginResult {
        let req = makeRequest("/api/auth/login", method: "POST",
                               body: jsonBody(LoginRequest(taiKhoan: taiKhoan, matKhau: matKhau, thietBi: deviceName(), nenTang: "iOS", thietBiId: deviceId())),
                               authorized: false)
        let (data, _) = await send(req, allowRefresh: false)
        guard let data else { return .networkError }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<LoginResponse>.self, from: data) else { return .networkError }
        if !env.isSuccess { return .rejected(env.message ?? "Sai tài khoản hoặc mật khẩu.") }
        guard let resp = env.data else { return .networkError }
        return .success(resp)
    }

    private func deviceName() -> String {
        UIDevice.current.name
    }

    /// Định danh ổn định của máy (khác deviceName() — tên máy do người dùng đặt, dễ trùng nếu 2 máy
    /// cùng chưa đổi tên mặc định "iPhone", từng khiến backend dedupe nhầm 2 máy là 1, thu hồi phiên
    /// lẫn nhau — xem incident_ios_multidevice_same_name_session_kick). identifierForVendor ổn định
    /// qua các lần mở app, chỉ đổi nếu gỡ hết app của cùng vendor.
    private func deviceId() -> String? {
        UIDevice.current.identifierForVendor?.uuidString
    }

    // Danh sách/gỡ thiết bị đăng nhập — màn hình "Thiết bị đăng nhập" trong MoreMenuView.
    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getSessionsOrNil() async -> [PhienDangNhapDto]? {
        let req = makeRequest("/api/Auth/sessions")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[PhienDangNhapDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getSessions() async -> [PhienDangNhapDto] { await getSessionsOrNil() ?? [] }

    /// "Phiên bản app khách" (Trợ lý ảo > App Đặt Hàng) — thiết bị khách + bản app đang chạy.
    func getPhienBanAppKhach() async -> [KhachHangPhienBanAppDto] {
        let req = makeRequest("/api/KhachHang/phien-ban-app")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangPhienBanAppDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func revokeSession(id: String) async -> ActionResult {
        let req = makeRequest("/api/Auth/sessions/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Đăng ký APNs device token của thiết bị hiện tại (hoặc gỡ nếu token=nil) — dùng nhận push "Đơn
    /// mới". Gọi sau login và mỗi lần mở app khi đã đăng nhập sẵn (token APNs có thể đổi).
    func registerApnsDeviceToken(_ token: String?) async -> ActionResult {
        let req = makeRequest("/api/Auth/device-token", method: "PUT",
                               body: jsonBody(["apnsDeviceToken": token]))
        return await executeAction(req)
    }

    /// nil = tải LỖI (mất mạng/decode hỏng), khác với [] = ngày đó thật sự không có đơn — caller
    /// phải phân biệt, không được hiện "Không có hoá đơn nào" khi chỉ là rớt mạng.
    func getHoaDonListByDay(_ dateIso: String) async -> [HoaDonListDto]? {
        let req = makeRequest("/api/dashboard/hoa-don-list?ngay=\(dateIso)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    /// nil = tải LỖI, khác với [] = thật sự không còn ai nợ — caller KHÔNG được hiện "hết nợ"/0đ
    /// khi chỉ là rớt mạng (xem getHoaDonListByDay).
    func getCongNoList() async -> [HoaDonListDto]? {
        let req = makeRequest("/api/dashboard/cong-no-list")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    /// Số dư ví OpenRouter + model đang dùng cho từng tính năng AI — tab Menu.
    func getAiBalance() async -> AiBalanceDto? {
        let req = makeRequest("/api/dashboard/ai-balance")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<AiBalanceDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Số dư Zalo OTP (ZBS Account) sau lần gửi OTP gần nhất — tab Menu, dưới số dư AI.
    func getZaloBalance() async -> ZaloBalanceDto? {
        let req = makeRequest("/api/dashboard/zalo-balance")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<ZaloBalanceDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Đặt lại số dư Zalo OTP theo số trên trang Zalo (Zalo không có API hỏi số dư).
    func setZaloBalance(_ soDu: Int64) async -> ZaloBalanceDto? {
        let req = makeRequest("/api/dashboard/zalo-balance", method: "PUT", body: jsonBody(["soDu": soDu]))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<ZaloBalanceDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// nil = tải LỖI, khác với [] = ngày đó không có thanh toán nào (xem getHoaDonListByDay).
    func getThanhToanByDay(_ dateIso: String) async -> [ChiTietHoaDonThanhToanDto]? {
        let req = makeRequest("/api/ChiTietHoaDonThanhToan?ngay=\(dateIso)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ChiTietHoaDonThanhToanDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    /// nil = tải LỖI, khác với [] = ngày đó không có chi tiêu nào (xem getHoaDonListByDay).
    func getChiTieuByDay(_ dateIso: String) async -> [ChiTieuHangNgayDto]? {
        let req = makeRequest("/api/ChiTieuHangNgay?ngay=\(dateIso)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ChiTieuHangNgayDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getChiTieuByMonth(year: Int, month: Int) async -> [ChiTieuHangNgayDto] {
        let req = makeRequest("/api/ChiTieuHangNgay/month?year=\(year)&month=\(month)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ChiTieuHangNgayDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getTaiKhoan() async -> [TaiKhoanDto] {
        let (data, _) = await send(makeRequest("/api/TaiKhoan"))
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[TaiKhoanDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Công cụ "Giá nguyên liệu gần đây" (Menu > Công cụ) — N lần mua gần nhất của 1 nguyên liệu.
    func getGiaNguyenLieuGanDay(nguyenLieuId: String, soLan: Int = 3) async -> [ChiTieuHangNgayDto] {
        let req = makeRequest("/api/ChiTieuHangNgay/gia-gan-day?nguyenLieuId=\(nguyenLieuId)&soLan=\(soLan)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ChiTieuHangNgayDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Danh sách nguyên liệu cần mua sắp tới (đến hạn/trễ hạn), gấp nhất trước — tính bằng công thức, không AI.
    func getCanMua() async -> [MuaHangDeXuatDto] {
        let req = makeRequest("/api/ChiTieuHangNgay/can-mua")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[MuaHangDeXuatDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Đề xuất ngày mua tiếp theo (AI đọc lịch sử mua) — nil nếu chưa đủ lịch sử hoặc lỗi.
    func getDeXuatMua(nguyenLieuId: String) async -> MuaHangDeXuatDto? {
        let req = makeRequest("/api/ChiTieuHangNgay/de-xuat-mua?nguyenLieuId=\(nguyenLieuId)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<MuaHangDeXuatDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Bật/tắt "ngừng sử dụng" nguyên liệu (PATCH riêng, không ghi đè field khác).
    func setNguyenLieuNgungSuDung(id: String, value: Bool) async -> Bool {
        let req = makeRequest("/api/NguyenLieu/\(id)/ngung-su-dung?value=\(value)", method: "PATCH")
        return await executeAction(req).success
    }

    /// Bật/tắt giỏ Shopee của nguyên liệu (PATCH riêng, không qua Update để không ghi đè các field khác).
    func setNguyenLieuMuaShopee(id: String, value: Bool) async -> Bool {
        let req = makeRequest("/api/NguyenLieu/\(id)/mua-shopee?value=\(value)", method: "PATCH")
        return await executeAction(req).success
    }

    /// Bật/tắt "đang quản lý số lượng realtime" của nguyên liệu (PATCH riêng).
    func setNguyenLieuQuanLyTonKho(id: String, value: Bool) async -> Bool {
        let req = makeRequest("/api/NguyenLieu/\(id)/quan-ly-ton-kho?value=\(value)", method: "PATCH")
        return await executeAction(req).success
    }

    /// Bật/tắt "Nổi bật" cho món (dải "Món quán đề xuất" đầu tab Thực đơn app khách, thứ tự hiện
    /// random mỗi lần tải) — trả cả message để hiện lỗi nếu server từ chối.
    func setSanPhamNoiBat(id: String, value: Bool) async -> ActionResult {
        let req = makeRequest("/api/SanPham/\(id)/noi-bat?value=\(value)", method: "PATCH")
        return await executeAction(req)
    }

    func createChiTieu(_ body: ChiTieuHangNgayCreateRequest) async -> ActionResult {
        let req = makeRequest("/api/ChiTieuHangNgay", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    /// Đọc ảnh hoá đơn qua Gemini — multipart/form-data field "image". Không dùng makeRequest (JSON
    /// mặc định), tự dựng multipart body rồi gọi chung send() để có sẵn refresh-token/retry 401.
    func parseReceipt(imageData: Data, mimeType: String = "image/jpeg") async -> (result: ReceiptParseResultDto?, message: String?) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"receipt.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: Prefs.apiBase + "/api/ChiTieuHangNgay/parse-receipt")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = Prefs.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body

        let (data, _) = await send(req)
        guard let data else { return (nil, "Không có phản hồi từ server.") }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<ReceiptParseResultDto>.self, from: data) else {
            return (nil, "Không đọc được phản hồi từ server.")
        }
        return (env.data, env.isSuccess ? nil : (env.message ?? "Đọc ảnh thất bại."))
    }

    /// Khớp nguyên liệu cho dòng hàng đã có chữ sẵn (đơn Shopee) — cùng thuật toán parseReceipt, không qua AI.
    func matchReceiptLines(_ lines: [ReceiptMatchLineRequest]) async -> (result: ReceiptParseResultDto?, message: String?) {
        let req = makeRequest("/api/ChiTieuHangNgay/match-lines", method: "POST", body: jsonBody(ReceiptMatchRequest(lines: lines)))
        let (data, _) = await send(req)
        guard let data else { return (nil, "Không có phản hồi từ server.") }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<ReceiptParseResultDto>.self, from: data) else {
            return (nil, "Không đọc được phản hồi từ server.")
        }
        return (env.data, env.isSuccess ? nil : (env.message ?? "Không khớp được nguyên liệu."))
    }

    /// Mã đơn Shopee nào đã nhập chi tiêu (cột NguonShopeeOrderId) — đánh dấu "Đã nhập" ở ShopeeImportView.
    func shopeeDaNhap(_ orderIds: [String]) async -> Set<String> {
        let req = makeRequest("/api/ChiTieuHangNgay/shopee-da-nhap", method: "POST", body: jsonBody(ShopeeDaNhapRequest(orderIds: orderIds)))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[String]>.self, from: data) else { return [] }
        return Set(env.data ?? [])
    }

    /// Mã các đơn Shopee nhập gần đây nhất (mới nhất trước) — ShopeeImportView đọc đơn Shopee tới khi
    /// gặp 1 mã trong đây thì dừng. Rỗng nếu chưa nhập đơn nào hoặc lỗi mạng (khi đó đọc 30 ngày).
    func shopeeDonGanDay() async -> [String] {
        let (data, _) = await send(makeRequest("/api/ChiTieuHangNgay/shopee-don-gan-day"))
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[String]>.self, from: data) else { return [] }
        return env.data ?? []
    }

    /// "Bắt đơn từ ảnh" — multipart/form-data nhiều field "images" (1-nhiều ảnh cùng 1 cuộc hội thoại,
    /// vd chụp cuộn màn hình). Cùng cách dựng body với parseReceipt(), chỉ khác nhiều field ảnh.
    func parseOrderImages(images: [Data]) async -> (result: OrderFromImageResultDto?, message: String?) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (i, imageData) in images.enumerated() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"images\"; filename=\"chat\(i).jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: Prefs.apiBase + "/api/HoaDon/parse-order-images")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = Prefs.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body

        let (data, _) = await send(req)
        guard let data else { return (nil, "Không có phản hồi từ server.") }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<OrderFromImageResultDto>.self, from: data) else {
            return (nil, "Không đọc được phản hồi từ server.")
        }
        return (env.data, env.isSuccess ? nil : (env.message ?? "Đọc ảnh thất bại."))
    }

    /// "Bắt đơn từ tin nhắn" — text đã copy sẵn (clipboard) thay vì ảnh, cùng kết quả trả về với
    /// parseOrderImages().
    func parseOrderText(_ text: String) async -> (result: OrderFromImageResultDto?, message: String?) {
        let req = makeRequest("/api/HoaDon/parse-order-text", method: "POST", body: jsonBody(["text": text]))
        let (data, _) = await send(req)
        guard let data else { return (nil, "Không có phản hồi từ server.") }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<OrderFromImageResultDto>.self, from: data) else {
            return (nil, "Không đọc được phản hồi từ server.")
        }
        return (env.data, env.isSuccess ? nil : (env.message ?? "Đọc tin nhắn thất bại."))
    }

    /// Đổi/thêm ảnh món — multipart/form-data field "image", cùng cách dựng body với parseReceipt().
    /// Backend lưu vào wwwroot/menu-images, trả về URL ảnh mới (data: String) để cập nhật UI ngay
    /// không cần tải lại cả danh sách.
    func uploadSanPhamHinhAnh(id: String, imageData: Data, mimeType: String = "image/jpeg") async -> (url: String?, message: String?) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"menu.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: Prefs.apiBase + "/api/SanPham/\(id)/hinh-anh")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = Prefs.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body

        let (data, _) = await send(req)
        guard let data else { return (nil, "Không có phản hồi từ server.") }
        guard let env = try? JSONDecoder().decode(ApiEnvelope<String>.self, from: data) else {
            return (nil, "Không đọc được phản hồi từ server.")
        }
        return (env.data, env.isSuccess ? nil : (env.message ?? "Cập nhật ảnh thất bại."))
    }

    func bulkCreateChiTieu(_ body: ChiTieuHangNgayBulkCreateRequest) async -> ActionResult {
        let req = makeRequest("/api/ChiTieuHangNgay/bulk", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateChiTieu(id: String, _ body: ChiTieuHangNgayCreateRequest) async -> ActionResult {
        let req = makeRequest("/api/ChiTieuHangNgay/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteChiTieu(id: String) async -> ActionResult {
        let req = makeRequest("/api/ChiTieuHangNgay/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    func deleteThanhToan(id: String) async -> ActionResult {
        let req = makeRequest("/api/ChiTietHoaDonThanhToan/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    func doiPhuongThucThanhToan(id: String) async -> ActionResult {
        let req = makeRequest("/api/ChiTietHoaDonThanhToan/\(id)/doi-phuong-thuc", method: "PUT")
        return await executeAction(req)
    }

    /// Bật/tắt ⭐ nguyên liệu bán hàng (PATCH riêng, không ghi đè field khác).
    func setNguyenLieuBanHangYeuThich(id: String, value: Bool) async -> Bool {
        let req = makeRequest("/api/NguyenLieuBanHang/\(id)/yeu-thich?value=\(value)", method: "PATCH")
        return await executeAction(req).success
    }

    /// Điều chỉnh tồn kho theo kiểm kê — ghi đè số tồn thực tế, không tự cộng/trừ.
    func dieuChinhTonKho(id: String, tonKhoThucTe: Double, ghiChu: String?) async -> ActionResult {
        let body = DieuChinhTonKhoRequest(tonKhoThucTe: tonKhoThucTe, ghiChu: ghiChu)
        let req = makeRequest("/api/NguyenLieuBanHang/\(id)/adjust", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getNguyenLieuBanHangOrNil() async -> [NguyenLieuBanHangDto]? {
        let req = makeRequest("/api/NguyenLieuBanHang?take=1000")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[NguyenLieuBanHangDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getNguyenLieuBanHang() async -> [NguyenLieuBanHangDto] { await getNguyenLieuBanHangOrNil() ?? [] }

    // ---- Công thức / Định lượng (quản trị — CongThucListView, thay CongThucWindow bên Desktop) ----

    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getCongThucListOrNil() async -> [CongThucDto]? {
        let req = makeRequest("/api/CongThuc")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[CongThucDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getCongThucList() async -> [CongThucDto] { await getCongThucListOrNil() ?? [] }

    func createCongThuc(_ body: CongThucDto) async -> CreateActionResult {
        let req = makeRequest("/api/CongThuc", method: "POST", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<IdOnlyDto>.self, from: data) else {
            return CreateActionResult(success: false, message: "Không có phản hồi từ server.", id: nil)
        }
        return CreateActionResult(success: env.isSuccess, message: env.message, id: env.data?.id)
    }

    func updateCongThuc(id: String, _ body: CongThucDto) async -> ActionResult {
        let req = makeRequest("/api/CongThuc/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteCongThuc(id: String) async -> ActionResult {
        let req = makeRequest("/api/CongThuc/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Màn Duyệt công thức L/XL — nil = tải LỖI.
    func getCongThucDuyetSizeOrNil() async -> [CongThucDuyetSizeDto]? {
        let req = makeRequest("/api/CongThuc/duyet-size")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[CongThucDuyetSizeDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func duyetCongThuc(id: String) async -> ActionResult {
        let req = makeRequest("/api/CongThuc/\(id)/duyet", method: "POST")
        return await executeAction(req)
    }

    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getSuDungNguyenLieuListOrNil() async -> [SuDungNguyenLieuDto]? {
        let req = makeRequest("/api/SuDungNguyenLieu")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[SuDungNguyenLieuDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getSuDungNguyenLieuList() async -> [SuDungNguyenLieuDto] { await getSuDungNguyenLieuListOrNil() ?? [] }

    func createSuDungNguyenLieu(_ body: SuDungNguyenLieuDto) async -> ActionResult {
        let req = makeRequest("/api/SuDungNguyenLieu", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateSuDungNguyenLieu(id: String, _ body: SuDungNguyenLieuDto) async -> ActionResult {
        let req = makeRequest("/api/SuDungNguyenLieu/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteSuDungNguyenLieu(id: String) async -> ActionResult {
        let req = makeRequest("/api/SuDungNguyenLieu/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Nguyên liệu NHẬP dùng cho form Thêm chi tiêu — khớp desktop ChiTieuInputPanel (GET /api/NguyenLieu).
    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getNguyenLieuOrNil() async -> [NguyenLieuDto]? {
        let req = makeRequest("/api/NguyenLieu")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[NguyenLieuDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getNguyenLieu() async -> [NguyenLieuDto] { await getNguyenLieuOrNil() ?? [] }

    /// Thêm nguyên liệu mới ngay trong form Thêm chi tiêu — chỉ Ten là bắt buộc phía server
    /// (NguyenLieuService.CreateAsync), các field khác server tự để mặc định (0/false/null).
    func createNguyenLieu(ten: String) async -> (success: Bool, message: String?, nguyenLieu: NguyenLieuDto?) {
        let body = NguyenLieuCreateRequest(ten: ten)
        let req = makeRequest("/api/NguyenLieu", method: "POST", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<NguyenLieuDto>.self, from: data) else {
            return (false, "Không có phản hồi từ server.", nil)
        }
        return (env.isSuccess, env.message, env.data)
    }

    /// Cập nhật nguyên liệu (NguyenLieuEditSheet) — chỉnh Ten/DonViTinh/GiaNhap/NgungSuDung/Nhóm chi
    /// tiêu đầy đủ (khác createNguyenLieu(ten:) chỉ thêm nhanh 1 field).
    func createNguyenLieuFull(_ body: NguyenLieuUpdateRequest) async -> ActionResult {
        let req = makeRequest("/api/NguyenLieu", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateNguyenLieu(id: String, _ body: NguyenLieuUpdateRequest) async -> ActionResult {
        let req = makeRequest("/api/NguyenLieu/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteNguyenLieu(id: String) async -> ActionResult {
        let req = makeRequest("/api/NguyenLieu/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    // ---- Sản phẩm (quản trị — SanPhamListView, thay SanPhamWindow bên Desktop) ----

    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getSanPhamAdminOrNil() async -> [SanPhamAdminDto]? {
        let req = makeRequest("/api/SanPham")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[SanPhamAdminDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getSanPhamAdmin() async -> [SanPhamAdminDto] { await getSanPhamAdminOrNil() ?? [] }

    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getNhomSanPhamOrNil() async -> [NhomSanPhamDto]? {
        let req = makeRequest("/api/NhomSanPham")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[NhomSanPhamDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getNhomSanPham() async -> [NhomSanPhamDto] { await getNhomSanPhamOrNil() ?? [] }

    func createSanPham(_ body: SanPhamAdminDto) async -> ActionResult {
        let req = makeRequest("/api/SanPham", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateSanPham(id: String, _ body: SanPhamAdminDto) async -> ActionResult {
        let req = makeRequest("/api/SanPham/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteSanPham(id: String) async -> ActionResult {
        let req = makeRequest("/api/SanPham/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// So sánh & lưu tình trạng store cho TOÀN BỘ sản phẩm — khớp nút "Kiểm tra Store" bên Desktop.
    func syncSanPhamStoreStatus() async -> ActionResult {
        let req = makeRequest("/api/AppOrder/sync-store-status", method: "POST", body: jsonBody([String: String]()))
        return await executeAction(req)
    }

    func pushSanPhamToStore(_ body: PushSanPhamToStoreRequest) async -> ActionResult {
        let req = makeRequest("/api/AppOrder/push-san-pham", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func renameSanPhamOnStore(id: String) async -> ActionResult {
        let req = makeRequest("/api/AppOrder/rename-san-pham/\(id)", method: "POST", body: jsonBody([String: String]()))
        return await executeAction(req)
    }

    func toggleSanPhamStoreVisibility(id: String, ngungBan: Bool) async -> ActionResult {
        let req = makeRequest("/api/AppOrder/store-visibility/\(id)?ngungBan=\(ngungBan)", method: "POST", body: jsonBody([String: String]()))
        return await executeAction(req)
    }

    func pushToppingToStore(id: String) async -> ActionResult {
        let req = makeRequest("/api/AppOrder/push-topping/\(id)", method: "POST", body: jsonBody([String: String]()))
        return await executeAction(req)
    }

    /// Đẩy/đồng bộ topping cho TẤT CẢ sản phẩm đã có trên store — chạy nền bên Backend (có thể mất
    /// vài chục phút), kết quả báo qua thông báo Hệ thống (icon chuông) chứ không trả về ngay trong request này.
    func pushToppingAllToStore() async -> ActionResult {
        let req = makeRequest("/api/AppOrder/push-topping-all", method: "POST", body: jsonBody([String: String]()))
        return await executeAction(req)
    }

    /// Đẩy/đồng bộ biến thể "Size XL" (giá chênh cố định) lên 1 món đã có trên store VÀ đã có biến
    /// thể Size XL nội bộ.
    func pushSizeXLToStore(id: String) async -> ActionResult {
        let req = makeRequest("/api/AppOrder/push-size-xl/\(id)", method: "POST", body: jsonBody([String: String]()))
        return await executeAction(req)
    }

    /// Đẩy Size XL cho TẤT CẢ sản phẩm đủ điều kiện (đã lên store + có Size XL nội bộ) — chạy nền,
    /// báo qua thông báo Hệ thống, khớp pushToppingAllToStore.
    func pushSizeXLAllToStore() async -> ActionResult {
        let req = makeRequest("/api/AppOrder/push-size-xl-all", method: "POST", body: jsonBody([String: String]()))
        return await executeAction(req)
    }

    /// nil = tải LỖI, khác với [] = chưa có việc nào (xem getHoaDonListByDay).
    func getCongViecList() async -> [CongViecNoiBoDto]? {
        let req = makeRequest("/api/CongViecNoiBo")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[CongViecNoiBoDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func createCongViec(ten: String) async -> ActionResult {
        let body = CongViecNoiBoRequest(ten: ten, daHoanThanh: false, ngayGio: isoNow())
        let req = makeRequest("/api/CongViecNoiBo", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    /// Việc nên làm sớm theo lịch sử làm (AI/thống kê) — rỗng nếu chưa đủ lịch sử hoặc lỗi.
    func getCongViecDeXuat() async -> [CongViecDeXuatDto] {
        let req = makeRequest("/api/CongViecNoiBo/de-xuat")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[CongViecDeXuatDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func updateCongViec(id: String, ten: String, daHoanThanh: Bool, ngayGio: String?) async -> ActionResult {
        let body = CongViecNoiBoRequest(ten: ten, daHoanThanh: daHoanThanh, ngayGio: ngayGio)
        let req = makeRequest("/api/CongViecNoiBo/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    // Lịch sử thông báo nội bộ (icon chuông, tab Hoá đơn) — thay Discord từ 2026-10-03.
    /// before = taoLuc (nguyên chuỗi server trả) của dòng cuối trang trước — cuộn xuống tải trang kế.
    func getThongBaoNoiBoList(take: Int = 50, before: String? = nil) async -> [ThongBaoNoiBoDto] {
        var path = "/api/ThongBaoNoiBo?take=\(take)"
        if let before, let encoded = before.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&before=\(encoded)"
        }
        let req = makeRequest(path)
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ThongBaoNoiBoDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getThongBaoUnreadCount() async -> Int {
        let req = makeRequest("/api/ThongBaoNoiBo/unread-count")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<Int>.self, from: data), env.isSuccess else { return 0 }
        return env.data ?? 0
    }

    /// Trợ lý ảo: thẻ tình trạng tồn kho đầu màn — nil nếu lỗi mạng.
    func getTroLyTongQuan() async -> TroLyTraLoi? {
        let req = makeRequest("/api/TroLy/tong-quan")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<TroLyTraLoi>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Trợ lý ảo: các câu hỏi bấm sẵn (server quyết định có câu nào) — rỗng nếu lỗi mạng.
    func getTroLyCauHoi() async -> [TroLyCauHoi] {
        let req = makeRequest("/api/TroLy/cau-hoi")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[TroLyCauHoi]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Trợ lý ảo: câu trả lời có cấu trúc cho 1 câu hỏi bấm sẵn — nil nếu lỗi.
    func getTroLyChiTiet(_ ma: String) async -> TroLyTraLoi? {
        let req = makeRequest("/api/TroLy/chi-tiet/\(ma)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<TroLyTraLoi>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    // ===== Trợ lý ảo: Lên đơn lấy hàng (đại lý + đề xuất hàng nên lấy) =====

    /// Các đại lý lấy hàng + đơn tối thiểu đã lưu — nil nếu lỗi mạng.
    func getLayHangDaiLy() async -> [LayHangDaiLy]? {
        let req = makeRequest("/api/TroLy/lay-hang/dai-ly")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[LayHangDaiLy]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    /// Đề xuất hàng nên lấy ở 1 đại lý. soLuongToiThieu nil = dùng mức đã lưu của đại lý. Trả (kết quả, thông báo lỗi).
    /// Món không có công thức hỏi AI nên có thể mất vài giây.
    func getLayHang(daiLyId: String, soLuongToiThieu: Int?) async -> (LayHang?, String?) {
        var path = "/api/TroLy/lay-hang/\(daiLyId)"
        if let soLuongToiThieu { path += "?soLuongToiThieu=\(soLuongToiThieu)" }
        let (data, _) = await send(makeRequest(path))
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<LayHang>.self, from: data) else {
            return (nil, "Không kết nối được máy chủ.")
        }
        return env.isSuccess ? (env.data, nil) : (nil, env.message ?? "Không tính được đơn.")
    }

    func datSoLuongToiThieu(daiLyId: String, soLuongToiThieu: Int) async -> ActionResult {
        let req = makeRequest("/api/TroLy/lay-hang/dai-ly/\(daiLyId)/so-luong-toi-thieu", method: "PUT",
                              body: jsonBody(["soLuongToiThieu": soLuongToiThieu]))
        return await executeAction(req)
    }

    func taoDaiLyLayHang(ten: String) async -> ActionResult {
        let req = makeRequest("/api/TroLy/lay-hang/dai-ly", method: "POST", body: jsonBody(["ten": ten]))
        return await executeAction(req)
    }

    /// Mọi nguyên liệu + cái nào đại lý này lấy được — nil nếu lỗi.
    func getLayHangMatHang(daiLyId: String) async -> [LayHangMatHang]? {
        let (data, _) = await send(makeRequest("/api/TroLy/lay-hang/dai-ly/\(daiLyId)/mat-hang"))
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[LayHangMatHang]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    /// Đặt lại TOÀN BỘ mặt hàng của đại lý.
    func datLayHangMatHang(daiLyId: String, nguyenLieuIds: [String]) async -> ActionResult {
        let req = makeRequest("/api/TroLy/lay-hang/dai-ly/\(daiLyId)/mat-hang", method: "PUT",
                              body: jsonBody(["nguyenLieuIds": nguyenLieuIds]))
        return await executeAction(req)
    }

    /// Trợ lý ảo: việc cần xử lý (lỗi, VPS, lệch ví, backup — thay Discord). nil nếu lỗi mạng hoặc không
    /// phải tài khoản Admin (server trả 403) — màn trợ lý ẩn hẳn mục này.
    func getCanhBao(daXuLy: Bool = false) async -> [CanhBaoHeThong]? {
        let req = makeRequest("/api/TroLy/canh-bao?daXuLy=\(daXuLy)&take=100")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[CanhBaoHeThong]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func danhDauCanhBao(id: String, daXuLy: Bool) async -> ActionResult {
        let req = makeRequest("/api/TroLy/canh-bao/\(id)/xu-ly", method: "POST", body: jsonBody(["daXuLy": daXuLy]))
        return await executeAction(req)
    }

    func markThongBaoSeen() async -> ActionResult {
        let req = makeRequest("/api/ThongBaoNoiBo/danh-dau-da-xem", method: "POST")
        return await executeAction(req)
    }

    // Tin khuyến mãi hiện cho app khách (AppDatHangIOS) — quản trị từ đây.
    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getThongBaoQuanListOrNil() async -> [ThongBaoQuanDto]? {
        let req = makeRequest("/api/ThongBaoQuan")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ThongBaoQuanDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getThongBaoQuanList() async -> [ThongBaoQuanDto] { await getThongBaoQuanListOrNil() ?? [] }

    func createThongBaoQuan(tieude: String, noiDung: String, dangHoatDong: Bool) async -> ActionResult {
        let body = ThongBaoQuanRequest(tieude: tieude, noiDung: noiDung, dangHoatDong: dangHoatDong)
        let req = makeRequest("/api/ThongBaoQuan", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateThongBaoQuan(id: String, tieude: String, noiDung: String, dangHoatDong: Bool) async -> ActionResult {
        let body = ThongBaoQuanRequest(tieude: tieude, noiDung: noiDung, dangHoatDong: dangHoatDong)
        let req = makeRequest("/api/ThongBaoQuan/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteThongBaoQuan(id: String) async -> ActionResult {
        let req = makeRequest("/api/ThongBaoQuan/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    // Voucher app khách (AppDatHangIOS) — quản trị từ đây.
    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getVoucherListOrNil() async -> [VoucherDto]? {
        let req = makeRequest("/api/Voucher")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[VoucherDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getVoucherList() async -> [VoucherDto] { await getVoucherListOrNil() ?? [] }

    func createVoucher(_ v: VoucherRequest) async -> ActionResult {
        let req = makeRequest("/api/Voucher", method: "POST", body: jsonBody(v))
        return await executeAction(req)
    }

    func updateVoucher(id: String, _ v: VoucherRequest) async -> ActionResult {
        let req = makeRequest("/api/Voucher/\(id)", method: "PUT", body: jsonBody(v))
        return await executeAction(req)
    }

    func deleteVoucher(id: String) async -> ActionResult {
        let req = makeRequest("/api/Voucher/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Phân bố đơn theo giờ trong ngày, cộng dồn `soNgay` ngày gần đây — dùng cho GioThapDiemView
    /// (nhận ra khung giờ vắng khách trước khi cấu hình voucher KhungGioThapDiem).
    func getPhanBoDonTheoGio(soNgay: Int = 30) async -> [PhanBoDonTheoGioItemDto] {
        let req = makeRequest("/api/ThongKe/phan-bo-don-theo-gio?soNgay=\(soNgay)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[PhanBoDonTheoGioItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getPhanBoDoanhThuTheoThu(soNgay: Int = 30) async -> [PhanBoDoanhThuTheoThuItemDto] {
        let req = makeRequest("/api/ThongKe/phan-bo-doanh-thu-theo-thu?soNgay=\(soNgay)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[PhanBoDoanhThuTheoThuItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Doanh thu theo tháng (soThang tháng gần đây) — dùng cho BaoHoaView, nhìn xu hướng tăng
    /// trưởng có đang chững lại không.
    func getDoanhThuTheoThang(soThang: Int = 12) async -> [DoanhThuTheoThangItemDto] {
        let req = makeRequest("/api/ThongKe/doanh-thu-theo-thang?soThang=\(soThang)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[DoanhThuTheoThangItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Tỷ lệ khách tháng trước quay lại tháng sau — dùng cho BaoHoaView.
    func getTyLeKhachQuayLaiTheoThang(soThang: Int = 12) async -> [TyLeKhachQuayLaiThangItemDto] {
        let req = makeRequest("/api/ThongKe/ty-le-khach-quay-lai-theo-thang?soThang=\(soThang)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[TyLeKhachQuayLaiThangItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Vị trí khách hàng cho Bản đồ khách hàng — đọc thẳng từ DB, xem MapCustomerDto.
    func getMapCustomers() async -> [MapCustomerDto] {
        let req = makeRequest("/api/Map/customers")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[MapCustomerDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Bán kính ship trung bình theo tháng — đọc từ DonViTriLog (DB), dùng cho BaoHoaView.
    func getShipRadiusTrend(soThang: Int = 12) async -> [ShipRadiusThangItemDto] {
        let req = makeRequest("/api/Map/ship-radius-trend?soThang=\(soThang)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ShipRadiusThangItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    // Ngưỡng/số tiền các tính năng giữ chân khách (giới thiệu, sinh nhật, vòng quay, thẻ
    // tem) trong app khách — trước đây hardcode, giờ chỉnh được từ đây.
    func getGamificationConfig() async -> GamificationConfigDto? {
        let req = makeRequest("/api/GamificationConfig")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<GamificationConfigDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func updateGamificationConfig(_ dto: GamificationConfigDto) async -> ActionResult {
        let req = makeRequest("/api/GamificationConfig", method: "PUT", body: jsonBody(dto))
        return await executeAction(req)
    }

    func getThongKeChiTieu(ngay: Int, thang: Int, nam: Int) async -> ThongKeChiTieuDto? {
        await getThongKe("chi-tieu-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeCongNo(ngay: Int, thang: Int, nam: Int) async -> ThongKeCongNoDto? {
        await getThongKe("cong-no-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeThanhToan(ngay: Int, thang: Int, nam: Int) async -> ThongKeThanhToanDto? {
        await getThongKe("thanh-toan-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeDoanhThu(ngay: Int, thang: Int, nam: Int) async -> ThongKeDoanhThuNgayDto? {
        await getThongKe("doanh-thu-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getNhipDoanhThuNgay(ngay: Int, thang: Int, nam: Int) async -> NhipDoanhThuDto? {
        await getThongKe("nhip-doanh-thu-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeTraNo(ngay: Int, thang: Int, nam: Int) async -> ThongKeTraNoNgayDto? {
        await getThongKe("tra-no-ngay", ngay: ngay, thang: thang, nam: nam)
    }
    func getThongKeDonChuaThanhToan(ngay: Int, thang: Int, nam: Int) async -> ThongKeDonChuaThanhToanDto? {
        await getThongKe("don-chua-thanh-toan", ngay: ngay, thang: thang, nam: nam)
    }
    func getTongNo() async -> TongNoDto? {
        let req = makeRequest("/api/ThongKe/tong-no")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<TongNoDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    private func getThongKe<T: Decodable>(_ endpoint: String, ngay: Int, thang: Int, nam: Int) async -> T? {
        let req = makeRequest("/api/ThongKe/\(endpoint)?ngay=\(ngay)&thang=\(thang)&nam=\(nam)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<T>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func getThongKeChiTieuThang(thang: Int, nam: Int) async -> ThongKeChiTieuDto? {
        await getThongKeThang("chi-tieu-thang", thang: thang, nam: nam)
    }
    func getThongKeThanhToanThang(thang: Int, nam: Int) async -> ThongKeThanhToanDto? {
        await getThongKeThang("thanh-toan-thang", thang: thang, nam: nam)
    }
    func getNhipDoanhThuThang(thang: Int, nam: Int) async -> NhipDoanhThuDto? {
        await getThongKeThang("nhip-doanh-thu-thang", thang: thang, nam: nam)
    }
    func getThongKeDoanhThuThang(thang: Int, nam: Int) async -> ThongKeDoanhThuNgayDto? {
        await getThongKeThang("doanh-thu-thang", thang: thang, nam: nam)
    }
    func getThongKeTraNoThang(thang: Int, nam: Int) async -> ThongKeTraNoNgayDto? {
        await getThongKeThang("tra-no-thang", thang: thang, nam: nam)
    }
    func getThongKeDonChuaThanhToanThang(thang: Int, nam: Int) async -> ThongKeDonChuaThanhToanDto? {
        await getThongKeThang("don-chua-thanh-toan-thang", thang: thang, nam: nam)
    }
    func getThongKeGiamGiaThang(thang: Int, nam: Int) async -> ThongKeGiamGiaDto? {
        await getThongKeThang("giam-gia-thang", thang: thang, nam: nam)
    }
    func getThongKeGiamGiaNgay(ngay: Int, thang: Int, nam: Int) async -> ThongKeGiamGiaDto? {
        await getThongKe("giam-gia-ngay", ngay: ngay, thang: thang, nam: nam)
    }

    /// `ngay` != nil: backend chỉ trả đơn của đúng ngày đó (màn thống kê NGÀY). Backend cũ chưa có
    /// tham số này sẽ bỏ qua và trả cả tháng — caller vẫn lọc lại theo ngày phía client cho chắc.
    func getDoanhThuChiTietThang(thang: Int, nam: Int, ten: String, ngay: Int? = nil) async -> [HoaDonListDto] {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        let req = makeRequest("/api/ThongKe/doanh-thu-chi-tiet-thang?thang=\(thang)&nam=\(nam)&ten=\(tenEncoded)\(ngayQuery(ngay))")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func getThanhToanChiTietThang(thang: Int, nam: Int, ten: String, ngay: Int? = nil) async -> [ThanhToanChiTietItemDto] {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        let req = makeRequest("/api/ThongKe/thanh-toan-chi-tiet-thang?thang=\(thang)&nam=\(nam)&ten=\(tenEncoded)\(ngayQuery(ngay))")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ThanhToanChiTietItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Chi tiết card "Khách trả nợ" (bản ngày) — GetTraNoAsync gộp SUM theo tên khách nên card không
    /// có hoaDonId để tap; endpoint riêng này giữ nguyên bộ lọc nhưng trả nguyên danh sách.
    func getTraNoChiTietThang(thang: Int, nam: Int, ten: String, isShipper: Bool, khachHangId: String? = nil, ngay: Int? = nil) async -> [ThanhToanChiTietItemDto] {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        var url = "/api/ThongKe/tra-no-chi-tiet-thang?thang=\(thang)&nam=\(nam)&ten=\(tenEncoded)&isShipper=\(isShipper)"
        if let khachHangId { url += "&khachHangId=\(khachHangId)" }
        url += ngayQuery(ngay)
        let req = makeRequest(url)
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ThanhToanChiTietItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    private func ngayQuery(_ ngay: Int?) -> String {
        ngay.map { "&ngay=\($0)" } ?? ""
    }

    private func getThongKeThang<T: Decodable>(_ endpoint: String, thang: Int, nam: Int) async -> T? {
        let req = makeRequest("/api/ThongKe/\(endpoint)?thang=\(thang)&nam=\(nam)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<T>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func getLuongShipperThang(ten: String, thang: Int, nam: Int) async -> LuongShipperDto? {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        let req = makeRequest("/api/ThongKe/luong-shipper-thang?ten=\(tenEncoded)&thang=\(thang)&nam=\(nam)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<LuongShipperDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func getDoanhThuShipperChiTietThang(ten: String, thang: Int, nam: Int) async -> [HoaDonListDto] {
        let tenEncoded = ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ten
        let req = makeRequest("/api/ThongKe/doanh-thu-shipper-chi-tiet-thang?ten=\(tenEncoded)&thang=\(thang)&nam=\(nam)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[HoaDonListDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// Proxy VietQR qua Backend (bank config chỉ sống ở BankQrConfig phía server — Desktop/Mobile
    /// dùng chung, iOS gọi qua đây nên đổi tài khoản 1 chỗ là mọi client ra cùng 1 mã QR).
    /// Ảnh HoaDonGrid mới nhất từ máy Desktop `label` (2026-08-27: đổi từ SignalR push sang HTTP
    /// GET thường, xem DesktopScreenController phía Backend + DesktopScreenView.swift) — trả kèm
    /// tuổi khung hình (ms) đọc từ header `X-Frame-Age-Ms` để view tự quyết "đã lâu không có khung
    /// mới" thay vì đo timestamp cục bộ, phòng đồng hồ máy lệch.
    func getDesktopScreenFrame(label: String) async -> (data: Data, ageMs: Int)? {
        let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? label
        let req = makeRequest("/api/desktopscreen/\(encodedLabel)/frame")
        let (data, http) = await send(req)
        guard let data, http?.statusCode == 200 else { return nil }
        let ageMs = Int(http?.value(forHTTPHeaderField: "X-Frame-Age-Ms") ?? "") ?? 0
        return (data, ageMs)
    }

    func getBillQrImage(amount: Double, addInfo: String) async -> Data? {
        let vnd = Int(amount.rounded())
        let query = "amount=\(vnd)&addInfo=\(addInfo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let req = makeRequest("/api/HoaDon/bill-qr?\(query)")
        let (data, http) = await send(req)
        guard let data, http?.statusCode == 200 else { return nil }
        return data
    }

    /// Nội dung chuyển khoản cho QR GỘP NHIỀU hoá đơn (CongNoListView) — tính trên Backend qua
    /// BankQrConfig.BuildAddInfo, KHÔNG tự build ở Swift nữa (từng lệch tiền tố "SEVQR" giữa 2 bên
    /// hồi 2026-08-23 vì có 2 bản implement song song).
    func getGopAddInfo(ten: String, maDau: String, maCuoi: String?) async -> String? {
        var query = "ten=\(ten.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" +
                    "&maDau=\(maDau.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let maCuoi, !maCuoi.isEmpty {
            query += "&maCuoi=\(maCuoi.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        let req = makeRequest("/api/HoaDon/gop-addinfo?\(query)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<String>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func getHoaDonDetail(_ id: String) async -> HoaDonDetailDto? {
        let req = makeRequest("/api/HoaDon/\(id)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<HoaDonDetailDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// Parse thô bằng JSONSerialization (không ràng buộc shape "data") — khớp cách Kotlin dùng
    /// JsonParser thô cho các action, tránh Decodable fail nếu "data" trả về khác dự đoán.
    private func executeAction(_ req: URLRequest) async -> ActionResult {
        let (data, _) = await send(req)
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ActionResult(success: false, message: "Không có phản hồi từ server.")
        }
        let success = (obj["isSuccess"] as? Bool) ?? false
        let message = obj["message"] as? String
        let warnings = (obj["warnings"] as? [String]) ?? []
        return ActionResult(success: success, message: message, warnings: warnings)
    }

    private func isoNow() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// Thu đủ số tiền còn lại — không hỗ trợ thu 1 phần/ví, khớp giới hạn khung bên Android.
    func thuTien(hoaDonId: String, isCash: Bool, soTien: Double, ten: String, khachHangId: String?) async -> ActionResult {
        let path = isCash ? "f1" : "f4"
        let now = isoNow()
        let body = ThanhToanRequest(
            ten: ten, hoaDonId: hoaDonId, soTien: soTien, ngayGio: now, ngay: now,
            khachHangId: khachHangId,
            phuongThucThanhToanId: isCash ? PaymentMethod.tienMatId : PaymentMethod.chuyenKhoanId
        )
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/\(path)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func ghiNo(hoaDonId: String) async -> ActionResult {
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/f12", method: "PUT", body: jsonBody(IdOnlyRequest(id: hoaDonId)))
        return await executeAction(req)
    }

    func doiPhanLoaiHoaDon(hoaDonId: String) async -> ActionResult {
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/doi-phan-loai", method: "PUT")
        return await executeAction(req)
    }

    func rollback(hoaDonId: String) async -> ActionResult {
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/rollback", method: "PUT", body: jsonBody(IdOnlyRequest(id: hoaDonId)))
        return await executeAction(req)
    }

    func delete(hoaDonId: String) async -> ActionResult {
        let req = makeRequest("/api/HoaDon/\(hoaDonId)", method: "DELETE")
        return await executeAction(req)
    }

    func createHoaDonFull(_ body: HoaDonFullCreateRequest) async -> CreateActionResult {
        let req = makeRequest("/api/HoaDon", method: "POST", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data,
              let env = try? JSONDecoder().decode(ApiEnvelope<IdOnlyDto>.self, from: data) else {
            return CreateActionResult(success: false, message: "Không có phản hồi từ server.", id: nil)
        }
        return CreateActionResult(success: env.isSuccess, message: env.message, id: env.data?.id)
    }

    /// Sửa hoá đơn đã có — PUT /api/HoaDon/{id} nhận cùng shape body với tạo mới
    /// (HoaDonCrudService.UpdateAsync xoá sạch ChiTietHoaDons/Toppings cũ rồi AddAsync lại từ dto,
    /// khớp cách Desktop HoaDonEditWindow.Save ghi đè toàn bộ chứ không diff từng dòng).
    func updateHoaDonFull(id: String, _ body: HoaDonFullCreateRequest) async -> CreateActionResult {
        let req = makeRequest("/api/HoaDon/\(id)", method: "PUT", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data,
              let env = try? JSONDecoder().decode(ApiEnvelope<IdOnlyDto>.self, from: data) else {
            return CreateActionResult(success: false, message: "Không có phản hồi từ server.", id: nil)
        }
        return CreateActionResult(success: env.isSuccess, message: env.message, id: env.data?.id ?? id)
    }

    /// Danh sách sản phẩm/topping đang bán — tải 1 lần lúc mở form thêm hoá đơn rồi lọc/tìm cục bộ
    /// (khớp cách Desktop cache AppDataCache.SanPhams, không gọi search API theo từng phím gõ).
    /// includeNgungBan = true để giữ cả sản phẩm đã ngừng bán (màn Công thức cần tên của công thức cũ).
    /// nil = tải LỖI, khác với [] = thật sự trống.
    func getSanPhamListOrNil(includeNgungBan: Bool = false) async -> [SanPhamDto]? {
        let req = makeRequest("/api/SanPham")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[SanPhamDto]>.self, from: data), env.isSuccess else { return nil }
        return (env.data ?? []).filter { includeNgungBan || !$0.ngungBan }
    }

    func getSanPhamList(includeNgungBan: Bool = false) async -> [SanPhamDto] {
        await getSanPhamListOrNil(includeNgungBan: includeNgungBan) ?? []
    }

    func getToppingList() async -> [ToppingDto] {
        let req = makeRequest("/api/Topping")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ToppingDto]>.self, from: data), env.isSuccess else { return [] }
        return (env.data ?? []).filter { !$0.ngungBan }
    }

    // ---- Topping (quản trị — ToppingListView, thay ToppingWindow bên Desktop) ----

    /// Khác getToppingList() ở chỗ KHÔNG lọc ngừng bán — màn quản trị cần thấy cả món đã ngừng bán.
    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getToppingAdminOrNil() async -> [ToppingDto]? {
        let req = makeRequest("/api/Topping")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ToppingDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getToppingAdmin() async -> [ToppingDto] { await getToppingAdminOrNil() ?? [] }

    func createTopping(_ body: ToppingDto) async -> ActionResult {
        let req = makeRequest("/api/Topping", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateTopping(id: String, _ body: ToppingDto) async -> ActionResult {
        let req = makeRequest("/api/Topping/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteTopping(id: String) async -> ActionResult {
        let req = makeRequest("/api/Topping/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Tải 1 lần rồi lọc cục bộ, khớp cách Desktop cache AppDataCache.TenDuongs cho TenDuongBox.
    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getTenDuongListOrNil() async -> [TenDuongDto]? {
        let req = makeRequest("/api/TenDuong")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[TenDuongDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getTenDuongList() async -> [TenDuongDto] { await getTenDuongListOrNil() ?? [] }

    // ---- Tên đường (quản trị — TenDuongListView, thay TenDuongWindow bên Desktop) ----

    func createTenDuong(_ body: TenDuongDto) async -> ActionResult {
        let req = makeRequest("/api/TenDuong", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func updateTenDuong(id: String, _ body: TenDuongDto) async -> ActionResult {
        let req = makeRequest("/api/TenDuong/\(id)", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteTenDuong(id: String) async -> ActionResult {
        let req = makeRequest("/api/TenDuong/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Giá riêng đã lưu cho MỌI khách — endpoint không hỗ trợ lọc theo khách (khớp cách Desktop
    /// tải hết AppDataCache.GiaBanRiengs rồi lọc cục bộ theo KhachHangId khi cần).
    func getKhachHangGiaBanList() async -> [KhachHangGiaBanDto] {
        let req = makeRequest("/api/KhachHangGiaBan?take=5000")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangGiaBanDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    // ---- Giá riêng (quản trị — GiaRiengListView, thay GiaRiengWindow bên Desktop) ----

    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getGiaRiengAdminOrNil() async -> [GiaRiengAdminDto]? {
        let req = makeRequest("/api/KhachHangGiaBan?take=5000")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[GiaRiengAdminDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getGiaRiengAdmin() async -> [GiaRiengAdminDto] { await getGiaRiengAdminOrNil() ?? [] }

    func upsertGiaRieng(_ body: GiaRiengUpsertRequest) async -> ActionResult {
        let req = makeRequest("/api/KhachHangGiaBan/upsert", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func deleteGiaRieng(id: String) async -> ActionResult {
        let req = makeRequest("/api/KhachHangGiaBan/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Toàn bộ khách hàng (không lọc) — dùng cho tính năng đồng bộ Danh bạ, take cao để chắc chắn
    /// lấy hết (GetAllAsync bên backend không có cap cứng, chỉ giới hạn khi truyền take).
    /// nil = tải LỖI, khác với [] = thật sự trống — màn danh sách dùng bản này để không hiện "trống" khi chỉ rớt mạng.
    func getAllKhachHangOrNil() async -> [KhachHangDto]? {
        let req = makeRequest("/api/KhachHang?take=100000")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangDto]>.self, from: data), env.isSuccess else { return nil }
        return env.data ?? []
    }

    func getAllKhachHang() async -> [KhachHangDto] { await getAllKhachHangOrNil() ?? [] }

    func searchKhachHang(_ q: String) async -> [KhachHangDto] {
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let query = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let req = makeRequest("/api/KhachHang/search?q=\(query)&take=20")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// excludeHoaDonId: loại đơn đang sửa ra khỏi "Đơn khác chưa trả" — khớp
    /// HoaDonCustomerInfoService.GetAsync(khachHangId, excludeHoaDonId) (Backend), tránh đơn đang
    /// sửa tự đếm nợ của chính nó (Desktop truyền HoaDonId hiện tại khi mở HoaDonEditWindow cho đơn
    /// có sẵn, chỉ để trống lúc tạo đơn mới).
    func getKhachHangInfo(khachHangId: String, excludeHoaDonId: String? = nil) async -> KhachHangInfoDto? {
        var path = "/api/HoaDon/get-khach-hang-info/\(khachHangId)"
        if let excludeHoaDonId {
            path += "?excludeHoaDonId=\(excludeHoaDonId)"
        }
        let req = makeRequest(path)
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangInfoDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    func getKhachHangHayGoiSom() async -> [KhachHangGoiSomDto] {
        let req = makeRequest("/api/HoaDon/khach-hay-goi-som")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangGoiSomDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// "Bắt đơn App" — khớp GetDonAsync (Desktop). List() trả Result<object> (không phải
    /// Result<List<...>>) nhưng runtime type vẫn là mảng đơn khi thành công nên decode với
    /// ApiEnvelope<[AppOrderSummaryDto]> vẫn khớp; lúc lỗi (chưa cấu hình Shipping) data=null.
    func getAppOrderList() async -> (orders: [AppOrderSummaryDto], message: String?) {
        let req = makeRequest("/api/AppOrder/list")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[AppOrderSummaryDto]>.self, from: data) else {
            return ([], "Không có phản hồi từ server.")
        }
        guard env.isSuccess else { return ([], env.message) }
        return (env.data ?? [], nil)
    }

    func getAppOrderDetail(_ id: String) async -> (detail: AppOrderDetailDto?, message: String?, warnings: [String]) {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let req = makeRequest("/api/AppOrder/detail/\(encodedId)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<AppOrderDetailDto>.self, from: data) else {
            return (nil, "Không có phản hồi từ server.", [])
        }
        guard env.isSuccess else { return (nil, env.message, []) }
        return (env.data, nil, env.warnings ?? [])
    }

    func getKhachHangById(_ id: String) async -> KhachHangDto? {
        let req = makeRequest("/api/KhachHang/\(id)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangDto>.self, from: data), env.isSuccess else { return nil }
        return env.data
    }

    /// "Bắt đơn từ ảnh" — nhân viên chọn 1 khách khác tên AI đọc từ ảnh chat (khách đổi tên hiển thị
    /// Messenger/Zalo). Không quan tâm kết quả — học nền, không chặn UI (xem HoaDonCreateFormView.selectKhach).
    func learnKhachHangAlias(rawText: String, khachHangId: String) async {
        let req = makeRequest("/api/KhachHang/alias", method: "POST",
                               body: jsonBody(["rawText": rawText, "khachHangId": khachHangId]))
        _ = await send(req)
    }

    /// Khớp CreateKhachBtn_Click (Desktop): trùng SĐT với khách có sẵn thì server trả lỗi kèm tên
    /// khách đó trong message — KHÔNG tự tìm/chọn lại giúp (khác Desktop có cache toàn bộ khách để
    /// tự dò), hiển thị lỗi để nhân viên tự tìm khách đó qua ô tìm kiếm.
    func createKhachHang(_ body: KhachHangCreateRequest) async -> (success: Bool, message: String?, khach: KhachHangDto?) {
        let req = makeRequest("/api/KhachHang", method: "POST", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangDto>.self, from: data) else {
            return (false, "Không có phản hồi từ server.", nil)
        }
        return (env.isSuccess, env.message, env.data)
    }

    /// Sửa tên/SĐT/địa chỉ (nhiều dòng)/voucher của khách đã có — khớp SaveKhachContactBtn_Click
    /// (Desktop): PUT full KhachHangDto, server tự thêm/xoá KhachHangPhones/Addresses theo Id khớp
    /// (KhachHangCrudService.UpdateAsync) — dòng có Id trùng thì sửa tại chỗ, không có thì thêm mới,
    /// bị thiếu trong payload thì xoá. KHÔNG đụng SoDu (server không đọc field này khi Update).
    func updateKhachHang(_ body: KhachHangDto) async -> (success: Bool, message: String?, khach: KhachHangDto?) {
        let req = makeRequest("/api/KhachHang/\(body.id)", method: "PUT", body: jsonBody(body))
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<KhachHangDto>.self, from: data) else {
            return (false, "Không có phản hồi từ server.", nil)
        }
        return (env.isSuccess, env.message, env.data)
    }

    // ---- Khách hàng (quản trị — KhachHangListView, thay KhachHangWindow bên Desktop) ----

    func deleteKhachHang(id: String) async -> ActionResult {
        let req = makeRequest("/api/KhachHang/\(id)", method: "DELETE")
        return await executeAction(req)
    }

    /// Gộp nhiều khách trùng làm 1 — KHÔNG thể hoàn tác, xem MergeKhachHangRequest.
    func mergeKhachHang(_ body: MergeKhachHangRequest) async -> ActionResult {
        let req = makeRequest("/api/KhachHang/merge", method: "POST", body: jsonBody(body))
        return await executeAction(req)
    }

    func getViGiaoDich(khachHangId: String, take: Int = 100) async -> [ViGiaoDichDto] {
        let req = makeRequest("/api/KhachHang/\(khachHangId)/vi-giao-dich?take=\(take)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[ViGiaoDichDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    /// nam=0/thang=0 nghĩa là "Tất cả" (không lọc theo tháng) — khớp KhachHangLichSuWindow (Desktop).
    func getKhachHangLichSu(khachHangId: String, nam: Int, thang: Int) async -> [KhachHangLichSuItemDto] {
        let req = makeRequest("/api/HoaDon/khach-hang/\(khachHangId)/lich-su?nam=\(nam)&thang=\(thang)")
        let (data, _) = await send(req)
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[KhachHangLichSuItemDto]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func ganShipper(hoaDonId: String, nguoiShip: String) async -> ActionResult {
        let now = isoNow()
        let body = GanShipperRequest(id: hoaDonId, nguoiShip: nguoiShip, ngayShip: now, ngayIn: now)
        let req = makeRequest("/api/HoaDon/\(hoaDonId)/esc", method: "PUT", body: jsonBody(body))
        return await executeAction(req)
    }
}

extension APIClient {
    func getTtsSoundNames() async -> [String] {
        let (data, _) = await send(makeRequest("/api/tts-sounds"))
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[String]>.self, from: data), env.isSuccess else { return [] }
        return env.data ?? []
    }

    func downloadTtsSound(_ name: String) async -> Data? {
        let (data, resp) = await send(makeRequest("/api/tts-sounds/\(name)"))
        guard resp?.statusCode == 200, let data, data.count > 44 else { return nil }
        return data
    }
}

extension APIClient {
    func getTtsSoundIndex() async -> [String: String] {
        let (data, _) = await send(makeRequest("/api/tts-sounds/index"))
        guard let data, let env = try? JSONDecoder().decode(ApiEnvelope<[String: String]>.self, from: data), env.isSuccess else { return [:] }
        return env.data ?? [:]
    }
}
