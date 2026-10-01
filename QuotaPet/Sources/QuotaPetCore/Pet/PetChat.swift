import Foundation

/// 面板上和她聊天的状态：每打开一次换一句、「这么晚还在忙」一晚只说一次、连着戳会闹别扭。
/// 纯值类型，时间都由调用方传进来（App 里是 PopoverState 拿着它）
public struct PetChat: Equatable, Sendable {
    /// 同一种情况有几句时说第几句（PetStatus.line），每打开一次面板、每戳一下加一
    public private(set) var pick: Int
    /// 这次打开面板能不能说「这么晚还在忙」
    public private(set) var lateNight = true
    private var lateNightSaidAt: Date?
    /// 一共戳了几下、连着戳了几下、上一下是什么时候
    private var pokes = 0
    private var streak = 0
    private var lastPokeAt: Date?

    /// 说过「这么晚还在忙」之后，这么久以内不再说
    static let lateNightEvery: TimeInterval = 12 * 3600
    /// 被戳之后回的那句显示多久；这段时间里又戳，算连着戳
    public static let pokeLineDuration: TimeInterval = 3

    public init(pick: Int = 0) {
        self.pick = pick
    }

    /// 面板打开了
    public mutating func opened(now: Date) {
        pick += 1
        lateNight = lateNightSaidAt.map { now.timeIntervalSince($0) > Self.lateNightEvery } ?? true
    }

    /// 面板上显示了这种情况的话。每次打开、每次换了情况都要告诉它，不能只在情况变了的时候说：
    /// 两次打开之间情况没变（都是深夜）的话，时间就一直停在上一晚
    public mutating func said(_ situation: PetTalk.Situation, now: Date) {
        if situation == .lateNight { lateNightSaidAt = now }
    }

    /// 戳了她一下：她回的话、是不是被戳烦了；还没算出来时是 nil。回完之后接着说这种情况的下一句
    public mutating func poke(mood: PetMood, now: Date) -> (line: String, annoyed: Bool)? {
        let again = lastPokeAt.map { now.timeIntervalSince($0) < Self.pokeLineDuration } ?? false
        let streak = again ? self.streak + 1 : 1
        guard let poke = PetTalk.poked(mood: mood, count: pokes + 1, streak: streak) else { return nil }
        pokes += 1
        self.streak = streak
        lastPokeAt = now
        pick += 1
        return poke
    }
}
