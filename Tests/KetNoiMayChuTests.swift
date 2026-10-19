import XCTest
@testable import AppMobileIOS

/// Phân loại kết quả request cho thanh "Không kết nối được máy chủ" — 4xx là máy chủ vẫn sống,
/// 52x/502-504 là Cloudflare không tới được VPS, request bị huỷ thì không tính.
final class KetNoiMayChuTests: XCTestCase {
    func testPhanLoai_MaySongKeCa4xx() {
        XCTAssertEqual(KetNoiMayChu.phanLoai(status: 200, error: nil), true)
        XCTAssertEqual(KetNoiMayChu.phanLoai(status: 401, error: nil), true)
        XCTAssertEqual(KetNoiMayChu.phanLoai(status: 500, error: nil), true)
    }

    func testPhanLoai_CloudflareKhongToiVps_LaChet() {
        for code in [502, 503, 504, 520, 522, 523, 530] {
            XCTAssertEqual(KetNoiMayChu.phanLoai(status: code, error: nil), false, "\(code)")
        }
    }

    func testPhanLoai_LoiMang_LaChet_HuyThiBoQua() {
        XCTAssertEqual(KetNoiMayChu.phanLoai(status: nil, error: URLError(.timedOut)), false)
        XCTAssertEqual(KetNoiMayChu.phanLoai(status: nil, error: URLError(.cannotConnectToHost)), false)
        XCTAssertNil(KetNoiMayChu.phanLoai(status: nil, error: URLError(.cancelled)))
        XCTAssertNil(KetNoiMayChu.phanLoai(status: nil, error: CancellationError()))
    }
}
