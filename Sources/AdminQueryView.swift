import SwiftUI

/// SQL nhanh (chỉ Admin, SELECT-only — backend tự chặn ghi/DDL) dùng khi cần tra dữ liệu gấp trên
/// điện thoại, không cần SSH/SSMS. Dùng chung JWT đang đăng nhập app.
/// Kết quả hiện mỗi dòng 1 nhóm "tên cột — giá trị" (bảng ngang trên điện thoại phải cuộn 2 chiều, khó đọc).
/// Số/ngày do backend định dạng sẵn (1,035,000; 2026-11-23).
struct AdminQueryView: View {
    @State private var sql: String = "SELECT TOP 20 * FROM ChiTieuHangNgays ORDER BY Ngay DESC"
    @State private var result: AdminQueryResultDto?
    @State private var loi: String?
    @State private var dangChay = false
    @FocusState private var dangGo: Bool

    private var sqlRong: Bool { sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        List {
            Section {
                TextEditor(text: $sql)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minHeight: 100)
                    .focused($dangGo)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    Task { await chay() }
                } label: {
                    HStack {
                        Spacer()
                        if dangChay {
                            ProgressView().tint(.white)
                        } else {
                            Text("Chạy").font(.body.weight(.semibold))
                        }
                        Spacer()
                    }
                    .foregroundColor(.white)
                }
                .listRowBackground(sqlRong ? Color.textMuted : Color.brandPrimary)
                .disabled(dangChay || sqlRong)
            } footer: {
                if let loi {
                    Text(loi).foregroundStyle(.red)
                } else if let result {
                    Text("\(result.rows.count) dòng" + (result.coBiCat ? " (đã cắt, còn nhiều hơn)" : ""))
                }
            }

            if let result {
                if result.rows.isEmpty {
                    Section { Text("Không có dòng nào").foregroundStyle(.secondary) }
                } else if let doRong = doRongBang(result) {
                    bang(result, doRong: doRong)
                } else {
                    theTungDong(result)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("SQL nhanh")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { dangGo = false }
            }
        }
    }

    // MARK: - Dạng bảng (vừa màn hình)

    /// Độ rộng từng cột nếu cả bảng vừa bề ngang màn hình; nil = quá rộng → dùng dạng thẻ từng dòng.
    private func doRongBang(_ r: AdminQueryResultDto) -> [CGFloat]? {
        let kyTu: CGFloat = 8.6
        let tho = r.columns.map { cot -> CGFloat in
            let dai = r.rows.prefix(200).map { ($0[cot].flatMap { $0 } ?? "NULL").count }.max() ?? 0
            return CGFloat(max(cot.count, dai)) * kyTu + 14
        }
        let coSan = UIScreen.main.bounds.width - 72
        let tong = tho.reduce(0, +)
        guard tong <= coSan else { return nil }
        let them = (coSan - tong) / CGFloat(tho.count)
        return tho.map { $0 + them }
    }

    private func cotLaSo(_ r: AdminQueryResultDto) -> [Bool] {
        r.columns.map { cot in
            let giaTri = r.rows.compactMap { $0[cot].flatMap { $0 } }
            return !giaTri.isEmpty && giaTri.allSatisfy { $0.range(of: "^-?[0-9,]+(\\.[0-9]+)?$", options: .regularExpression) != nil }
        }
    }

    private func bang(_ r: AdminQueryResultDto, doRong: [CGFloat]) -> some View {
        let laSo = cotLaSo(r)
        return Section {
            hangBang(r.columns.map { Optional($0) }, doRong: doRong, laSo: laSo, tieuDe: true)
            ForEach(Array(r.rows.enumerated()), id: \.offset) { _, row in
                hangBang(r.columns.map { row[$0].flatMap { $0 } }, doRong: doRong, laSo: laSo, tieuDe: false)
            }
        }
    }

    private func hangBang(_ o: [String?], doRong: [CGFloat], laSo: [Bool], tieuDe: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(o.indices, id: \.self) { i in
                Text(o[i] ?? "NULL")
                    .font(tieuDe ? .subheadline.weight(.semibold) : .subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(tieuDe ? Color.brandPrimary : (o[i] == nil ? Color.textMuted : Color.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: doRong[i], alignment: laSo[i] ? .trailing : .leading)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Dạng thẻ (quá nhiều cột)

    @ViewBuilder
    private func theTungDong(_ result: AdminQueryResultDto) -> some View {
        ForEach(Array(result.rows.enumerated()), id: \.offset) { i, row in
            Section(result.rows.count > 1 ? "Dòng \(i + 1)" : "Kết quả") {
                ForEach(result.columns, id: \.self) { cot in
                    oKetQua(cot: cot, giaTri: row[cot].flatMap { $0 })
                }
            }
        }
    }

    private func oKetQua(cot: String, giaTri: String?) -> some View {
        // Dồn hết về trái (chủ quán 24/11/2026): tên cột cột cố định bên trái, giá trị ngay sau.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(cot)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 120, alignment: .leading)
            Text(giaTri ?? "NULL")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(giaTri == nil ? Color.textMuted : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private func chay() async {
        dangGo = false
        let cau = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cau.isEmpty else { return }
        dangChay = true
        loi = nil
        let (res, err) = await APIClient.shared.runAdminQuery(sql: cau)
        result = res
        loi = err
        dangChay = false
    }
}
