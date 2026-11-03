import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var td = TDService.shared
    @State private var showLogoutConfirm = false
    @State private var showWipeConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Telegram 账号") {
                    HStack {
                        Text("API_ID")
                        Spacer()
                        Text("\(settings.apiId)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("手机号")
                        Spacer()
                        Text(settings.phone).foregroundStyle(.secondary)
                    }
                    Button("退出登录", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }

                Section {
                    if settings.llmNodes.isEmpty {
                        Text("尚未配置 LLM 节点，请点击下方「添加节点」")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                    ForEach($settings.llmNodes) { $node in
                        LLMNodeEditor(node: $node)
                    }
                    .onDelete { offsets in
                        settings.llmNodes.remove(atOffsets: offsets)
                    }
                    Button("添加节点") {
                        settings.llmNodes.append(
                            LLMNode(name: "节点\(settings.llmNodes.count + 1)",
                                    baseUrl: "https://", apiKey: "", model: ""))
                    }
                } header: {
                    Text("LLM 节点（OpenAI 兼容，按顺序轮询）")
                }

                Section("总结") {
                    TextField("输出风格要求", text: $settings.summaryStyle, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle("打开 App 自动同步并总结", isOn: $settings.autoSummarize)
                }

                Section("数据") {
                    Button("清空全部总结缓存", role: .destructive) {
                        showWipeConfirm = true
                    }
                }
            }
            .navigationTitle("设置")
            .confirmationDialog("退出登录会删除本机 Telegram 会话与消息归档？仅退出会话，归档保留。", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("确认退出登录", role: .destructive) {
                    Task { await td.logout() }
                }
            }
            .confirmationDialog("将删除所有已生成的总结，聊天归档保留。", isPresented: $showWipeConfirm, titleVisibility: .visible) {
                Button("确认清空", role: .destructive) {
                    SummaryStore.shared.removeAll()
                }
            }
        }
    }
}

struct LLMNodeEditor: View {
    @Binding var node: LLMNode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("名称", text: $node.name)
                .font(.headline)
            TextField("Base URL（如 https://api.minimax.chat/v1）", text: $node.baseUrl)
                .font(.caption)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            SecureField("API Key", text: $node.apiKey)
                .font(.caption)
            TextField("模型（如 MiniMax-M2.5）", text: $node.model)
                .font(.caption)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.vertical, 4)
    }
}
