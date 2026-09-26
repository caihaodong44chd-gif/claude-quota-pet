import AppKit
import Combine
import QuotaPetCore

/// 播放宠物动画。菜单栏（头像）和面板（半身像）用同一帧，表情同步。
@MainActor
final class PetAnimator: ObservableObject {
    @Published private(set) var frame: PetFrame
    private(set) var mood: PetMood = .loading
    private var style: PetStyle

    private var frames: [PetFrame]
    private var index = 0
    private var timer: Timer?
    private var animates: Bool
    private var screenAsleep = false
    /// 菜单栏上的宠物藏起来时不用播动画
    var isVisible = true {
        didSet { if isVisible != oldValue { restart() } }
    }
    private var cancellables: Set<AnyCancellable> = []

    init(settings: AppSettings) {
        style = settings.petStyle
        frames = PetSprites.frames(for: .loading, style: style)
        frame = frames[0]
        animates = settings.animatePet

        settings.$petStyle
            .dropFirst()
            .sink { [weak self] style in
                guard let self else { return }
                self.style = style
                frames = PetSprites.frames(for: mood, style: style)
                restart()
            }
            .store(in: &cancellables)

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

    func setMood(_ mood: PetMood) {
        guard mood != self.mood else { return }
        self.mood = mood
        frames = PetSprites.frames(for: mood, style: style)
        index = 0
        restart()
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
        let timer = Timer(timeInterval: frames[index].duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
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
