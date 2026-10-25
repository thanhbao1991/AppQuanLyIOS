import XCTest
@testable import AppMobileIOS

/// "Lên đơn lấy hàng" (Trợ lý ảo, 25/10/2026): giải mã đúng JSON server trả (món công thức + món AI ước + ghi chú
/// bỏ qua) và các hàm hiển thị/đổi số. Server tính toán, app chỉ trình bày nên test khoá phần dễ vỡ: tên trường JSON.
final class LayHangTests: XCTestCase {

    func test_giaiMa_ketQuaServer_goiMonCongThucMonAiVaGhiChuBoQua() throws {
        let json = """
        {"isSuccess":true,"message":null,"warnings":null,"data":{
          "nhaCungCapId":"11111111-1111-1111-1111-111111111111","tenDaiLy":"Mini Mart K7",
          "donToiThieu":1000000,"tongTien":1086000,"datToiThieu":true,
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
        XCTAssertEqual(kq.donToiThieu, 1_000_000)
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
        XCTAssertEqual(LayHangFormat.doiSo("1.500.000"), 1_500_000)
        XCTAssertEqual(LayHangFormat.doiSo(" 2 000 "), 2_000)
        XCTAssertEqual(LayHangFormat.doiSo("1000000"), 1_000_000)
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
        let kq = LayHang(nhaCungCapId: "x", tenDaiLy: "Mini Mart K7", donToiThieu: 1_000_000, tongTien: 671_000,
                         datToiThieu: false, dong: [dong], uocLuongAi: [ai], boQua: [])
        XCTAssertEqual(LayHangFormat.vanBanDon(kq),
                       "Đơn lấy hàng — Mini Mart K7\n- Revive (Thùng) x3\n- Hạt Dưa (Lốc 20) x1\nTổng: 671.000đ")
    }
}
