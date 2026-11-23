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
                }
                ForEach(Array(result.rows.enumerated()), id: \.offset) { i, row in
                    Section(result.rows.count > 1 ? "Dòng \(i + 1)" : "Kết quả") {
                        ForEach(result.columns, id: \.self) { cot in
                            oKetQua(cot: cot, giaTri: row[cot].flatMap { $0 })
                        }
                    }
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
