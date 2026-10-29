import AVFoundation
import CallKit
import PushKit
import UIKit
import WebRTC

extension Notification.Name {
    /// Có cuộc gọi từ quầy (CallKit) — nút bộ đàm WKWebView phải nhả kết nối, không thì 2 bên giành máy quầy.
    static let cuocGoiQuayBatDau = Notification.Name("cuocGoiQuayBatDau")
}

/// Máy quầy gọi AppQuanLy (29/10/2026) — chiều ngược của nút bộ đàm (BoDamButton).
/// Quầy bấm 📻 / F8 → backend gửi VoIP push (BoDamController.Goi) → app đổ chuông CallKit như cuộc gọi thật, kể
/// cả lúc khoá màn hình hoặc app đã tắt. Nghe máy → nối WebRTC tới trang quầy y như vai "ql" của
/// wwwroot/bodam/index.html (offer gửi nhóm quầy, nhận answer/ice), rồi gửi "noi on" suốt cuộc gọi để 2 bên nói
/// tự do như gọi điện. Không dùng WKWebView ở đây: WebKit tắt micro khi app ở nền/khoá màn hình, còn WebRTC
/// native chạy chung phiên âm thanh CallKit (khử vọng của iOS, Opus) nên nghe ở màn hình khoá được.
/// iOS bắt buộc mọi VoIP push phải báo CallKit ngay, kể cả push cũ/trùng — không báo là app bị iOS giết.
final class CuocGoiQuay: NSObject {
    static let shared = CuocGoiQuay()

    private static let tenQuay = "Quầy Đenn"
    private static let keyVoipToken = "bodam.voipToken"

    private let provider: CXProvider
    private let callController = CXCallController()
    private var registry: PKPushRegistry?

