import SwiftUI

@MainActor
final class GroupsModel: ObservableObject {
    @Published var chats: [(id: Int64, title: String)] = []
    @Published var loading = false
    @Published var loadError: String?

    func load() async {
        loading = true
        loadError = nil
        let result = await TDService.shared.fetchGroupChats()
        chats = result
        if result.isEmpty { loadError = "未拉取到群组，请下拉重试" }
        loading = false
    }
}

struct GroupsView: View {
    @StateObject private var model = GroupsModel()
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var sync = SyncService.shared
    @ObservedObject var archive = ArchiveStore.shared

    private var selectedSet: Set<Int64> {
        Set(settings.selectedChatIds)
    }

    var body: some View {
        NavigationStack {
            List {
                if sync.syncing {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("正在同步所选群…")
                        }
                    }
                }

                if !settings.selectedChatIds.isEmpty {
                    Section {
                        ForEach(settings.selectedChatIds, id: \.self) { chatId in
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.tint)
                                    .font(.caption)
                                Text(model.chats.first(where: { $0.id == chatId })?.title ?? "群 \(chatId)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    settings.selectedChatIds.removeAll { $0 == chatId }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.tertiary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        Button("清空清单", role: .destructive) {
                            settings.selectedChatIds.removeAll()
                        }
                    } header: {
                        Text("我的总结清单（已记住，总结页按此生成）")
                    }
                }

                Section {
                    ForEach(model.chats, id: \.id) { chat in
                        Button {
                            if selectedSet.contains(chat.id) {
                                settings.selectedChatIds.removeAll { $0 == chat.id }
                            } else {
                                settings.selectedChatIds.append(chat.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedSet.contains(chat.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedSet.contains(chat.id) ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.title)
                                        .foregroundStyle(.primary)
                                    if let state = archive.syncState[chat.id] {
                                        Text(state)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("会话列表（勾选要总结的群）")
                }

                if let error = model.loadError, model.chats.isEmpty {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if model.loading && model.chats.isEmpty {
                    ProgressView("拉取会话列表…")
                }
            }
            .refreshable {
                await model.load()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        let ids = settings.selectedChatIds
                        Task { await sync.syncAll(chatIds: ids) }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(settings.selectedChatIds.isEmpty || sync.syncing)
                }
            }
            .navigationTitle("群组")
            .task {
                if model.chats.isEmpty {
                    await model.load()
                }
            }
        }
    }
}
