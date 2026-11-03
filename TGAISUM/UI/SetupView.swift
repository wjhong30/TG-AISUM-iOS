import SwiftUI

struct SetupView: View {
    @ObservedObject var td = TDService.shared
    @ObservedObject var settings = AppSettings.shared

    @State private var apiIdText: String = AppSettings.shared.apiId == 0 ? "" : String(AppSettings.shared.apiId)
    @State private var apiHashText: String = AppSettings.shared.apiHash
    @State private var phoneText: String = AppSettings.shared.phone
    @State private var codeText: String = ""
    @State private var passwordText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Telegram 凭据（my.telegram.org 申请）") {
                    TextField("API_ID", text: $apiIdText)
                        .keyboardType(.numberPad)
                    SecureField("API_HASH", text: $apiHashText)
                }

                switch td.authState {
                case .idle, .failed, .connecting:
                    Section("登录") {
                        TextField("手机号（国际格式，如 +8613800138000）", text: $phoneText)
                            .keyboardType(.phonePad)
                        Button("开始登录") {
                            settings.apiId = Int(apiIdText) ?? 0
                            settings.apiHash = apiHashText
                            settings.phone = phoneText
                            td.start()
                        }
                        .disabled(apiIdText.isEmpty || apiHashText.isEmpty || phoneText.isEmpty)
                    }
                default:
                    EmptyView()
                }

                if td.authState == .waitingPhone {
                    Section("验证码") {
                        TextField("手机号（国际格式）", text: $phoneText)
                            .keyboardType(.phonePad)
                        Button("发送验证码") {
                            settings.phone = phoneText
                            Task { await td.sendPhone(phoneText) }
                        }
                        .disabled(phoneText.isEmpty)
                    }
                }

                if td.authState == .waitingCode {
                    Section("输入验证码（Telegram 官方 App 内收到）") {
                        TextField("验证码", text: $codeText)
                            .keyboardType(.numberPad)
                        Button("验证") {
                            Task { await td.submitCode(codeText) }
                        }
                        .disabled(codeText.isEmpty)
                    }
                }

                if td.authState == .waitingPassword {
                    Section("两步验证密码") {
                        SecureField("密码", text: $passwordText)
                        Button("验证") {
                            Task { await td.submitPassword(passwordText) }
                        }
                        .disabled(passwordText.isEmpty)
                    }
                }

                if td.authState == .connecting {
                    Section("连接 Telegram…") {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("等待 TDLib 事件")
                        }
                        ForEach(td.eventLog, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("代理（可选，直连不通时使用）") {
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
                        Text("代理在「开始登录」时生效；已开始连接的话请返回重进。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if case .failed(let msg) = td.authState {
                    Section {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.callout)
                        ForEach(td.eventLog, id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("说明") {
                    Text("登录一次后，会话保存在本机沙盒中，下次打开无需重新登录。抓取使用你的真实用户账号，与桌面版 Telethon 行为一致。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("TG-AISUM 登录")
        }
    }
}
