import SwiftUI

/// 1 câu hỏi bấm sẵn của trợ lý — server trả danh sách (GET /api/TroLy/cau-hoi).
struct TroLyCauHoi: Codable, Identifiable, Equatable {
    let ma: String
    let noiDung: String
    var id: String { ma }
}

/// Trợ lý ảo (Menu > Trợ lý ảo) — KHÔNG dùng AI: mở ra là báo cáo những món cần để ý (dưới ngưỡng an toàn,
/// sắp hết), bên dưới là các câu hỏi bấm sẵn, chạm để xem trả lời (server tính thẳng từ DB). Nhấn giữ rồi
/// kéo câu hỏi để đổi thứ tự — thứ tự lưu trên máy (AppStorage), câu hỏi mới server thêm sẽ nằm cuối.
struct TroLyView: View {
    @AppStorage("troLy.thuTu") private var thuTuRaw = ""
    @State private var baoCao: String?
    @State private var cauHoi: [TroLyCauHoi] = []
    @State private var traLoi: [String: String] = [:]
    @State private var dangHoi: Set<String> = []
    @State private var dangTai = true

    var body: some View {
        List {
            Section {
                if let baoCao {
                    Text(baoCao).textSelection(.enabled)
                } else if dangTai {
                    HStack { ProgressView(); Text("Đang xem tồn kho…").foregroundColor(.textMuted) }
                } else {
                    Text("Không tải được báo cáo.").foregroundColor(.textMuted)
                }
            }

            Section {
                ForEach(cauHoi) { hang($0) }
                    .onMove { tu, den in
                        cauHoi.move(fromOffsets: tu, toOffset: den)
                        thuTuRaw = cauHoi.map(\.ma).joined(separator: ",")
                    }
            } header: {
                Text("Hỏi nhanh")
            } footer: {
                if !cauHoi.isEmpty { Text("Nhấn giữ rồi kéo để đổi thứ tự.") }
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

    private func hang(_ c: TroLyCauHoi) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await hoi(c.ma) }
            } label: {
                HStack {
                    Text(c.noiDung).foregroundColor(.brandPrimary)
                    Spacer()
                    if dangHoi.contains(c.ma) {
                        ProgressView()
                    } else {
                        Image(systemName: traLoi[c.ma] == nil ? "chevron.right" : "arrow.clockwise")
                            .font(.footnote).foregroundColor(.textMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let tl = traLoi[c.ma] {
                Text(tl)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func taiLai() async {
        dangTai = true
        async let bc = APIClient.shared.getTroLyChao()
        async let ds = APIClient.shared.getTroLyCauHoi()
        let (b, d) = await (bc, ds)
        baoCao = b
        if !d.isEmpty { cauHoi = sapTheoThuTu(d) }
        dangTai = false
        // Kéo xuống làm mới thì cập nhật luôn các câu đã mở.
        for ma in traLoi.keys { Task { await hoi(ma) } }
    }

    private func hoi(_ ma: String) async {
        guard !dangHoi.contains(ma) else { return }
        dangHoi.insert(ma)
        let tl = await APIClient.shared.getTroLyTraLoi(ma)
        dangHoi.remove(ma)
        withAnimation { traLoi[ma] = tl ?? "Không tải được, thử lại nhé." }
    }

    private func sapTheoThuTu(_ ds: [TroLyCauHoi]) -> [TroLyCauHoi] {
        let thuTu = thuTuRaw.split(separator: ",").map(String.init)
        let viTri = { (i: Int, c: TroLyCauHoi) in (thuTu.firstIndex(of: c.ma) ?? thuTu.count, i) }
        return ds.enumerated().sorted { viTri($0.offset, $0.element) < viTri($1.offset, $1.element) }.map(\.element)
    }
}
