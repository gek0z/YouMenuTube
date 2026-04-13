import SwiftUI

struct SearchView: View {
    @Environment(YouTubeService.self) private var yt
    @Environment(PlayerController.self) private var player
    @Environment(\.openWindow) private var openWindow
    @State private var query: String = ""
    @State private var results: [VideoEntry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var lastCompletedQuery: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search YouTube", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { triggerSearch(immediate: true) }
                if isLoading {
                    ProgressView().controlSize(.small)
                }
                if !query.isEmpty {
                    Button {
                        searchTask?.cancel()
                        query = ""
                        results = []
                        lastCompletedQuery = nil
                        isLoading = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .padding(EdgeInsets(top: 4, leading: 10, bottom: 6, trailing: 10))
            .onChange(of: query) { _, _ in triggerSearch(immediate: false) }

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let error {
            ErrorInline(message: error) { triggerSearch(immediate: true) }
        } else if !results.isEmpty {
            VideoList(entries: results) { entry in
                player.play(videoId: entry.id, title: entry.title)
                openWindow(id: WindowID.player)
            }
        } else if trimmed.isEmpty {
            ContentUnavailableView(
                "Search YouTube",
                systemImage: "magnifyingglass",
                description: Text("Type to find videos.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if lastCompletedQuery == trimmed && !isLoading {
            ContentUnavailableView.search(text: trimmed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func triggerSearch(immediate: Bool) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            lastCompletedQuery = nil
            isLoading = false
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
        do {
            let r = try await yt.search(q)
            if Task.isCancelled { return }
            results = r
            lastCompletedQuery = q
        } catch {
            if (error as? CancellationError) == nil { self.error = error.localizedDescription }
        }
    }
}
