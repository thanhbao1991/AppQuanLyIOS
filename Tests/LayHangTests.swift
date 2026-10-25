import XCTest
@testable import AppMobileIOS

/// "Lên đơn lấy hàng" (Trợ lý ảo, 25/10/2026): giải mã đúng JSON server trả (món công thức + món AI ước + ghi chú
/// bỏ qua) và các hàm hiển thị/đổi số. Server tính toán, app chỉ trình bày nên test khoá phần dễ vỡ: tên trường JSON.
final class LayHangTests: XCTestCase {

    func test_giaiMa_ketQuaServer_goiMonCongThucMonAiVaGhiChuBoQua() throws {
        let json = """
        {"isSuccess":true,"message":null,"warnings":null,"data":{
          "nhaCungCapId":"11111111-1111-1111-1111-111111111111","tenDaiLy":"Mini Mart K7",
          "soLuongToiThieu":4,"tongSoLuong":4,"tongTien":671000,"datToiThieu":true,
          "dong":[{"nguyenLieuId":"a","ten":"Revive (Thùng)","donViTinh":"Thùng","soLuong":3,"donGia":167000,
                   "thanhTien":501000,"donViBan":"Chai","tonHienTai":4,"tonSau":76,"ngayConTruoc":0.8,"ngayConSau":22.2}],
          "uocLuongAi":[{"nguyenLieuId":"b","ten":"Hạt Dưa (Lốc 20)","donViTinh":"Lốc","soLuong":1,"donGia":170000,
                         "thanhTien":170000,"lyDo":"tới nhịp mua"}],
          "boQua":["Không Bán (Thùng): chưa cần lấy — mới mua tuần trước"]}}
        """
        let env = try JSONDecoder().decode(ApiEnvelope<LayHang>.self, from: Data(json.utf8))
        let kq = try XCTUnwrap(env.data)

        XCTAssertTrue(env.isSuccess)
        XCTAssertEqual(kq.tenDaiLy, "Mini Mart K7")
        XCTAssertEqual(kq.soLuongToiThieu, 4)
        XCTAssertEqual(kq.tongSoLuong, 4)
        XCTAssertTrue(kq.datToiThieu)
        XCTAssertEqual(kq.dong.first?.soLuong, 3)
        XCTAssertEqual(kq.dong.first?.ngayConSau, 22.2)
        XCTAssertEqual(kq.uocLuongAi.first?.lyDo, "tới nhịp mua")
        XCTAssertEqual(kq.boQua.count, 1)
    }

    func test_giaiMa_ngayConNull_vaDanhSachMatHang() throws {
        let dong = #"{"nguyenLieuId":"a","ten":"X","donViTinh":null,"soLuong":1,"donGia":1000,"thanhTien":1000,"donViBan":null,"tonHienTai":0,"tonSau":24,"ngayConTruoc":null,"ngayConSau":null}"#
        let d = try JSONDecoder().decode(LayHangDong.self, from: Data(dong.utf8))
        XCTAssertNil(d.ngayConTruoc)
        XCTAssertNil(d.donViBan)

        let ds = #"[{"nguyenLieuId":"a","ten":"Bò Húc (Thùng)","donViTinh":"Thùng","giaNhap":295000,"daChon":true}]"#
        let mh = try JSONDecoder().decode([LayHangMatHang].self, from: Data(ds.utf8))
        XCTAssertEqual(mh.first?.id, "a")
        XCTAssertEqual(mh.first?.daChon, true)
    }

    func test_doiSo_chiLayChuSo() {
        XCTAssertEqual(LayHangFormat.doiSo("4"), 4)
        XCTAssertEqual(LayHangFormat.doiSo(" 12 "), 12)
        XCTAssertEqual(LayHangFormat.doiSo("1.5"), 15)
        XCTAssertNil(LayHangFormat.doiSo(""))
        XCTAssertNil(LayHangFormat.doiSo("abc"))
    }

