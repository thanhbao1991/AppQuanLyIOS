import SwiftUI

/// Danh sách âm báo đọc tên khách đã tải về máy (Library/Sounds).
struct TtsSoundsView: View {
    @State private var files: [String] = []
    @State private var index: [String: String] = [:]
    @State private var dangTai = false

    private var dir: URL? {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Sounds")
    }

    var body: some View {
        List {
            Section {
                Text("\(files.count) file đã tải").font(.headline)
            }
            Section("Danh sách") {
                ForEach(files, id: \.self) { f in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(index[f] ?? f).font(.body.weight(.medium))
                        if index[f] != nil {
                            Text(f).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Âm báo đã tải")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button(dangTai ? "Đang tải…" : "Tải lại") { Task { await tai() } }.disabled(dangTai)
        }
        .task { reload(); index = await APIClient.shared.getTtsSoundIndex() }
    }

    private func reload() {
        guard let dir else { return }
        let all = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        files = all.filter { $0.hasPrefix("n_") && $0.hasSuffix(".wav") }.sorted {
            (index[$0] ?? $0).localizedCompare(index[$1] ?? $1) == .orderedAscending
        }
    }

    private func tai() async {
        dangTai = true
        await TtsSoundSync.sync()
        index = await APIClient.shared.getTtsSoundIndex()
        reload()
        dangTai = false
    }
}
