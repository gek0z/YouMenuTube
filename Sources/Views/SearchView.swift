import SwiftUI

struct SearchView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(PlayerController.self) private var player
    @Environment(\.openWindow) private var openWindow
    @State private var query: String = ""
    @State private var results: [VideoEntry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search YouTube", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { triggerSearch(immediate: true) }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .onChange(of: query) { _, _ in triggerSearch(immediate: false) }

            if let error {
                ErrorInline(message: error) { triggerSearch(immediate: true) }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.isEmpty {
                ContentUnavailableView(
                    "Search YouTube",
                    systemImage: "magnifyingglass",
                    description: Text("Type to find videos."))
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { entry in
                            VideoRow(entry: entry) {
                                player.play(videoId: entry.id, title: entry.title)
                                openWindow(id: "player")
                            }
                            Divider().opacity(0.3)
                        }
                    }
                }
            }
        }
    }

    private func triggerSearch(immediate: Bool) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
            }
            await runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do { results = try await yt.search(q) } catch {
            if (error as? CancellationError) == nil { self.error = error.localizedDescription }
        }
    }
}
