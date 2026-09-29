import Foundation

/// 第一次启动时的判断（AppDelegate 用，放在这里是为了能进自检）
public enum FirstLaunch {
    /// 启动过一次就存上（演示模式不存）
    public static let launchedKey = "launchedBefore"
    /// 第一次启动时存上，等在「应用程序」文件夹里打开时再开开机自启、清掉。
    /// 下载版常常第一次是在「下载」里打开的，macOS 会把它挪到临时目录运行，那时注册的开机自启指向临时路径，用不了
    public static let loginItemPendingKey = "loginItemPending"

    /// 设置里还没有 App 自己存的东西。NS 开头的是 AppKit 自己记的（比如演示模式留下的菜单栏图标位置），不算；
    /// 老版本升级上来的用户没有 launchedKey，但存过设置或提醒记录，不算第一次
    public static func isFirst(storedKeys: [String]) -> Bool {
        storedKeys.allSatisfy { $0.hasPrefix("NS") }
    }

    /// 在 /Applications 或 ~/Applications 里运行。被 macOS 挪到临时目录运行（App Translocation）时不算
    public static func isInApplicationsFolder(_ bundlePath: String) -> Bool {
        bundlePath.contains("/Applications/") && !bundlePath.contains("/AppTranslocation/")
    }
}
