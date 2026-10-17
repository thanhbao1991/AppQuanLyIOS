import Charts
import SwiftUI

/// 1 câu hỏi bấm sẵn của trợ lý — server trả danh sách (GET /api/TroLy/cau-hoi).
struct TroLyCauHoi: Codable, Identifiable, Equatable {
    let ma: String
    let noiDung: String
    var id: String { ma }
}

/// Câu trả lời có cấu trúc (GET /api/TroLy/tong-quan, /chi-tiet/{ma}) — trường nào nil thì không hiện.
struct TroLyTraLoi: Codable, Equatable {
    struct Dong: Codable, Equatable, Identifiable {
        let ten: String
        let giaTri: String
        let phu: String?
        /// "het" | "thap" | "sapHet" | nil
        let mucDo: String?
        let hang: Int?
        var id: String { ten }
    }

    struct Diem: Codable, Equatable, Identifiable {
        let nhan: String
        let giaTri: Double
        let nhom: String?
        var id: String { "\(nhom ?? "")|\(nhan)" }
    }

    struct BieuDo: Codable, Equatable {
        /// "duong" (cộng dồn theo giờ, nhan = giờ) | "cot" (cột ngang, nhan = tên)
        let loai: String
        let diem: [Diem]
        let donVi: String?
    }

    let tieuDe: String?
    let moTa: String?
    let soSanh: String?
    let soSanhTang: Bool?
    let thongDiep: String?
    /// "ok" | "canhBao" | nil
    let trangThai: String?
    let dong: [Dong]
    let bieuDo: BieuDo?
}

/// Trợ lý ảo (Menu > Trợ lý ảo) — KHÔNG dùng AI. Đầu màn là thẻ tình trạng tồn kho, bên dưới các câu hỏi bấm
/// sẵn THU GỌN — chạm câu nào mới mở + tải câu trả lời câu đó (server tính thẳng từ DB, kèm biểu đồ); user
/// không muốn phải đọc hết mọi câu. Kéo xuống để làm mới; nhấn giữ rồi kéo 1 câu để đổi thứ tự — lưu trên máy
/// (AppStorage), câu hỏi mới server thêm sẽ nằm cuối.
struct TroLyView: View {
    @AppStorage("troLy.thuTu") private var thuTuRaw = ""
    @State private var tongQuan: TroLyTraLoi?
    @State private var cauHoi: [TroLyCauHoi] = []
    @State private var traLoi: [String: TroLyTraLoi] = [:]
    @State private var moRa: Set<String> = []
    @State private var dangHoi: Set<String> = []
    @State private var dangTai = true
    @State private var capNhatLuc: Date?

