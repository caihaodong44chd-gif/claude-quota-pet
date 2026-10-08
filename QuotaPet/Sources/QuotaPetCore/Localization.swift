import Foundation

/// 界面语言。每句界面文字都用 tr("中文", "English") 写在一起。
/// 加一种语言：这里加 case，tr 加一个参数，编译器会指出每一句要补的翻译。
public enum Language: String, CaseIterable, Identifiable, Sendable {
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }

    /// 语言选项用这门语言自己的写法，切错了也认得出来
    public var nativeName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    /// 跟随系统：按系统的语言顺序挑第一个支持的，规则和 macOS 给 App 选语言一样（繁体中文、日文等都会落到英文）
    public static func preferred(_ languages: [String] = Locale.preferredLanguages) -> Language {
        Bundle.preferredLocalizations(from: allCases.map(\.rawValue), forPreferences: languages)
            .first.flatMap(Language.init(rawValue:)) ?? .en
    }
}

public enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current = Language.preferred()

    /// 当前界面语言，App 启动时和改设置时写入。后台线程算快照（窗口名、说明文字）时也会读，所以加锁
    public static var language: Language {
        get { lock.lock(); defer { lock.unlock() }; return current }
        set { lock.lock(); current = newValue; lock.unlock() }
    }
}

/// 按当前界面语言挑一句，只算用到的那句
public func tr(_ zh: @autoclosure () -> String, _ en: @autoclosure () -> String) -> String {
    switch L10n.language {
    case .zhHans: return zh()
    case .en: return en()
    }
}

/// 英文的单复数：plural(1, "day") = "1 day"，plural(3, "day") = "3 days"。
/// 数字要换个写法时传 shown：plural(1_500, "token", shown: "1.5K") = "1.5K tokens"
public func plural(_ count: Int, _ word: String, shown: String? = nil) -> String {
    "\(shown ?? "\(count)") \(word)\(count == 1 ? "" : "s")"
}
