import AppKit
import Combine
import QuotaPetCore

/// 调度刷新：文件一变（FSEvents）就重算那一家，另外每分钟兜底把几家都重算一次（重置倒计时要走）。
/// 真正的计算在同一个后台串行队列上跑；每家算完就单独更新，不用等别家。
@MainActor
final class UsageStore: ObservableObject {
    /// 各家的最新快照，顺序和 providers 一样（Claude 在前）；算出错的那家保留上一次的结果
    @Published private(set) var snapshots: [UsageSnapshot] = []
    /// 算出错的原因，按数据源
    @Published private(set) var errors: [ProviderID: String] = [:]
    /// 宠物对每一家记得的事（刚恢复、刚才的警报），心情和台词要用。只记在内存里，重启 App 就忘了
    private(set) var memory: [ProviderID: PetMemory] = [:]
    /// 每次兜底刷新时走一下。宠物的心情和时间有关（刚恢复十分钟、闲了半小时），
    /// 读取一直出错时快照和错误信息都不变，靠它让菜单栏和面板照样重算
    @Published private(set) var tick = Date()

    /// 每次拿到某一家的新数据时回调（旧快照，新快照），用来发通知
    var onUpdate: ((UsageSnapshot?, UsageSnapshot) -> Void)?

    private let providers: [UsageProvider]
    private let settings: AppSettings
    private let queue = DispatchQueue(label: "QuotaPet.usage", qos: .utility)
    private var watcher: FileWatcher?
    /// 正在监听的目录（启动时还不存在的目录，兜底刷新时会补上）
    private var watchedPaths: [String] = []
    private var pollTimer: Timer?
    private var debounce: Task<Void, Never>?
    /// 等着防抖结束再刷新的几家
    private var debounced: Set<ProviderID> = []
    /// 正在算的几家，和算的时候又有新变化、算完要再算一次的几家
    private var running: Set<ProviderID> = []
    private var again: Set<ProviderID> = []
    private var cancellables: Set<AnyCancellable> = []

    init(providers: [UsageProvider], settings: AppSettings) {
        self.providers = providers
        self.settings = settings
        applyConfig(settings.providerConfig)
    }

    /// 面板和菜单栏要显示的几家
    var shown: [UsageSnapshot] { UsageSnapshot.visible(snapshots, hidden: settings.hiddenProviders) }

    /// 宠物和菜单栏跟着的那家：最紧张的
    var focus: UsageSnapshot? { UsageSnapshot.focus(of: shown) }

    func snapshot(for provider: ProviderID) -> UsageSnapshot? {
        snapshots.first { $0.provider == provider }
    }

    func start() {
        updateWatcher()

        let timer = Timer(timeInterval: providers.map(\.pollInterval).min() ?? 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateWatcher()
                self?.refresh()
                self?.tick = Date()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        // 改了实时估算 / 自动学习 / 每周重置时间，立刻重算（只影响 Claude）
        Publishers.CombineLatest3(settings.$liveEstimate, settings.$autoLearn, settings.$weeklyResetAnchor)
            .dropFirst()
            .sink { [weak self] live, learn, anchor in
                self?.applyConfig(AppSettings.providerConfig(liveEstimate: live, autoLearn: learn, weeklyResetAnchor: anchor))
                self?.refresh([.claude])
            }
            .store(in: &cancellables)

        // 换了界面语言：快照里的窗口名、说明文字要用新语言重算
        settings.$language
            .dropFirst()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    /// 要监听的目录可能是后来才有的（比如 App 开着的时候才第一次用 Codex）：目录有变化就重建监听
    private func updateWatcher() {
        let existing = providers.flatMap(\.watchPaths).filter { FileManager.default.fileExists(atPath: $0) }
        guard existing != watchedPaths else { return }
        watchedPaths = existing
        watcher = FileWatcher(paths: existing) { [weak self] paths in
            MainActor.assumeIsolated {
                guard let self else { return }
                let changed = self.providersAffected(by: paths)
                if !changed.isEmpty { self.scheduleRefresh(changed) }
            }
        }
    }

    /// 哪几家的文件变了：路径在它监听的目录下、它也认这个文件。
    /// 路径对不上任何一家的目录（比如软链接被展开了）时，交给所有认这个文件的
    private func providersAffected(by paths: [String]) -> Set<ProviderID> {
        var ids = Set<ProviderID>()
        for path in paths {
            let owners = providers.filter { $0.watchPaths.contains { path == $0 || path.hasPrefix($0 + "/") } }
            for provider in owners.isEmpty ? providers : owners where provider.isRelevantChange(path: path) {
                ids.insert(provider.id)
            }
        }
        return ids
    }

    /// 文件事件会连着来一串，合并成一次刷新
    func scheduleRefresh(_ ids: Set<ProviderID>, after delay: TimeInterval = 0.8) {
        debounced.formUnion(ids)
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let ids = debounced
            debounced = []
            refresh(ids)
        }
    }

    /// 重算这几家（nil = 全部）。某一家正在算时，等它算完再算一次
    func refresh(_ ids: Set<ProviderID>? = nil) {
        for provider in providers where ids?.contains(provider.id) ?? true {
            let id = provider.id
            if running.contains(id) {
                again.insert(id)
                continue
            }
            running.insert(id)
            queue.async { [weak self] in
                let result = Result { try provider.snapshot(now: Date()) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finish(id, result) }
                }
            }
        }
    }

    private func finish(_ id: ProviderID, _ result: Result<UsageSnapshot, Error>) {
        running.remove(id)
        switch result {
        case .success(let new):
            let old = snapshot(for: id)
            // 要在 snapshots 赋值之前记好：订阅者收到新快照时会来读
            memory[id] = (memory[id] ?? PetMemory()).updated(from: old, to: new, now: new.generatedAt)
            let next = providers.compactMap { $0.id == id ? new : snapshot(for: $0.id) }
            if next != snapshots { snapshots = next }
            if errors[id] != nil { errors[id] = nil }
            onUpdate?(old, new)
        case .failure(let error):
            if errors[id] != error.localizedDescription { errors[id] = error.localizedDescription }
        }
        if again.remove(id) != nil { refresh([id]) }
    }

    private func applyConfig(_ config: ClaudeProvider.Config) {
        for case let provider as ClaudeProvider in providers {
            provider.config = config
        }
    }
}
