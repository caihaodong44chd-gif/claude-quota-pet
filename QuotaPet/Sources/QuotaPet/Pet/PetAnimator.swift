import AppKit
import Combine
import QuotaPetCore

/// 播放宠物动画。菜单栏（头像）和面板（半身像）用同一个时，表情同步；
/// 面板切到另一家时，面板上的宠物由另一个 PetAnimator 播。
@MainActor
final class PetAnimator: ObservableObject {
    @Published private(set) var frame: PetFrame
    private(set) var mood: PetMood = .loading
    private(set) var style: PetStyle

    private var frames: [PetFrame]
    private var index = 0
    private var timer: Timer?
    private var animates: Bool
    private var screenAsleep = false
    /// 宠物藏起来（菜单栏上藏起来、面板关着）时不用播动画
    var isVisible = true {
        didSet { if isVisible != oldValue { restart() } }
    }
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings, style: PetStyle, isVisible: Bool = true) {
        self.style = style
        self.isVisible = isVisible
        frames = PetSprites.frames(for: .loading, style: style)
        frame = frames[0]
        animates = settings.animatePet

        settings.$animatePet
            .dropFirst()
            .sink { [weak self] on in
                self?.animates = on
                self?.restart()
            }
            .store(in: &cancellables)

        // 屏幕睡眠时停掉动画，省电
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.screensDidSleepNotification)
            .sink { [weak self] _ in
                self?.screenAsleep = true
                self?.restart()
            }
            .store(in: &cancellables)
        workspace.publisher(for: NSWorkspace.screensDidWakeNotification)
            .sink { [weak self] _ in
                self?.screenAsleep = false
                self?.restart()
            }
            .store(in: &cancellables)

        restart()
    }

    /// 换心情或形象（跟着的那家变了、改了设置）；都没变就接着播
    func show(mood: PetMood, style: PetStyle) {
        guard mood != self.mood || style != self.style else { return }
        self.mood = mood
        self.style = style
        frames = PetSprites.frames(for: mood, style: style)
        index = 0
        restart()
    }

    /// 被戳了一下：把反应播一遍，再回到原来的动画。是用户自己点的，没开动画也播。
    /// mood：面板上显示的心情（她回的话按它挑，反应也按它，两样才对得上）。annoyed：连着戳了很多下
    func react(mood: PetMood, annoyed: Bool) {
        let reaction = PetSprites.reaction(for: mood, style: style, annoyed: annoyed)
        guard !reaction.isEmpty, !screenAsleep, isVisible else { return }
        play(reaction[...])
    }

    private func play(_ reaction: ArraySlice<PetFrame>) {
        timer?.invalidate()
        guard let next = reaction.first else {
            index = 0
            restart()
            return
        }
        frame = next
        schedule(after: next.duration) { $0.play(reaction.dropFirst()) }
    }

    private func restart() {
        timer?.invalidate()
        timer = nil
        if !animates { index = 0 }
        index = min(index, frames.count - 1)
        frame = frames[index]
        guard animates, !screenAsleep, isVisible, frames.count > 1 else { return }
        scheduleNext()
    }

    private func scheduleNext() {
        schedule(after: frames[index].duration) { $0.advance() }
    }

    private func schedule(after delay: TimeInterval, _ then: @escaping @MainActor (PetAnimator) -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { then(self) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)  // 菜单打开时也继续动
        self.timer = timer
    }

    private func advance() {
        index = (index + 1) % frames.count
        frame = frames[index]
        scheduleNext()
    }
}
