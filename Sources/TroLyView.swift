import SwiftUI

/// 1 lượt chat gửi lên /api/TroLy/chat (role "user"/"assistant").
struct TroLyTinNhan: Codable, Identifiable, Equatable {
    var id = UUID()
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey { case role, content }
}

/// Trợ lý ảo (Menu > Trợ lý ảo) — mở ra là có "Báo cáo chủ nhân…" về tồn kho (server tính, không tốn AI),
/// rồi chat hỏi đáp kiểu "Bò Húc sắp hết chưa?". Backend gửi ảnh chụp số liệu tồn kho cho AI mỗi câu hỏi
/// (TroLyService), AI chỉ trả lời dựa trên số liệu đó. Lịch sử chat chỉ giữ trong phiên, đóng màn là mất.
struct TroLyView: View {
    @State private var tinNhan: [TroLyTinNhan] = []
    @State private var nhap = ""
    @State private var dangTraLoi = false
    @State private var loi: String?
    @FocusState private var dangGo: Bool

    private let goiY = [
        "Có nguyên liệu nào sắp hết không?",
        "Bò Húc sắp hết chưa?",
        "Mai cần nhập hàng gì?",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if tinNhan.isEmpty {
                            HStack { ProgressView(); Text("Đang xem tồn kho…").foregroundColor(.textMuted) }
                                .padding(.top, 20)
                        }
                        ForEach(tinNhan) { bongBong($0) }
                        if dangTraLoi {
                            HStack(spacing: 6) { ProgressView(); Text("Đang nghĩ…").font(.subheadline).foregroundColor(.textMuted) }
                                .id("dang-tra-loi")
                        }
                        if let loi {
                            Text(loi).font(.footnote).foregroundColor(.red)
                        }
                        if tinNhan.count <= 1 && !dangTraLoi {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(goiY, id: \.self) { cau in
                                    Button { Task { await gui(cau) } } label: {
                                        Text(cau)
                                            .font(.subheadline)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(Capsule().stroke(Color.brandPrimary, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.brandPrimary)
                                }
                            }
                            .padding(.top, 4)
                        }
                        Color.clear.frame(height: 1).id("cuoi")
                    }
                    .padding(12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: tinNhan.count) { _ in withAnimation { proxy.scrollTo("cuoi", anchor: .bottom) } }
                .onChange(of: dangTraLoi) { _ in withAnimation { proxy.scrollTo("cuoi", anchor: .bottom) } }
            }

            HStack(spacing: 8) {
                TextField("Hỏi trợ lý…", text: $nhap, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($dangGo)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.gray.opacity(0.12)))
                Button {
                    let cau = nhap
                    Task { await gui(cau) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(dangTraLoi || nhap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .foregroundColor(.brandPrimary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(Divider(), alignment: .top)
        }
        .navigationTitle("Trợ lý ảo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            guard tinNhan.isEmpty else { return }
            let chao = await APIClient.shared.getTroLyChao()
            tinNhan = [TroLyTinNhan(role: "assistant", content: chao ?? "Chào chủ nhân! Em chưa xem được tồn kho lúc này, chủ nhân cứ hỏi em nhé.")]
        }
    }

    private func bongBong(_ m: TroLyTinNhan) -> some View {
        let laToi = m.role == "user"
        return HStack {
            if laToi { Spacer(minLength: 40) }
            Text(m.content)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundColor(laToi ? .white : .primary)
                .background(RoundedRectangle(cornerRadius: 16).fill(laToi ? Color.brandPrimary : Color.gray.opacity(0.14)))
            if !laToi { Spacer(minLength: 40) }
        }
    }

    private func gui(_ cau: String) async {
        let noiDung = cau.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !noiDung.isEmpty, !dangTraLoi else { return }
        nhap = ""
        loi = nil
        tinNhan.append(TroLyTinNhan(role: "user", content: noiDung))
        dangTraLoi = true
        let (traLoi, loiMoi) = await APIClient.shared.troLyChat(tinNhan)
        dangTraLoi = false
        if let traLoi {
            tinNhan.append(TroLyTinNhan(role: "assistant", content: traLoi))
        } else {
            loi = loiMoi
        }
    }
}