    private lazy var factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(encoderFactory: nil, decoderFactory: nil)
    }()

    // Trạng thái cuộc gọi — chỉ đụng trên main queue.
    private var maCuoc: UUID?
    private var daNghe = false
    private var hub: BoDamHub?
    private var ice: [RTCIceServer] = []
    private var pc: RTCPeerConnection?
    private var micTrack: RTCAudioTrack?
    private var phien = 0
    private var hangIce: [(phien: Int, c: RTCIceCandidate)] = []
    private var henChuong: DispatchWorkItem?
    private var henGoiLai: DispatchWorkItem?
    private var henMat: DispatchWorkItem?
    private var tatTieng = false

    /// Đang đổ chuông hoặc đang nói — nút bộ đàm không được nối trong lúc này.
    var dangCo: Bool { maCuoc != nil }

    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)

        // WebRTC không tự bật/tắt phiên âm thanh — CallKit làm (didActivate/didDeactivate).
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.isAudioEnabled = false
    }

    /// Gọi sớm trong didFinishLaunching — app bị VoIP push đánh thức phải có registry ngay mới nhận được push.
    func batDau() {
        guard registry == nil else { return }
        let r = PKPushRegistry(queue: .main)
        r.delegate = self
        r.desiredPushTypes = [.voIP]
        registry = r
    }

    /// Gửi token PushKit lên phiên đăng nhập hiện tại — gọi mỗi lần app vào trạng thái đã đăng nhập.
    func guiTokenLenServer() {
        guard Prefs.isLoggedIn, let token = UserDefaults.standard.string(forKey: Self.keyVoipToken) else { return }
        Task { _ = await APIClient.shared.dangKyVoipToken(token) }
        // Lần đầu: xin quyền micro sẵn — nghe máy ở màn hình khoá thì iOS không hiện được hộp hỏi.
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    // MARK: - Đổ chuông

    private func baoCuocGoiDen(_ ma: UUID, ten: String) {
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: ten)
        update.localizedCallerName = ten
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        if maCuoc != nil {
            // Đang có cuộc khác (push trùng/quầy bấm 2 lần) — vẫn phải báo CallKit rồi tắt ngay.
            provider.reportNewIncomingCall(with: ma, update: update) { [weak self] _ in
                self?.provider.reportCall(with: ma, endedAt: nil, reason: .failed)
            }
            return
        }

        maCuoc = ma
        daNghe = false
        tatTieng = false
        NotificationCenter.default.post(name: .cuocGoiQuayBatDau, object: nil)
        provider.reportNewIncomingCall(with: ma, update: update) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.maCuoc == ma else { return }
                if error != nil {
                    // Bị chặn (Không làm phiền, đang có cuộc gọi điện thoại…) — coi như từ chối.
                    Task { await APIClient.shared.boDamTuChoi(ma.uuidString) }
                    self.donDep()
                    return
                }
                self.choNghe(ma)
                // Đang mở app thì tự nghe như máy quầy tự nhận khi AppQuanLy bấm nút bộ đàm.
                if UIApplication.shared.applicationState == .active {
                    self.callController.request(CXTransaction(action: CXAnswerCallAction(call: ma))) { _ in }
                }
            }
        }
    }

    /// Lúc đang đổ chuông: nối hub sẵn (để nghe tin quầy huỷ / máy khác nghe) và lấy ICE trước cho nhanh.
    private func choNghe(_ ma: UUID) {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.maCuoc == ma, !self.daNghe else { return }
            self.ketThuc(.unanswered)
        }
        henChuong = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 35, execute: item)

        Task {
            // Gọi API trước để token được làm mới nếu đã hết hạn (app có thể vừa thức dậy sau nhiều giờ).
            let tt = await APIClient.shared.boDamTrangThai(ma.uuidString)
            let ds = await APIClient.shared.boDamIce()
            await MainActor.run {
                guard self.maCuoc == ma else { return }
                self.ice = ds.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
                if let tt, tt != "dangGoi", !self.daNghe {
                    self.ketThuc(tt == "daNghe" ? .answeredElsewhere : .remoteEnded)
                    return
                }
                self.noiHub()
            }
        }
    }

    private func noiHub() {
        guard hub == nil, let token = Prefs.token else { return }
        let h = BoDamHub(token: token)
        h.onTin = { [weak self] tu, tin in self?.nhan(tu: tu, tin: tin) }
        h.onNoi = { [weak self] in
            guard let self, self.hub === h else { return }
            h.invoke("BoDamDangKyQl", [])
            // Nghe máy trước lúc hub nối xong (hoặc hub vừa nối lại) → gọi quầy ngay.
            if self.daNghe, self.pc?.connectionState != .connected { self.goiQuay() }
        }
        hub = h
        h.start()
    }

    // MARK: - WebRTC (vai "ql" của trang bộ đàm)

    private func gui(_ tin: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: tin),
              let s = String(data: data, encoding: .utf8) else { return }
        hub?.invoke("BoDamGuiQuay", [s])
    }

    private func dongPc() {
        henMat?.cancel()
        pc?.delegate = nil
        pc?.close()
        pc = nil
        micTrack = nil
    }

    private func goiQuay() {
        guard daNghe, let hub, hub.daNoi else { return }
        henGoiLai?.cancel()
        phien += 1
        let ph = phien
        hangIce = []
        dongPc()

        let config = RTCConfiguration()
        config.iceServers = ice
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
        config.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let p = factory.peerConnection(with: config, constraints: constraints, delegate: self) else { return }
        pc = p
        let source = factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = factory.audioTrack(with: source, trackId: "mic")
        track.isEnabled = !tatTieng
        micTrack = track
        _ = p.add(track, streamIds: ["ql"])

        let offerConstraints = RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true"], optionalConstraints: nil)
        p.offer(for: offerConstraints) { [weak self] sdp, _ in
            guard let sdp else { return }
            p.setLocalDescription(sdp) { _ in
                DispatchQueue.main.async {
                    guard let self, self.phien == ph, self.pc === p else { return }
                    self.gui(["t": "offer", "phien": ph, "sdp": sdp.sdp])
                }
            }
        }

        // Quầy không trả lời (trang quầy đang nạp lại, mạng chậm…) thì 6 giây sau gọi lại.
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.phien == ph, self.pc?.connectionState != .connected else { return }
            self.goiQuay()
        }
        henGoiLai = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
    }

    private func themIce(_ ph: Int, _ c: RTCIceCandidate) {
        if let pc, pc.remoteDescription != nil, ph == phien {
            pc.add(c) { _ in }
        } else {
            hangIce.append((ph, c))
        }
    }

    private func nhan(tu: String, tin: [String: Any]) {
        guard let t = tin["t"] as? String, let ma = maCuoc else { return }
        let tinMa = (tin["maCuoc"] as? String).flatMap(UUID.init(uuidString:))
        switch t {
        case "huyGoi":
            if tinMa == ma, !daNghe { ketThuc(.remoteEnded) }
        case "daNghe":
            if tinMa == ma, !daNghe { ketThuc(.answeredElsewhere) }
        case "answer":
            guard daNghe, (tin["phien"] as? Int) == phien, let sdp = tin["sdp"] as? String,
                  let pc, pc.remoteDescription == nil else { return }
            let ph = phien
            pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.phien == ph, self.pc === pc else { return }
                    let con = self.hangIce.filter { $0.phien == ph }
                    self.hangIce = []
                    con.forEach { pc.add($0.c) { _ in } }
                }
            }
        case "ice":
            guard daNghe, let ph = tin["phien"] as? Int, let c = tin["c"] as? [String: Any],
                  let sdp = c["candidate"] as? String else { return }
            themIce(ph, RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(c["sdpMLineIndex"] as? Int ?? 0), sdpMid: c["sdpMid"] as? String))
        case "bye":
            // Quầy gác máy (hoặc có máy khác vừa giành nối quầy).
            if daNghe, !tu.isEmpty { ketThuc(.remoteEnded) }
        default:
            break
        }
    }

    private func doiTrangThai(_ s: RTCPeerConnectionState) {
        henMat?.cancel()
        switch s {
        case .connected:
            henGoiLai?.cancel()
            // Cả cuộc gọi là "đang giữ nút": quầy mở mic + phát tiếng mình suốt tới khi gác máy.
            gui(["t": "noi", "phien": phien, "on": true])
        case .disconnected:
            // Mạng chập chờn thường tự hồi vài giây; quá 6 giây nối lại từ đầu.
            let item = DispatchWorkItem { [weak self] in self?.goiQuay() }
            henMat = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
        case .failed:
            goiQuay()
        default:
            break
        }
    }

    // MARK: - Kết thúc

    /// Cuộc gọi kết thúc không do người dùng bấm trên màn CallKit (quầy huỷ/gác, hết giờ, máy khác nghe).
    private func ketThuc(_ lyDo: CXCallEndedReason) {
        guard let ma = maCuoc else { return }
        provider.reportCall(with: ma, endedAt: nil, reason: lyDo)
        donDep()
    }

    private func donDep() {
        henChuong?.cancel()
        henGoiLai?.cancel()
        dongPc()
        hub?.stop()
        hub = nil
        hangIce = []
        phien += 1
        maCuoc = nil
        daNghe = false
    }

    private func cauHinhAmThanh() {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        cfg.mode = AVAudioSession.Mode.voiceChat.rawValue
        cfg.categoryOptions = [.allowBluetooth]
        try? rtc.setConfiguration(cfg)
        rtc.unlockForConfiguration()
    }
}

