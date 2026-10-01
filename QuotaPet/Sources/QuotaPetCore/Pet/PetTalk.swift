import Foundation

/// 宠物在面板上说的话：看的是实际情况（快用完了、烧得快、刚恢复…），不只是用了多少。
/// 从上往下找第一个符合的情况；同一种情况有几句，面板每打开一次换一句（Options.pick）。
/// 趋势和心情看的是同一份（PetTrend），表情和台词对得上
public enum PetTalk {
    /// 说话的由头，按优先级从高到低
    public enum Situation: String, CaseIterable, Sendable {
        /// 还没算出来
        case loading
        /// 读不到数据
        case confused
        /// 用完了
        case usedUp
        /// 刚看到额度恢复
        case recovered
        /// 照最近的速度眼看要用完（和「快用完」提醒同一个标准，见 UsageWindow.warningLead）
        case runningOut
        /// 90% 以上
        case almostOut
        /// 还没到 75%，但 5 小时这种短窗口照这个速度撑不到重置
        case burningFast
        /// 75%–90%
        case tired
        /// 不紧张，但每周额度这种长窗口和平均节奏差得多
        case pace
        /// 聊天、网页、手机正在用
        case elsewhere
        /// 有一阵没用了
        case idle
        /// 深夜还在用
        case lateNight
        /// 没什么特别的，按心情说
        case ordinary
    }

    public struct Options: Equatable, Sendable {
        /// 同一种情况有几句时说第几句（取余数），面板每打开一次加一
        public var pick: Int
        /// 最近一次看到这家的额度恢复是什么时候（见 recovered(from:to:)）
        public var recoveredAt: Date?
        /// 能不能说「这么晚还在忙」：一晚只说一次，说过了由 App 关掉
        public var lateNight: Bool

        public init(pick: Int = 0, recoveredAt: Date? = nil, lateNight: Bool = true) {
            self.pick = pick
            self.recoveredAt = recoveredAt
            self.lateNight = lateNight
        }
    }

    /// 深夜那句：最近这么久以内用过才说
    static let activeWithin: TimeInterval = 600
    /// 深夜是几点到几点
    static let lateHours = 0..<5
    /// 和平均节奏差多少个点才说（面板上多用这么多时标橙）
    static let paceGap = 10.0

    /// 这次刷新看到额度恢复了：有窗口从六成以上掉到了 5% 以下（和「额度恢复」提醒同一个标准）
    public static func recovered(from old: UsageSnapshot?, to new: UsageSnapshot) -> Bool {
        guard let old else { return false }
        return new.windows.contains { window in
            old.window(window.id).map { UsageAlerts.recovered(from: $0.percent, to: window.percent) } ?? false
        }
    }

    /// 连着戳到第几下开始闹别扭
    static let annoyedAfter = 5

    /// 在面板上被戳了一下时说的话，按心情分几组，count 是一共第几下（从 1 数，轮着说）。还没算出来时不说。
    /// streak 是连着戳的第几下（上一句还没说完又戳）：心情好的时候连戳 5 下以上她会闹别扭（annoyed，表情也换成生气的）
    public static func poked(mood: PetMood, count: Int, streak: Int = 1) -> (line: String, annoyed: Bool)? {
        if mood.pouts, streak >= annoyedAfter {
            let lines = [tr("哼，不理你了", "Hmph. Not talking to you"), tr("戳够了没有！", "Are you done poking?!"),
                         tr("再戳我真的生气了！", "One more and I'm really mad!")]
            return (lines[(streak - annoyedAfter) % lines.count], true)
        }
        let lines: [String]
        switch mood {
        case .energetic, .normal, .revived:
            lines = [tr("在呢在呢！", "Right here!"), tr("嘿嘿，戳我干嘛～", "Hehe, what's the poke for~"),
                     tr("有什么要我盯着的吗？", "Anything you want me to watch?"), tr("再戳要痒了～", "That tickles~")]
        case .resting:
            lines = [tr("嗯？我没睡着哦", "Hm? I wasn't asleep"), tr("啊，你回来啦", "Oh, you're back"),
                     tr("醒着呢，就是歇一会儿", "Awake, just taking a breather")]
        case .nervous:
            lines = [tr("啊！吓我一跳", "Ah! You startled me"), tr("别戳啦，正慌着呢！", "Not now, I'm panicking!"),
                     tr("慢一点我就不慌了", "Slow down and I'll calm down")]
        case .tired:
            lines = [tr("别戳啦，我在冒汗…", "No poking, I'm sweating here…"), tr("唔…让我喘口气", "Mm… let me catch my breath"),
                     tr("省着点用，我就不累了", "Go easy and I won't be so tired")]
        case .exhausted:
            lines = [tr("呜…别戳了", "Waah… stop poking"), tr("快没了快没了！", "Almost gone, almost gone!"),
                     tr("再戳也变不出额度呀…", "Poking won't make more quota…")]
        case .sleeping:
            lines = [tr("唔…再睡一会儿…", "Mm… five more minutes…"), tr("zzz…别吵…", "zzz… shh…"), tr("（翻了个身）", "(rolls over)")]
        case .confused:
            lines = [tr("我也不知道怎么回事…", "I don't know what's going on either…"),
                     tr("戳我也没用呀，找不到数据", "Poking won't help, there's no data")]
        case .loading:
            return nil
        }
        return (lines[abs(count - 1) % lines.count], false)
    }

