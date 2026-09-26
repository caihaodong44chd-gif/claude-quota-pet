import AppKit
import Combine
import QuotaPetCore

/// 调度刷新：文件一变（FSEvents）就重算，另外每分钟兜底刷新一次（重置倒计时要走）。
/// 真正的计算在后台串行队列上跑。
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?

    /// 每次拿到新数据时回调（旧快照，新快照），用来发通知
    var onUpdate: ((UsageSnapshot?, UsageSnapshot) -> Void)?

    private let provider: UsageProvider
    private let settings: AppSettings
    private let queue = DispatchQueue(label: "QuotaPet.usage", qos: .utility)
    private var watcher: FileWatcher?
    private var pollTimer: Timer?
    private var debounce: Task<Void, Never>?
    private var isRunning = false
    private var runAgain = false
    private var cancellables: Set<AnyCancellable> = []

    init(provider: UsageProvider, settings: AppSettings) {
        self.provider = provider
        self.settings = settings
        applyConfig(settings.providerConfig)
    }

    func start() {
        watcher = FileWatcher(paths: provider.watchPaths) { [weak self] paths in
            MainActor.assumeIsolated {
                guard let self, paths.contains(where: self.provider.isRelevantChange) else { return }
                self.scheduleRefresh()
            }
        }

        let timer = Timer(timeInterval: provider.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // 改了实时估算 / 自动学习 / 每周重置时间，立刻重算
        Publishers.CombineLatest3(settings.$liveEstimate, settings.$autoLearn, settings.$weeklyResetAnchor)
            .dropFirst()
            .sink { [weak self] live, learn, anchor in
                self?.applyConfig(AppSettings.providerConfig(liveEstimate: live, autoLearn: learn, weeklyResetAnchor: anchor))
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    /// 文件事件会连着来一串，合并成一次刷新
    func scheduleRefresh(after delay: TimeInterval = 0.8) {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    func refresh() {
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        let provider = self.provider
        queue.async { [weak self] in
            let now = Date()
            let result = Result { try provider.snapshot(now: now) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(result, at: now) }
            }
        }
    }

    private func finish(_ result: Result<UsageSnapshot, Error>, at now: Date) {
        isRunning = false
        switch result {
        case .success(let new):
            let old = snapshot
            if new != old { snapshot = new }
            errorMessage = nil
            lastUpdated = now
            onUpdate?(old, new)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
        if runAgain {
            runAgain = false
            refresh()
        }
    }

    private func applyConfig(_ config: ClaudeProvider.Config) {
        (provider as? ClaudeProvider)?.config = config
    }
}
