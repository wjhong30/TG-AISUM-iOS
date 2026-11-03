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

                Section("代理（直连不通时使用）") {
                    Toggle("启用代理", isOn: $settings.proxyEnabled)
                    if settings.proxyEnabled {
                        Picker("类型", selection: $settings.proxyType) {
                            Text("SOCKS5").tag("socks5")
                            Text("HTTP").tag("http")
                        }
                        .pickerStyle(.segmented)
                        TextField("服务器", text: $settings.proxyServer)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("端口", value: $settings.proxyPort, format: .number)
                            .keyboardType(.numberPad)
                        TextField("用户名（可选）", text: $settings.proxyUser)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("密码（可选）", text: $settings.proxyPassword)
                        Text("修改代理后需退出登录重新连接（或重启 App）。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("总结") {
                    TextField("输出风格要求（{style} 占位符内容）", text: $settings.summaryStyle, axis: .vertical)
                        .lineLimit(2...4)
                    Toggle("打开 App 自动同步并总结", isOn: $settings.autoSummarize)
                }

                Section {
                    TextEditor(text: $settings.promptTemplate)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay {
                            if settings.promptTemplate.isEmpty {
                                Text("使用内置默认模板（可在左侧输入自定义模板覆盖）\n可用占位符：{group} {date} {slot} {style} {total} {text} {media} {senders} {transcript}")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button("恢复默认模板") {
                        settings.promptTemplate = ""
                    }
                } header: {
                    Text("提示词模板（留空用默认）")
                } footer: {
                    Text("模板会替代默认提示词。占位符：{group}=群名 {date}=日期 {slot}=时段 {style}=风格要求 {total}/{text}/{media}=消息统计 {senders}=活跃成员 {transcript}=聊天记录")
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