    /// 现在是什么情况、她说哪一句
    public static func say(_ snapshot: UsageSnapshot?, mood: PetMood, now: Date, options: Options = Options(),
                           calendar: Calendar = .current) -> (situation: Situation, line: String) {
        let found = lines(snapshot, mood: mood, now: now, options: options, calendar: calendar)
        return (found.situation, found.lines[abs(options.pick) % found.lines.count])
    }

    /// 现在是什么情况、这种情况下轮着说的几句（至少一句）。
    /// mood 只用来认「还没算出来」和「读不到数据」（出错了、还没有快照时也是疑惑），别的都按快照算
    static func lines(_ snapshot: UsageSnapshot?, mood: PetMood, now: Date, options: Options = Options(),
                      calendar: Calendar = .current) -> (situation: Situation, lines: [String]) {
        if mood == .loading { return (.loading, [mood.line]) }
        guard mood != .confused, let snapshot, let trend = PetTrend(snapshot, now: now, recoveredAt: options.recoveredAt) else {
            return (.confused, [PetMood.confused.line, tr("咦，读数去哪了？", "Huh, where did the readings go?")])
        }
        let top = trend.top, level = trend.level
        let left = max(1, Int((100 - top.clampedPercent).rounded()))
        func clock(_ date: Date) -> String { Fmt.clock(date, now: now, calendar: calendar) }
        func wait(_ date: Date) -> String { Fmt.duration(date.timeIntervalSince(now)) }
        /// 最紧张的窗口在这么久以内重置的话，是什么时候
        func reset(within limit: TimeInterval) -> Date? {
            top.resetsAt.flatMap { $0 > now && $0.timeIntervalSince(now) <= limit ? $0 : nil }
        }

        if level == .sleeping {
            // 和菜单栏的倒计时一样，等最晚恢复的那个；不知道什么时候恢复就不说时间
            guard let last = snapshot.lastToRecover, let back = last.resetsAt, back > now else { return (.usedUp, [level.line]) }
            return (.usedUp, [
                last.duration == week
                    ? tr("这周的用完了，\(clock(back)) 见 zzz", "This week's quota is gone until \(clock(back)) zzz")
                    : tr("额度用完啦，\(clock(back)) 见 zzz", "All used up until \(clock(back)) zzz"),
                tr("先睡一会儿，\(wait(back))后叫我…", "Napping… wake me in \(wait(back))"),
            ])
        }

        if trend.recovered {
            return (.recovered, [
                PetMood.revived.line,
                tr("额度回来啦，开工！", "Quota's back, let's go!"),
                tr("睡饱了，继续吧～", "Well rested. Let's keep going~"),
            ])
        }

        if let soon = trend.soon {
            return (.runningOut, [
                tr("照这样 \(clock(soon.at)) 就见底了，慢一点！", "At this rate we're out by \(clock(soon.at)). Slow down!"),
                tr("只够再撑 \(wait(soon.at))了…", "Only about \(wait(soon.at)) left at this rate…"),
                tr("要不要歇一会儿？\(clock(soon.at)) 就没了", "Take a break? It's gone by \(clock(soon.at))"),
            ])
        }

        if level == .exhausted {
            var lines = [tr("只剩 \(left)% 了，挑要紧的做！", "Only \(left)% left. Pick what matters!"), level.line]
            if let back = reset(within: 40 * 60) {
                lines.append(tr("再撑 \(wait(back))就恢复了！", "Hang on, it resets in \(wait(back))!"))
            }
            return (.almostOut, lines)
        }

        // 已经用到七成半、在冒汗了，就不另外说烧得快
        if level != .tired, let fast = trend.fast, let burn = fast.window.burnPerHour {
            var lines = [
                tr("今天好拼啊，一小时烧了 \(Int(burn.rounded()))%…", "Going hard today: \(Int(burn.rounded()))% an hour…"),
                PetMood.nervous.line,
            ]
            if let back = fast.window.resetsAt {
                lines.insert(tr("这个速度撑不到 \(clock(back)) 重置哦", "At this speed we won't make it to the \(clock(back)) reset"), at: 1)
            }
            return (.burningFast, lines)
        }

        if level == .tired {
            let tens = Int(top.percent / 10)  // 7 或 8
            var lines = [
                level.line,
                tr("用了\(tens == 7 ? "七" : "八")成多，还剩 \(left)%", "Over \(tens)0% used, \(left)% left"),
            ]
            if let back = reset(within: 3600) {
                lines.append(tr("还有 \(wait(back))就重置，放心用吧", "It resets in \(wait(back)), so go ahead"))
            }
            return (.tired, lines)
        }

        // 往下都是不紧张的时候（75% 以下）
        let paces = snapshot.windows.compactMap { window in window.pace(now: now).map { (window: window, pace: $0) } }
        if let far = paces.max(by: { abs($0.pace.ahead) < abs($1.pace.ahead) }), abs(far.pace.ahead) >= paceGap {
            let points = Int(abs(far.pace.ahead).rounded())
            let period = far.window.duration == week ? tr("这周", "this week") : tr("最近", "lately")
            guard far.pace.ahead > 0 else {
                return (.pace, [
                    tr("\(period)省了 \(points) 个点，可以放开用～", "\(plural(points, "point")) under pace \(period), go for it~"),
                    tr("节奏很稳，比平均还少用 \(points) 个点", "Nice and steady: \(plural(points, "point")) under an even pace"),
                ])
            }
            var lines = [tr("\(period)用得有点猛，比平均多 \(points) 个点", "Going hard \(period): \(plural(points, "point")) over an even pace")]
            // 说「够用到周二」要重置就在这几天，不然不知道是哪个周二
            if let perDay = far.pace.perDay, let back = far.window.resetsAt, back.timeIntervalSince(now) <= week {
                let day = Fmt.weekday(back, calendar: calendar)
                lines.append(tr("之后每天约 \(Int(perDay.rounded()))% 才够用到\(day)",
                                "About \(Int(perDay.rounded()))% a day will last until \(day)"))
            }
            return (.pace, lines)
        }

        if let window = trend.elsewhere {
            let other = Int(window.otherPercent.rounded())
            return (.elsewhere, [
                tr("你在别处也在聊天吧？那边用了 \(other)%", "Chatting somewhere else too? That's \(other)% so far"),
                tr("网页和手机上用的，我也算进来了", "I'm counting what you use on web and mobile too"),
            ])
        }

        if trend.idle {
            return (.idle, [PetMood.resting.line, tr("好安静…我先发会儿呆", "So quiet… I'll just zone out for a bit")])
        }
        if options.lateNight, let quiet = trend.quiet, quiet <= activeWithin, lateHours.contains(calendar.component(.hour, from: now)) {
            return (.lateNight, [
                tr("这么晚还在忙？早点休息呀", "Still up this late? Get some rest soon"),
                tr("夜深了，我陪你再撑一会儿", "It's late. I'll stay up with you a little longer"),
            ])
        }

        let used = Int(top.clampedPercent.rounded())
        if level == .energetic {
            // 一点都没用时不说「才用了 0%」
            let amount = used >= 1 ? [tr("才用了 \(used)%，随便造～", "Only \(used)% used. Go wild~")] : []
            return (.ordinary, [level.line] + amount + [tr("状态满分！", "Feeling great!")])
        }
        return (.ordinary, [
            level.line,
            tr("过半啦，还剩 \(left)%", "Past halfway, \(left)% left"),
            tr("节奏不错，继续～", "Good rhythm, keep going~"),
        ])
    }

    private static let week: TimeInterval = 7 * 86400
}