// MARK: - PushKit

extension CuocGoiQuay: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.keyVoipToken)
        guiTokenLenServer()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        UserDefaults.standard.removeObject(forKey: Self.keyVoipToken)
        if Prefs.isLoggedIn { Task { _ = await APIClient.shared.dangKyVoipToken(nil) } }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        let ma = (dict["maCuoc"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
        let ten = dict["ten"] as? String ?? Self.tenQuay
        baoCuocGoiDen(ma, ten: ten)
        completion()
    }
}

// MARK: - CallKit

extension CuocGoiQuay: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        donDep()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard action.callUUID == maCuoc else { action.fail(); return }
        let ma = action.callUUID
        daNghe = true
        henChuong?.cancel()
        cauHinhAmThanh()
        action.fulfill()
        Task {
            let duoc = await APIClient.shared.boDamNghe(ma.uuidString)
            // Bấm nghe nhanh hơn lúc lấy xong ICE lúc đổ chuông (tự nghe khi đang mở app) — lấy lại cho chắc có TURN.
            let ds = self.ice.isEmpty ? await APIClient.shared.boDamIce() : []
            await MainActor.run {
                guard self.maCuoc == ma else { return }
                if !duoc { self.ketThuc(.answeredElsewhere); return }
                if self.ice.isEmpty {
                    self.ice = ds.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
                }
                if self.hub == nil { self.noiHub() } else { self.goiQuay() }
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard action.callUUID == maCuoc else { action.fulfill(); return }
        if daNghe {
            gui(["t": "bye"])
        } else {
            let ma = action.callUUID.uuidString
            Task { await APIClient.shared.boDamTuChoi(ma) }
        }
        // Đợi tin "bye" kịp đi trước khi đóng hub.
        let hubCu = hub
        hub = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { hubCu?.stop() }
        donDep()
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        tatTieng = action.isMuted
        micTrack?.isEnabled = !action.isMuted
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.audioSessionDidActivate(audioSession)
        rtc.isAudioEnabled = true
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.audioSessionDidDeactivate(audioSession)
        rtc.isAudioEnabled = false
    }
}

