import SwiftUI

/// Duyệt công thức size L/XL (Menu > Cấu hình) — đa số công thức L/XL đang chép y nguyên Size
/// Chuẩn nên trừ tồn kho thấp hơn thực tế. Nhân viên mở từng món, so với định lượng Size Chuẩn,
/// sửa số rồi "Lưu & duyệt" (POST /api/CongThuc/{id}/duyet ghi NgayDuyet + NguoiDuyet). Món bán chạy
/// 30 ngày gần nhất lên đầu để làm trước.
struct DuyetCongThucSizeView: View {
    enum Loc: String, CaseIterable, Identifiable {
        case chuaDuyet = "Chưa duyệt"
        case daDuyet = "Đã duyệt"
        case tatCa = "Tất cả"
        var id: String { rawValue }
    }

    @State private var items: [CongThucDuyetSizeDto] = []
    @State private var congThucs: [CongThucDto] = []
    @State private var dinhLuongAll: [SuDungNguyenLieuDto] = []
    @State private var allSanPham: [SanPhamDto] = []
    @State private var allNguyenLieu: [NguyenLieuBanHangDto] = []
    @State private var hasLoaded = false
    @State private var loadFailed = false
    @State private var searchText = ""
    @State private var loc: Loc = .chuaDuyet
    @State private var dangSua: CongThucDuyetSizeDto?

    private var soDaDuyet: Int { items.filter { $0.ngayDuyet != nil }.count }

    private var rows: [CongThucDuyetSizeDto] {
        items.filter { item in
            switch loc {
            case .chuaDuyet: if item.ngayDuyet != nil { return false }
            case .daDuyet: if item.ngayDuyet == nil { return false }
            case .tatCa: break
            }
            return searchText.isEmpty || anyMatchesSearch(searchText, item.tenSanPham, item.tenBienThe, item.tenNhom)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, placeholder: "Tìm món...")
            Picker("Lọc", selection: $loc) {
                ForEach(Loc.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            if !hasLoaded {
                fullScreenLoading()
            } else {
                if loadFailed {
                    ThongKeLoadErrorBanner(text: "Chưa tải được công thức") { Task { await load() } }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                List {
                    Section {
                        ForEach(rows) { item in
                            Button { dangSua = item } label: {
                                DuyetCongThucSizeRow(item: item, trangThai: trangThai(item))
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Đã duyệt \(soDaDuyet)/\(items.count) size L/XL")
                    }
                }
                .listStyle(.plain)
                .softScrollEdgeTop()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Duyệt công thức L/XL")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .sheet(item: $dangSua) { item in
            CongThucEditSheet(
                existing: item.congThucId.flatMap { id in congThucs.first { $0.id == id } },
                existingLines: lines(of: item.congThucId),
                allSanPham: allSanPham,
                allNguyenLieu: allNguyenLieu,
                bienTheCoDinhId: item.sanPhamBienTheId,
                chuanLines: lines(of: item.congThucChuanId)
            ) {
                Task { await load() }
            }
        }
    }

    private func lines(of congThucId: String?) -> [SuDungNguyenLieuDto] {
        guard let congThucId else { return [] }
        return dinhLuongAll.filter { $0.congThucId == congThucId }
    }

    enum TrangThai {
        case chuaCoCongThuc, giongChuan, khacChuan
        case daDuyet(String)
    }

    private func trangThai(_ item: CongThucDuyetSizeDto) -> TrangThai {
        if let ngay = item.ngayDuyet {
            // "2026-10-23T10:11:12..." → "23/10"
            let parts = ngay.prefix(10).split(separator: "-")
            let ngayNgan = parts.count == 3 ? "\(parts[2])/\(parts[1])" : ""
            return .daDuyet([item.nguoiDuyet, ngayNgan].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        }
        let l = lines(of: item.congThucId)
        if l.isEmpty { return .chuaCoCongThuc }
        let chuan = lines(of: item.congThucChuanId)
        func key(_ x: [SuDungNguyenLieuDto]) -> [String] { x.map { "\($0.nguyenLieuId)|\($0.soLuong)" }.sorted() }
        return key(l) == key(chuan) ? .giongChuan : .khacChuan
    }

    private func load() async {
        async let dsTask = APIClient.shared.getCongThucDuyetSizeOrNil()
        async let ctTask = APIClient.shared.getCongThucListOrNil()
        async let dlTask = APIClient.shared.getSuDungNguyenLieuListOrNil()
        async let spTask = APIClient.shared.getSanPhamListOrNil(includeNgungBan: true)
        async let nlTask = APIClient.shared.getNguyenLieuBanHangOrNil()
        let (ds, ct, dl, sp, nl) = await (dsTask, ctTask, dlTask, spTask, nlTask)
        // Phải về đủ cả bộ mới áp dụng — cùng lý do CongThucListView.load: thiếu dinhLuongAll mà vẫn
        // mở sửa rồi Lưu sẽ tạo trùng dòng nguyên liệu (trừ tồn kho gấp đôi).
        if let ds, let ct, let dl, let sp, let nl {
            items = ds
            congThucs = ct
            dinhLuongAll = dl
            allSanPham = sp
            allNguyenLieu = nl.sorted { $0.ten.localizedStandardCompare($1.ten) == .orderedAscending }
            loadFailed = false
        } else {
            loadFailed = true
        }
        hasLoaded = true
    }
}

private struct DuyetCongThucSizeRow: View {
    let item: CongThucDuyetSizeDto
    let trangThai: DuyetCongThucSizeView.TrangThai

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.tenSanPham)  \(item.tenBienThe)")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text([item.tenNhom, "\(item.soLyBan30Ngay) ly / 30 ngày"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.textMuted)
            }
            Spacer()
            nhan
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var nhan: some View {
        switch trangThai {
        case .chuaCoCongThuc:
            Text("Chưa có CT").font(.caption).fontWeight(.bold).foregroundColor(.dangerColor)
        case .giongChuan:
            Text("Giống Chuẩn").font(.caption).fontWeight(.bold).foregroundColor(.orange)
        case .khacChuan:
            Text("Đã khác Chuẩn").font(.caption).fontWeight(.bold).foregroundColor(.brandPrimary)
        case .daDuyet(let ai):
            Label(ai.isEmpty ? "Đã duyệt" : ai, systemImage: "checkmark.seal.fill")
                .font(.caption).fontWeight(.bold).foregroundColor(.successColor)
        }
    }
}
