import AppKit
import Combine
import SwiftUI
import QuotaPetCore

/// 菜单栏上的宠物 + 文字。左键弹出面板，右键 / Control-点按弹出菜单。
/// 默认只在 Claude 桌面端打开时出现（设置里可以改成一直显示）。
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private static let autosaveName = "QuotaPet"
    /// 系统记录图标位置的 key（用户按住 ⌘ 拖动后系统会更新它）
    private static let positionKey = "NSStatusItem Preferred Position \(autosaveName)"
    /// 我们自己备份的位置
    private static let savedPositionKey = "statusItemPosition"

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let store: UsageStore
    private let settings: AppSettings
    private let animator: PetAnimator
    private let claudeWatcher: ClaudeAppWatcher
    private let popoverState = PopoverState()
    private var imageCache: [ImageKey: NSImage] = [:]
    private var cancellables: Set<AnyCancellable> = []

    // 决定显不显示的几个条件
    private var visibility: MenuBarVisibility = .withClaude
    private var claudeRunning = false
    private let keepVisible: Bool   // 演示模式一直显示
    private var pinned: Bool        // 用户临时叫出来了（再次打开 QuotaPet）

    private struct ImageKey: Hashable {
        let grid: PixelGrid
        let template: Bool
    }

    init(store: UsageStore, settings: AppSettings, animator: PetAnimator, claudeWatcher: ClaudeAppWatcher, keepVisible: Bool) {
        self.store = store
        self.settings = settings
        self.animator = animator
        self.claudeWatcher = claudeWatcher
        self.keepVisible = keepVisible
        self.pinned = keepVisible

        Self.restorePosition()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = Self.autosaveName
        super.init()
        configureButton()
        configurePopover()

        Publishers.CombineLatest(animator.$frame, settings.$monochromePet)
            .sink { [weak self] frame, monochrome in self?.showPet(frame.icon, template: monochrome) }
            .store(in: &cancellables)
        Publishers.CombineLatest(store.$snapshot, settings.$menuBarText)
            .sink { [weak self] snapshot, mode in self?.showText(snapshot, mode: mode) }
            .store(in: &cancellables)
        Publishers.CombineLatest(store.$snapshot, store.$errorMessage)
            .sink { [weak animator] snapshot, error in
                animator?.setMood(snapshot == nil && error != nil ? .confused : PetMood.from(snapshot: snapshot))
            }
            .store(in: &cancellables)
        Publishers.CombineLatest(settings.$visibility, claudeWatcher.$isRunning)
            .sink { [weak self] visibility, running in
                self?.visibility = visibility
                self?.claudeRunning = running
                self?.updateVisibility()
            }
            .store(in: &cancellables)
    }

    /// Claude 开着（或设置成一直显示）才出现；藏起来时动画也停掉，只在后台等着发提醒
    private func updateVisibility() {
        let show = visibility.shouldShow(claudeRunning: claudeRunning, pinned: pinned || popover.isShown)
        if statusItem.isVisible != show {
            if show { Self.restorePosition() } else { Self.rememberPosition() }
            statusItem.isVisible = show
        }
        animator.isVisible = show
    }

    // 新图标默认排在菜单栏最左边，菜单栏一挤（尤其是刘海屏）就会藏到刘海后面。
    // 所以第一次把它放到最右边、紧挨着时钟（位置 0）。
    // macOS 26 在隐藏图标时会删掉位置记录，再显示就跑回最左边，所以隐藏前备份一份，显示前写回去。
    private static func restorePosition() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: positionKey) == nil {
            defaults.set(defaults.object(forKey: savedPositionKey) ?? 0, forKey: positionKey)
        }
    }

    private static func rememberPosition() {
        if let position = UserDefaults.standard.object(forKey: positionKey) {
            UserDefaults.standard.set(position, forKey: savedPositionKey)
        }
    }

    /// 宠物藏起来的时候，再次打开 QuotaPet（Spotlight / 启动台）就把它叫出来，并打开面板
    func reveal() {
        pinned = true
        updateVisibility()
        // 图标刚出现时位置还没排好，等一下再弹面板
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.popover.isShown else { return }
                self.togglePopover()
            }
        }
    }

    // MARK: - 菜单栏

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
    }

    private func showPet(_ frame: PixelGrid, template: Bool) {
        let key = ImageKey(grid: frame, template: template)
        let image = imageCache[key] ?? PetRenderer.image(frame, pixel: 0.5, template: template)
        imageCache[key] = image
        statusItem.button?.image = image
    }

    private func showText(_ snapshot: UsageSnapshot?, mode: MenuBarTextMode) {
        guard let button = statusItem.button else { return }
        let now = Date()
        let (text, level) = MenuBarText.make(snapshot, mode: mode, now: now)
        let title = text.isEmpty ? "" : " " + text
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let limited = snapshot?.windows.contains { $0.percent >= 100 } ?? false
        if !limited, level >= 75 {
            // 快用完了：数字标橙 / 标红。被限流时宠物已经在睡觉了，倒计时就不标红吓人了
            let color: NSColor = level >= 90 ? .systemRed : .systemOrange
            button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: color])
        } else {
            button.font = font
            button.title = title
        }
        button.toolTip = tooltip(for: snapshot, now: now)
        button.setAccessibilityLabel("QuotaPet " + (button.toolTip ?? ""))
    }

    private func tooltip(for snapshot: UsageSnapshot?, now: Date) -> String {
        guard let snapshot, snapshot.hasData else { return "QuotaPet：还没有额度数据" }
        let lines = snapshot.windows.map { w -> String in
            var line = "\(w.title) \(Fmt.percent(w.clampedPercent))"
            if let reset = w.resetsAt { line += "，约 \(Fmt.duration(reset.timeIntervalSince(now)))后重置" }
            return line
        }
        return (["\(snapshot.provider.displayName) 额度"] + lines).joined(separator: "\n")
    }

    // MARK: - 点击

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func configurePopover() {
        let root = PopoverRoot(store: store, settings: settings, state: popoverState, animator: animator,
                               onQuit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.delegate = self
    }

    private func togglePopover(page: PopoverState.Page = .overview) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popoverState.page = page
        store.refresh()
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        popoverState.page = .overview
        pinned = keepVisible
        updateVisibility()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(menuItem("立即刷新", #selector(refreshNow), "r"))
        menu.addItem(menuItem("设置…", #selector(openSettings), ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 QuotaPet", #selector(quit), "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)  // 弹出菜单，关掉后才返回
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refreshNow() { store.refresh() }
    @objc private func openSettings() { togglePopover(page: .settings) }
    @objc private func quit() { NSApp.terminate(nil) }
}
