import AppKit
import Combine

/// 盯着 Claude 桌面端有没有在运行。
/// 用 runningApplications 的 KVO，不用 didLaunch / didTerminate 通知：
/// 那两个通知只发给有 Dock 图标的 App，KVO 什么 App 都能收到。
@MainActor
final class ClaudeAppWatcher: ObservableObject {
    nonisolated static let claudeBundleID = "com.anthropic.claudefordesktop"

    @Published private(set) var isRunning: Bool

    private let bundleID: String
    private var cancellables: Set<AnyCancellable> = []

    /// bundleID 可以换成别的 App，调试用（--watch-bundle-id）
    init(bundleID: String = ClaudeAppWatcher.claudeBundleID) {
        self.bundleID = bundleID
        isRunning = Self.isRunning(bundleID, in: NSWorkspace.shared.runningApplications)

        // runningApplications 只会在主线程变化
        NSWorkspace.shared.publisher(for: \.runningApplications)
            .map { Self.isRunning(bundleID, in: $0) }
            .removeDuplicates()
            .sink { [weak self] running in self?.isRunning = running }
            .store(in: &cancellables)
    }

    private nonisolated static func isRunning(_ bundleID: String, in apps: [NSRunningApplication]) -> Bool {
        apps.contains { $0.bundleIdentifier == bundleID && !$0.isTerminated }
    }
}
