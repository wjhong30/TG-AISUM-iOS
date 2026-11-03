# TG-AISUM iOS

Telegram 群聊 AI 总结的 iPhone 客户端。定位与 [TG-AISUM Desktop](https://github.com/wjhong30/TG-AISUM-Desktop) 互补：
桌面端负责抓取与导出，本 App 负责**在手机上直接读 AI 总结**——登录、拉群、增量同步、生成总结都在 App 内完成，
不需要开着电脑。

产物是**未签名 IPA**，用 TrollStore（巨魔）直接安装，不依赖 Xcode 平台组件、不需要签名证书。

- 最低系统：iOS 16.0（arm64）
- 数据全部落在 App 沙盒内（`Documents/td-db`、`Documents/archive`、`Documents/summaries.json`），
  除你自己在设置里填的 LLM 接口外不上传任何第三方服务器。

---

## 目录

- [一、功能](#一功能)
- [二、安装（TrollStore）](#二安装trollstore)
- [三、首次使用](#三首次使用)
- [四、从源码构建 IPA](#四从源码构建-ipa)
- [五、目录结构](#五目录结构)
- [六、常见问题](#六常见问题)
- [七、版本](#七版本)
- [八、License / 致谢](#八license--致谢)

---

## 一、功能

**消息页（首页，QQ 式聊天列表）**
- 按最近消息排序的会话列表：头像、最后一条消息预览、时间、今日消息数与「N 条新」角标，正在生成时显示「总结中」。
- 点进任意群直达该群的 AI 总结页；顶部按钮一键「同步 + 按需总结」所选群。

**总结页（元宝式卡片）**
- 顶部卡片：共 N 条消息 / 正在总结 / 已总结 N 条消息；有新消息时提示「有 N 条新消息，满 100 条才自动重算」。
- 日期 + 时段（凌晨 / 上午 / 下午 / 晚上 / 全天 / 自定义区间，时区固定 Asia/Shanghai）。
- 正文 = 总览一句话 + 2~6 个话题卡片（话题标题 + 时间区间 + 要点列表），要点讲清起因→发展→结论；「复制全文」一键复制。
- **引用编号**：要点后附 `(n)` 编号圆片，编号来自提示词阶段对真实消息的编号（提示词禁止编造），
  点击进入「N 条群聊记录」气泡页，自动滚动并高亮被引用的消息。
- 省 token：打开页面时只有新消息比上次总结多出 100 条以上才自动重新生成，否则沿用缓存；手动重算不受限制。
- 结果按 `群 × 日期 × 时段` 缓存，重进不重算；解析失败自动回退纯文本渲染。
- 输出去掉 `#` / `**` / 反引号 / 代码块围栏等 markdown 记号，按段落重排（首行加粗、行距放宽、可选中复制）。

**群组页**
- 登录后拉取真实会话列表（仅普通群与超级群），勾选加入**我的总结清单**；清单持久化保存，总结页只按清单生成。
- 清单可逐条移除、一键清空；顶部按钮触发增量同步。

**同步**
- TDLib `getChatHistory` 反向翻页（每页 100 条，按消息 id 去重），增量窗口取「上次同步时间 − 1 小时」，首次同步抓 7 天；
  翻页不以单批数量为结束依据（TDLib 单批常少于 100 条），同步断点记实际归档的最新消息时间，截断自动回补。
- 归档落盘为 `Documents/archive/chat_{chatId}.json`；默认不下载媒体，媒体消息以 `[图片]` 之类占位文本入库。

**设置页**
- Telegram 凭据（`API_ID` / `API_HASH`）、手机号、退出登录。
- LLM 节点：多个 OpenAI 兼容端点（名称 / baseUrl / apiKey / model），按顺序降级重试，单请求超时 180s。
- 代理：SOCKS5 / HTTP（直连不通时用），改完需退出登录重连。
- 提示词模板：可编辑，留空则用内置默认模板，支持占位符
  `{group} {date} {slot} {style} {total} {text} {media} {senders} {transcript}`，一键恢复默认。
- 总结风格、自动总结开关、清空全部总结缓存。

---

## 二、安装（TrollStore）

1. 到 [Releases](https://github.com/wjhong30/TG-AISUM-iOS/releases) 下载最新版 `TGAISUM-<version>.ipa`。
2. 用 TrollStore 安装。
3. 覆盖安装保留登录态与已同步的聊天记录，升级不必重新登录。
4. 未越狱 / 未装 TrollStore 的设备装不了：本 App 未签名，App Store、TestFlight、描述文件通道都不生效。

---

## 三、首次使用

1. **准备凭据**：<https://my.telegram.org> → API development tools，拿到 `api_id` 与 `api_hash`。
2. **设置页填凭据**，回登录页输入手机号（国际格式，如 `+8613800000000`）→ 获取验证码 → 填验证码；开了两步验证再填密码。
3. 登录成功后进「群组」，勾选要总结的群（进清单），点顶部同步。
4. 回「总结」页选日期与时段等待生成。首次生成前需要在设置页配好至少一个 LLM 节点。

抓群历史必须用**用户会话**（Bot 通常没有群历史权限），这也是本 App 自己内嵌 TDLib、而不复用桌面端后端的原因。

---

## 四、从源码构建 IPA

前提：macOS + Xcode 命令行工具（只需 `swiftc` / `strip` / `plutil`）、`ldid`（`brew install ldid`）、约 2 GB 磁盘。
**全程不需要下载 iOS 平台组件**，也不走 xcodebuild 的 destination——脚本是 Theos 那套直接交叉编译。

```bash
git clone https://github.com/wjhong30/TG-AISUM-iOS.git
cd TG-AISUM-iOS

# 1) 取 TDLib 预编译框架（约 355 MB zip）
curl -L -o vendor/TDLibFramework.zip \
  https://github.com/Swiftgram/TDLibFramework/releases/download/1.8.69-4c6377aa/TDLibFramework.zip

# 校验（应与该 release 一致）
shasum -a 256 vendor/TDLibFramework.zip
#   c86ca527be4adb4e2562693176b28a74290a86e9a55988af5c169420c6b77d49

# 2) 构建：首次约几分钟（TDLibKit 1965 个文件），之后复用 build/swiftc 里的缓存只编 App
./build_ipa.sh
# 产物：TGAISUM.ipa 与 TGAISUM-<version>.ipa
```

已解压到别处就用环境变量指定：

```bash
TDLIB_XCFRAMEWORK=/path/to/TDLibFramework.xcframework ./build_ipa.sh
```

脚本做四件事：

1. `swiftc -emit-module` + `-emit-library -static` 把 `vendor/TDLibKit` 编成 `TDLibKit.swiftmodule` + `libTDLibKit.a`。
   **必须独立成模块**：TDLibKit 里有 `Date` 等与 Foundation 重名的生成类型，和 App 源码同模块编译会冲突。
   缓存存在时跳过这步。
2. 用 `-I build/swiftc` 导入该模块编译 App，静态链接 TDLib（`-lc++ -lz`），所以 IPA 里没有 `Frameworks/` 目录。
3. `strip -x` 瘦身（约 118 MB → 80 MB）后用 `ldid -S` 伪签名——顺序不能反，先签名再 strip 会让签名失效。
4. 打包 `Payload/TGAISUM.app` 为 IPA，并按 `CFBundleShortVersionString` 额外生成带版本号的副本。

`vendor/TDLibKit` 来自 <https://github.com/Swiftgram/TDLibKit> tag `1.5.2-tdlib-1.8.69-4c6377aa`，
其中 `TDLibClientManager.swift` 与 `TdClientImpl.swift` 的 `import TDLibFramework` 改成了 `import TDLibShim`
（`vendor/TDLibShim/` 是手写的 C 声明 + modulemap，直接暴露 `td_send` / `td_receive` / `td_execute` 等符号），
这样就不依赖 Swift Package Manager 的资源打包。

`project.yml` 是早期 xcodegen 方案留下的，构建脚本不用它；想用 Xcode 打开工程可 `xcodegen generate`
（生成的 `TGAISUM.xcodeproj` 已被 `.gitignore` 忽略）。

### 换版本号 / 换 Bundle ID

改 `Info_plist_template.plist` 里的 `CFBundleShortVersionString`（脚本据此生成带版本号的 IPA 副本名）
与 `CFBundleIdentifier`（默认 `com.tgaisum.mobile`，TrollStore 按它判定是否为覆盖安装）。

---

## 五、目录结构

```
TGAISUM/
  App/        TGAISUMApp.swift（入口）、RootView.swift（按登录态切界面）
  Config/     AppSettings.swift（UserDefaults：凭据 / LLM 节点 / 代理 / 清单 / 模板）
  Telegram/   TDService.swift（TDLib 客户端、授权状态机、会话列表、历史翻页、发送者名缓存）
  Sync/       ArchiveStore.swift（按群归档 + 按 id 去重合并 + 增量窗口）
  Summary/    Slot.swift（时段与 Asia/Shanghai 日期工具）
              PromptBuilder.swift（默认模板 / 占位符填充 / 去 markdown）
              LLMClient.swift（OpenAI 兼容多节点降级）
              SummaryStore.swift（总结缓存与生成状态）
  UI/         SetupView / MainView / ChatListView / GroupSummaryView / ChatLogView / GroupsView / SettingsView / RichTextView
vendor/
  TDLibKit/   TDLib 生成绑定（1965 个 .swift）
  TDLibShim/  C 声明 + modulemap
build_ipa.sh               构建脚本（swiftc + strip + ldid + zip）
Info_plist_template.plist  打包时拷成 .app/Info.plist
project.yml                xcodegen 配置（可选）
```

---

## 六、常见问题

**一直卡在「连接 Telegram…」，事件日志为空**
本机到 Telegram 的直连不通（官方客户端能连不代表这里也能，它可能走了应用内 MTProxy）。
在登录页或设置页配 SOCKS5 / HTTP 代理后重连。25 秒内没有任何 TDLib 事件，App 会主动报错并保留事件日志。

**事件日志里有 `updateAuthorizationState`，但状态不前进**
升级到 v0.1.2 起。TDLib 的 JSON 键是 snake_case，TDLibKit 生成的 Codable 是驼峰，
解码器必须开 `keyDecodingStrategy = .convertFromSnakeCase`，否则授权状态机解不出来。

**列表里没有目标群**
只列普通群与超级群；频道、私聊、机器人不入选。先确认账号在群里，再回群组页刷新会话。

**总结是空的**
该时段没有文本消息（只有含文本的消息进提示词），或 LLM 节点没配 / 全部失败。卡片上会显示错误原因。

**想要桌面端那种 JSON / Markdown / CSV 导出**
去 [TG-AISUM Desktop](https://github.com/wjhong30/TG-AISUM-Desktop)，手机端不做文件导出。

---

## 七、版本

见 [CHANGELOG.md](./CHANGELOG.md)。每个版本都有对应 git tag 与 GitHub Release，Release 里附该版本的 IPA。

| 版本 | tag | 要点 |
|---|---|---|
| 0.5.3 | [`v0.5.3`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.5.3) | 文件查看/保存、切后台继续总结、桌面版 logo 图标、总结更深（话题数按消息量自适应）、总结分享、失败自动重试 |
| 0.5.2 | [`v0.5.2`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.5.2) | 按需抓取历史日期、记录页看图片、后台刷新、圆片改「查看记录」、模板格式收紧 |
| 0.5.1 | [`v0.5.1`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.5.1) | 修复同步翻页提前截断+断点照常前进导致的「时段没有文本消息」缺口；升级后首次同步全量重抓 7 天回补 |
| 0.5.0 | [`v0.5.0`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.5.0) | 总结内容回到元宝话题式（总览+话题卡），要点讲清起因→发展→结论，撤回六板块结构 |
| 0.4.1 | [`v0.4.1`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.4.1) | 分节解析兼容中文序号（一、/1、）分节，不退化为纯文本 |
| 0.4.0 | [`v0.4.0`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.4.0) | 总结内容回归桌面版六板块深度报告（消息统计/核心话题/时间线/成员观点/技术汇总/趋势/待解决），元宝卡片式渲染 |
| 0.3.1 | [`v0.3.1`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.3.1) | 修复话题标题占位符照抄；行内引用编号只留圆片；话题时间区间可点击查看该段记录 |
| 0.3.0 | [`v0.3.0`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.3.0) | QQ 式聊天列表 + 元宝式话题卡片总结页、引用编号直达原始群聊记录、>100 条才自动重算的省 token 策略 |
| 0.2.0 | [`v0.2.0`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.2.0) | 四时段 + 自定义、我的总结清单、可编辑提示词模板、输出去 markdown 并排版 |
| 0.1.2 | [`v0.1.2`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.1.2) | 修复授权事件解码，登录端到端可用 |
| 0.1.1 | [`v0.1.1`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.1.1) | 登录事件日志、连接超时诊断、SOCKS5/HTTP 代理 |
| 0.1.0 | [`v0.1.0`](https://github.com/wjhong30/TG-AISUM-iOS/releases/tag/v0.1.0) | 首版：TDLib 登录、群选择、增量同步、按群按时段总结、缓存与 UI |

0.1.x 的 IPA 是按对应 tag 的源码重新构建的（当时都输出到同一个 `TGAISUM.ipa` 路径、被后续版本覆盖），
详见 CHANGELOG 末尾说明。

---

## 八、License / 致谢

MIT，Copyright (c) 2026 jhong，详见 [LICENSE](./LICENSE)。

- [Swiftgram/TDLibKit](https://github.com/Swiftgram/TDLibKit)（tag `1.5.2-tdlib-1.8.69-4c6377aa`）提供 TDLib 的 Swift 绑定，
  `vendor/TDLibKit` 是其源码并按上文说明改了 import。
- [Swiftgram/TDLibFramework](https://github.com/Swiftgram/TDLibFramework)（release `1.8.69-4c6377aa`）提供预编译 xcframework，
  内含 [tdlib/td](https://github.com/tdlib/td/tree/4c6377aa)；该框架在构建时下载，不随本仓库分发。
- 产品形态与提示词模板沿用 [TG-AISUM Desktop](https://github.com/wjhong30/TG-AISUM-Desktop)。