    func test_ngay_dinhDang() {
        XCTAssertEqual(LayHangFormat.ngay(nil), "?")
        XCTAssertEqual(LayHangFormat.ngay(0.4), "<1 ngày")
        XCTAssertEqual(LayHangFormat.ngay(22.2), "~22 ngày")
    }

    func test_dongPhu_tonTruocSau() {
        let d = LayHangDong(nguyenLieuId: "a", ten: "Revive (Thùng)", donViTinh: "Thùng", soLuong: 3, donGia: 167_000,
                            thanhTien: 501_000, donViBan: "Chai", tonHienTai: 4, tonSau: 76, ngayConTruoc: 0.8, ngayConSau: 22.2)
        XCTAssertEqual(LayHangFormat.dongPhu(d), "Tồn 4 chai (<1 ngày) → 76 (~22 ngày)")
    }

    func test_vanBanDon_gomMonCongThucVaMonAi() {
        let dong = LayHangDong(nguyenLieuId: "a", ten: "Revive (Thùng)", donViTinh: "Thùng", soLuong: 3, donGia: 167_000,
                               thanhTien: 501_000, donViBan: "Chai", tonHienTai: 4, tonSau: 76, ngayConTruoc: 0.8, ngayConSau: 22.2)
        let ai = LayHangAiDong(nguyenLieuId: "b", ten: "Hạt Dưa (Lốc 20)", donViTinh: "Lốc", soLuong: 1, donGia: 170_000,
                               thanhTien: 170_000, lyDo: "tới nhịp mua")
        let kq = LayHang(nhaCungCapId: "x", tenDaiLy: "Mini Mart K7", soLuongToiThieu: 4, tongSoLuong: 4, tongTien: 671_000,
                         datToiThieu: true, dong: [dong], uocLuongAi: [ai], boQua: [])
        XCTAssertEqual(LayHangFormat.vanBanDon(kq),
                       "Đơn lấy hàng — Mini Mart K7\n- Revive (Thùng) x3\n- Hạt Dưa (Lốc 20) x1\nTổng: 4 — 671.000đ")
    }

    // MARK: - Sửa nhanh tồn kho (Trợ lý ảo)

    func test_suaTonNhanh_doiSoVaDinhDang() {
        XCTAssertEqual(SuaTonNhanhFormat.doiSo("500"), 500)
        XCTAssertEqual(SuaTonNhanhFormat.doiSo("12,5"), 12.5)
        XCTAssertEqual(SuaTonNhanhFormat.doiSo(" 7.25 "), 7.25)
        XCTAssertNil(SuaTonNhanhFormat.doiSo(""))
        XCTAssertNil(SuaTonNhanhFormat.doiSo("abc"))
        XCTAssertEqual(SuaTonNhanhFormat.soChu(500), "500")
        XCTAssertEqual(SuaTonNhanhFormat.soChu(12.5), "12.50")
    }

    func test_giaiMa_dongTonKho_coMaNguyenLieuTonVaDonVi_dongKhacThiNil() throws {
        let tonKho = #"{"ten":"Ly Giấy 240Ml","giaTri":"53","phu":"~53 ly","mucDo":"thap","hang":null,"nguyenLieuBanHangId":"c7e4dd45","ton":53,"donVi":"Ly"}"#
        let d1 = try JSONDecoder().decode(TroLyTraLoi.Dong.self, from: Data(tonKho.utf8))
        XCTAssertEqual(d1.nguyenLieuBanHangId, "c7e4dd45")
        XCTAssertEqual(d1.ton, 53)
        XCTAssertEqual(d1.donVi, "Ly")

        let banChay = #"{"ten":"Cà phê","giaTri":"12","hang":1}"#
        let d2 = try JSONDecoder().decode(TroLyTraLoi.Dong.self, from: Data(banChay.utf8))
        XCTAssertNil(d2.nguyenLieuBanHangId)
        XCTAssertNil(d2.ton)
    }
}