// MARK: - RTCPeerConnectionDelegate (gọi trên luồng của WebRTC → đẩy về main)

extension CuocGoiQuay: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
            guard peerConnection === self.pc else { return }
            var c: [String: Any] = ["candidate": candidate.sdp, "sdpMLineIndex": Int(candidate.sdpMLineIndex)]
            if let mid = candidate.sdpMid { c["sdpMid"] = mid }
            self.gui(["t": "ice", "phien": self.phien, "c": c])
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        DispatchQueue.main.async {
            guard peerConnection === self.pc else { return }
            self.doiTrangThai(newState)
        }
    }
}

// MARK: - Hub SignalR riêng cho cuộc gọi

/// Kết nối /hub/entity riêng (JSON Hub Protocol qua WebSocket) — SignalRClient chung chỉ nhận EntityChanged và
/// tắt khi app vào nền, còn cuộc gọi phải sống cả lúc khoá màn hình. Gửi ping 10 giây/lần để server không cắt.
/// Mọi callback chạy trên main queue.
final class BoDamHub {
    private let token: String
    private var ws: URLSessionWebSocketTask?
    private var chay = false
    private var henPing: Timer?
    private(set) var daNoi = false

    var onTin: ((String, [String: Any]) -> Void)?
    var onNoi: (() -> Void)?

    init(token: String) { self.token = token }

    func start() {
        guard !chay else { return }
        chay = true
        Task { await vongNoi() }
    }

    func stop() {
        chay = false
        daNoi = false
        henPing?.invalidate()
        henPing = nil
        ws?.cancel(with: .goingAway, reason: nil)
        ws = nil
    }

    func invoke(_ target: String, _ args: [Any]) {
        guard daNoi, let ws else { return }
        let obj: [String: Any] = ["type": 1, "target": target, "arguments": args]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return }
        ws.send(.string(s + "\u{1e}")) { _ in }
    }

    private func vongNoi() async {
        while chay {
            do { try await noiMotLan() } catch {}
            await MainActor.run {
                self.daNoi = false
                self.henPing?.invalidate()
            }
            guard chay else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private func noiMotLan() async throws {
        var neg = URLRequest(url: URL(string: Prefs.apiBase + "/hub/entity/negotiate?negotiateVersion=1")!)
        neg.httpMethod = "POST"
        neg.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: neg)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (obj["connectionToken"] as? String) ?? (obj["connectionId"] as? String) else {
            throw URLError(.badServerResponse)
        }
        var comps = URLComponents(string: Prefs.apiBase + "/hub/entity")!
        comps.scheme = "wss"
        comps.queryItems = [URLQueryItem(name: "id", value: id), URLQueryItem(name: "access_token", value: token)]
        let socket = URLSession.shared.webSocketTask(with: comps.url!)
        guard chay else { return }
        ws = socket
        socket.resume()
        try await socket.send(.string("{\"protocol\":\"json\",\"version\":1}\u{1e}"))

        var batTay = false
        while chay {
            let msg = try await socket.receive()
            let text: String
            switch msg {
            case .string(let s): text = s
            case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
            @unknown default: continue
            }
            for rec in text.split(separator: "\u{1e}", omittingEmptySubsequences: true) {
                guard let d = String(rec).data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                if !batTay {
                    // Bản tin đầu là phản hồi bắt tay ({} hoặc {"error":…}).
                    batTay = true
                    if o["error"] != nil { throw URLError(.userAuthenticationRequired) }
                    await MainActor.run {
                        self.daNoi = true
                        self.henPing?.invalidate()
                        self.henPing = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                            self?.ws?.send(.string("{\"type\":6}\u{1e}")) { _ in }
                        }
                        self.onNoi?()
                    }
                    continue
                }
                guard (o["type"] as? Int) == 1, (o["target"] as? String) == "BoDam",
                      let args = o["arguments"] as? [Any], args.count >= 2,
                      let tu = args[0] as? String, let s = args[1] as? String,
                      let td = s.data(using: .utf8),
                      let tin = try? JSONSerialization.jsonObject(with: td) as? [String: Any] else { continue }
                await MainActor.run { self.onTin?(tu, tin) }
            }
        }
    }
}
