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

    /// 开关了一次开机自启之后，能不能清掉 loginItemPendingKey（不再等到「应用程序」文件夹里再替用户打开）：
    /// 关掉成功了（用户不要）；打开成功了、又是在「应用程序」里运行的（在「下载」或临时目录里注册的路径之后用不了）。失败了都留着
    public static func clearsLoginItemPending(enabling: Bool, succeeded: Bool, bundlePath: String) -> Bool {
        succeeded && (!enabling || isInApplicationsFolder(bundlePath))
    }

    /// 同时有几个 QuotaPet 在运行时留哪一个：最早启动的（同时启动的按 pid）。pid 会循环使用，不能只比 pid。
    /// 每个实例都按同样的规则挑，所以两个同时打开时只会留下一个，不会两个都退出
    public static func launchedEarlier(_ a: (launched: Date?, pid: Int32), than b: (launched: Date?, pid: Int32)) -> Bool {
        let ta = a.launched ?? .distantFuture, tb = b.launched ?? .distantFuture
        return ta != tb ? ta < tb : a.pid < b.pid
    }
}