    var body: some View {
        List {
            Section {
                theTinhTrang
            }

            Section {
                ForEach(cauHoi) { c in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { bamCauHoi(c.ma) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: Self.icon[c.ma] ?? "questionmark.circle")
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.brandPrimary)
                                    .frame(width: 24)
                                Text(c.noiDung).font(.body.weight(.medium)).foregroundColor(.primary)
                                Spacer()
                                if dangHoi.contains(c.ma) {
                                    ProgressView()
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.textMuted)
                                        .rotationEffect(.degrees(moRa.contains(c.ma) ? 90 : 0))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if moRa.contains(c.ma) {
                            if let tl = traLoi[c.ma] {
                                TroLyTraLoiView(traLoi: tl)
                            } else if !dangHoi.contains(c.ma) {
                                Text("Không tải được, chạm lại để thử.").font(.subheadline).foregroundColor(.textMuted)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onMove { tu, den in
                    cauHoi.move(fromOffsets: tu, toOffset: den)
                    thuTuRaw = cauHoi.map(\.ma).joined(separator: ",")
                }
            } footer: {
                if !cauHoi.isEmpty { Text("Kéo xuống để làm mới · nhấn giữ rồi kéo để đổi thứ tự.") }
            }
        }
        .navigationTitle("Trợ lý ảo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .refreshable { await taiLai() }
        .task { if cauHoi.isEmpty { await taiLai() } }
    }

    @ViewBuilder private var theTinhTrang: some View {
        let ok = tongQuan?.trangThai == "ok"
        let capNhat = capNhatLuc.map { "Cập nhật \($0.formatted(date: .omitted, time: .shortened))" }
        VStack(alignment: .leading, spacing: 12) {
            if let tq = tongQuan {
                TheKetLuan(mucDo: ok ? .tot : .canhBao,
                           tieuDe: ok ? "Tồn kho ổn" : (tq.thongDiep ?? ""),
                           moTa: ok ? tq.thongDiep : capNhat)
            } else if dangTai {
                HStack { ProgressView(); Text("Đang xem tồn kho…").foregroundColor(.textMuted) }
            } else {
                Text("Không tải được tồn kho.").foregroundColor(.textMuted)
            }
            if let tq = tongQuan, !tq.dong.isEmpty {
                TroLyDongList(dong: tq.dong)
            }
        }
        .padding(.vertical, 6)
    }

    private func taiLai() async {
        dangTai = true
        async let tq = APIClient.shared.getTroLyTongQuan()
        async let ds = APIClient.shared.getTroLyCauHoi()
        let (t, d) = await (tq, ds)
        tongQuan = t
        if !d.isEmpty { cauHoi = sapTheoThuTu(d) }
        capNhatLuc = Date()
        dangTai = false
        // Câu nào đang mở thì làm mới luôn; câu đã tải mà đang đóng thì bỏ để lần mở sau tải số mới.
        traLoi = traLoi.filter { moRa.contains($0.key) }
        for ma in moRa { Task { await hoi(ma) } }
    }

    private static let icon: [String: String] = [
        "can-nhap": "cart",
        "ton-kho": "shippingbox",
        "doanh-thu": "chart.line.uptrend.xyaxis",
        "ban-chay": "trophy",
    ]

    private func bamCauHoi(_ ma: String) {
        if moRa.contains(ma) {
            withAnimation { _ = moRa.remove(ma) }
        } else {
            withAnimation { _ = moRa.insert(ma) }
            if traLoi[ma] == nil { Task { await hoi(ma) } }
        }
    }

    private func hoi(_ ma: String) async {
        guard !dangHoi.contains(ma) else { return }
        dangHoi.insert(ma)
        let tl = await APIClient.shared.getTroLyChiTiet(ma)
        dangHoi.remove(ma)
        withAnimation { traLoi[ma] = tl }
    }

    private func sapTheoThuTu(_ ds: [TroLyCauHoi]) -> [TroLyCauHoi] {
        let thuTu = thuTuRaw.split(separator: ",").map(String.init)
        let viTri = { (i: Int, c: TroLyCauHoi) in (thuTu.firstIndex(of: c.ma) ?? thuTu.count, i) }
        return ds.enumerated().sorted { viTri($0.offset, $0.element) < viTri($1.offset, $1.element) }.map(\.element)
    }
}

/// Nội dung 1 câu trả lời: số lớn + so sánh, biểu đồ, các dòng.
struct TroLyTraLoiView: View {
    let traLoi: TroLyTraLoi

    /// Món bán chạy: biểu đồ cột đã ghi số trên cột, khỏi lặp lại danh sách.
    private var anDong: Bool {
        traLoi.bieuDo?.loai == "cot" && !traLoi.dong.isEmpty && traLoi.dong.allSatisfy { $0.hang != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let td = traLoi.tieuDe {
                SoLon(giaTri: td, moTa: traLoi.moTa, soSanh: traLoi.soSanh, tang: traLoi.soSanhTang)
            }

            if let bd = traLoi.bieuDo, !bd.diem.isEmpty {
                switch bd.loai {
                case "duong":
                    BieuDoCongDon(diem: bd.diem.map {
                        DiemCongDon(x: Int($0.nhan) ?? 0, giaTri: $0.giaTri, laKyNay: $0.nhom == "Hôm nay")
                    })
                default: TroLyBieuDoCot(bieuDo: bd)
                }
            }

            if !traLoi.dong.isEmpty && !anDong {
                TroLyDongList(dong: traLoi.dong)
            } else if traLoi.dong.isEmpty, let tdiep = traLoi.thongDiep {
                Label(tdiep, systemImage: traLoi.trangThai == "ok" ? "checkmark.circle.fill" : "info.circle")
                    .font(.subheadline)
                    .foregroundColor(traLoi.trangThai == "ok" ? .green : .textMuted)
            }
        }
    }
}

enum TroLyMau {
    static func theoMucDo(_ mucDo: String?) -> Color {
        switch mucDo {
        case "het": return .red
        case "thap": return .orange
        case "sapHet": return .yellow
        case "ok": return .green
        default: return .brandPrimary
        }
    }
}

/// Danh sách dòng: chấm màu mức độ (hoặc thứ hạng) · tên + dòng phụ · giá trị canh phải.
struct TroLyDongList: View {
    let dong: [TroLyTraLoi.Dong]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(dong.enumerated()), id: \.element.id) { i, d in
                if i > 0 { Divider().padding(.leading, 22) }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let h = d.hang {
                        Text("\(h)").font(.caption.weight(.bold)).foregroundColor(.textMuted).frame(width: 12)
                    } else {
                        Circle().fill(d.mucDo == nil ? Color.green : TroLyMau.theoMucDo(d.mucDo))
                            .frame(width: 8, height: 8).frame(width: 12)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.ten).font(.subheadline.weight(.medium))
                        if let phu = d.phu {
                            Text(phu).font(.caption).foregroundColor(.textMuted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(d.giaTri)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(d.mucDo == "het" || d.mucDo == "thap" ? TroLyMau.theoMucDo(d.mucDo) : .primary)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

/// Cột ngang: món bán chạy (màu chính) / số ngày còn của tồn kho (màu theo mức độ).
struct TroLyBieuDoCot: View {
    let bieuDo: TroLyTraLoi.BieuDo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if bieuDo.donVi == "ngày" {
                Text("Còn bán được (ngày)").font(.caption).foregroundColor(.textMuted)
            }
            Chart(bieuDo.diem) { d in
                BarMark(x: .value("Giá trị", d.giaTri), y: .value("Tên", d.nhan))
                    .foregroundStyle(TroLyMau.theoMucDo(d.nhom).gradient)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text(d.giaTri.formatted(.number.precision(.fractionLength(0...0))))
                            .font(.caption2.weight(.semibold)).foregroundColor(.textMuted)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(bieuDo.diem.count) * 30 + 8)
        }
    }
}
