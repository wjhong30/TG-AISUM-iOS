import SwiftUI
import UIKit
import BackgroundTasks

@main
struct TGAISUMApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundRefresher.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { phase in
            BackgroundRefresher.schedule()
            if phase == .background {
                BackgroundGuard.acquireIfNeeded()
            }
        }
    }
}

/// 切后台时若仍有总结在生成，申请后台运行时间让它跑完再挂起
@MainActor
enum BackgroundGuard {
    private static var taskId: UIBackgroundTaskIdentifier = .invalid

    static func acquireIfNeeded() {
        guard !SummaryStore.shared.generating.isEmpty, taskId == .invalid else { return }
        taskId = UIApplication.shared.beginBackgroundTask(withName: "summary-generate") {
            Task { @MainActor in release() }
        }
    }

    static func release() {
        guard taskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskId)
        taskId = .invalid
    }
}

/// BGAppRefreshTask：后台择机同步所选群并按 >100 条阈值生成总结。
/// iOS 不保证执行时机，只是提高"回 App 时数据已就绪"的概率。
@MainActor
enum BackgroundRefresher {
    static let taskId = "com.tgaisum.mobile.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            handle(task: task as! BGAppRefreshTask)
        }
    }

    static func schedule() {
        guard AppSettings.shared.autoSummarize,
              !AppSettings.shared.selectedChatIds.isEmpty else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(task: BGAppRefreshTask) {
        schedule() // 链式续订
        let job = Task { @MainActor in
            let ids = AppSettings.shared.selectedChatIds
            await SyncService.shared.syncAll(chatIds: ids)
            for chatId in ids {
                let dayKey = DayUtil.dayKey(Date())
                let all = ArchiveStore.shared.load(chatId)
                let messages = PromptBuilder.filter(messages: all, dayKey: dayKey, slot: .full)
                guard SummaryPolicy.shouldAutoRegenerate(
                    summary: SummaryStore.shared.get(chatId, dayKey, SlotRange.full.key),
                    currentCount: messages.count) else { continue }
                await SummaryService.generate(
                    chatId: chatId, chatTitle: "群\(chatId)", dayKey: dayKey, slot: .full)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            job.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
