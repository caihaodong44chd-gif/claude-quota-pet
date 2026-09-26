import AppKit
import Combine

/// 盯着 Claude 和 Codex 桌面端有没有在运行。
/// 用 runningApplications 的 KVO，不用 didLaunch / didTerminate 通知：
/// 那两个通知只发给有 Dock 图标的 App，KVO 什么 App 都能收到。
@MainActor
final class AppWatcher: ObservableObject {
    nonisolated static let claudeBundleID = "com.anthropic.claudefordesktop"
    nonisolated static let codexBundleID = "com.openai.codex"

    @Published private(set) var claudeRunning: Bool
    @Published private(set) var codexRunning: Bool

    private var cancellables: Set<AnyCancellable> = []

    /// claudeBundleID 可以换成别的 App，调试用（--watch-bundle-id）
    init(claudeBundleID: String = AppWatcher.claudeBundleID, codexBundleID: String = AppWatcher.codexBundleID) {
        let apps = NSWorkspace.shared.runningApplications
        claudeRunning = Self.isRunning(claudeBundleID, in: apps)
        codexRunning = Self.isRunning(codexBundleID, in: apps)

        // runningApplications 只会在主线程变化
        let running = NSWorkspace.shared.publisher(for: \.runningApplications)
        running.map { Self.isRunning(claudeBundleID, in: $0) }
            .removeDuplicates()
            .sink { [weak self] in self?.claudeRunning = $0 }
            .store(in: &cancellables)
        running.map { Self.isRunning(codexBundleID, in: $0) }
            .removeDuplicates()
            .sink { [weak self] in self?.codexRunning = $0 }
            .store(in: &cancellables)
    }

    private nonisolated static func isRunning(_ bundleID: String, in apps: [NSRunningApplication]) -> Bool {
        apps.contains { $0.bundleIdentifier == bundleID && !$0.isTerminated }
    }
}
