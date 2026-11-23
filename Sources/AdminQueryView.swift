import SwiftUI

/// SQL nhanh (chỉ Admin, SELECT-only — backend tự chặn ghi/DDL) dùng khi cần tra dữ liệu gấp trên
/// điện thoại, không cần SSH/SSMS. Dùng chung JWT đang đăng nhập app (AppQuanLyIOS), khỏi đăng nhập
/// riêng như bản web wwwroot/admin-query.
struct AdminQueryView: View {
    @State private var sql: String = "SELECT TOP 20 * FROM ChiTieuHangNgays ORDER BY Ngay DESC"
    @State private var result: AdminQueryResultDto?
    @State private var loi: String?
    @State private var dangChay = false

    var body: some View {
        VStack(spacing: 10) {
            TextEditor(text: $sql)
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .padding(6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.textMuted.opacity(0.3)))

            Button {
                Task { await chay() }
            } label: {
                if dangChay {
                    ProgressView()
                } else {
                    Text("Chạy").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .disabled(dangChay || sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let loi {
                Text(loi).font(.caption).foregroundStyle(.red)
            }

            if let result {
                HStack {
                    Text("\(result.rows.count) dòng" + (result.coBiCat ? " (đã cắt, còn nhiều hơn)" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                ScrollView([.horizontal, .vertical]) {
                    bang(result)
                }
            } else {
                Spacer()
            }
        }
        .padding()
        .navigationTitle("SQL nhanh")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandGradient, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func bang(_ result: AdminQueryResultDto) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                ForEach(result.columns, id: \.self) { c in
                    Text(c).font(.caption.weight(.bold)).foregroundStyle(Color.brandPrimary)
                }
            }
            Divider().gridCellColumns(result.columns.count)
            ForEach(Array(result.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(result.columns, id: \.self) { c in
                        Text(row[c].flatMap { $0 } ?? "")
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func chay() async {
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
