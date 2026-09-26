# QuotaPet 额度宠物

住在 macOS 菜单栏里的像素风二次元小人（橙色长发、别着星芒花饰），实时显示 Claude 的额度：额度越紧张，她越累；用完了就睡着，并显示恢复倒计时。
本机用过 Codex 的话，Codex 的额度也会一起显示，由另一只宠物（白发龙娘）看着。

截图和功能总览见[仓库首页](../README.md)，产品规划见 [docs/PRODUCT_PLAN.md](../docs/PRODUCT_PLAN.md)。

## 快速开始

需要 macOS 14+ 和 Swift 6。装了命令行工具（`xcode-select --install`）就够，不需要 Xcode。

```bash
make run        # 打包成 build/QuotaPet.app 并启动
make demo       # 演示模式：假数据，75 秒看完宠物的所有状态
make install    # 装到 ~/Applications 并开机自启：以后一打开 Claude，宠物就出现
make dump       # 在终端打印当前额度推算，和 usage_lab.py 对账
make check      # 跑自检
make previews   # 把宠物、菜单栏、面板渲染成 PNG，放到 build/previews（面板、设置页中英各一套）
```

第一次启动时，macOS 会问要不要允许「额度宠物」发通知，选允许才能收到用量提醒。

## 怎么用

- 默认**跟着 Claude 桌面端走**：打开 Claude 宠物就出现，关掉 Claude 就藏起来（后台照常发额度恢复提醒）。
  设置里可以改成「一直显示」。宠物藏着的时候想看额度，在 Spotlight 里再打开一次 QuotaPet 就会弹出面板。
- 要跟着 Claude 自动出现，QuotaPet 得开机自启（`make install` 会打开）。想关掉：QuotaPet 设置 → 通用，或者「系统设置 → 通用 → 登录项」。
- **左键**点宠物弹出面板，**右键**是刷新、设置、退出。
- 菜单栏显示 5 小时额度（可以在设置里改成「5h + 周」或「最紧张的窗口」）；75% 以上数字变橙，90% 以上变红。
- 宠物心情跟着最紧张的那个窗口走：< 50% 元气满满 → 50% 状态不错 → 75% 有点累 → 90% 快撑不住 → 100% 睡着。
- 被限流时菜单栏改显示恢复倒计时，比如 `1h23m`；额度恢复时会提醒。
- **同时用 Codex**（命令行或桌面端）时自动接进来：面板顶部有 Claude / Codex 切换条，每次点开先看更紧张的那家；宠物和菜单栏数字跟着两家里更紧张的那个，数字前面加一个小图标（星号是 Claude，终端是 Codex）。Codex 的宠物固定是龙娘，Claude 的形象在设置里选。
  「Claude 打开时出现」这时也看 Codex 桌面端。
- 界面有简体中文和英文，默认跟随系统语言（系统语言不是这两种时用英文），可以在设置 → 通用 → 语言里改。

设置页（右键 → 设置…）里能改：

| 分组 | 设置项 |
|---|---|
| 菜单栏 | 什么时候出现（Claude 打开时，在用 Codex 时也看 Codex / 一直显示）、宠物旁边显示什么、Claude 的宠物形象（Codex 固定是龙娘）、宠物动画、单色宠物 |
| 提醒 | 用量提醒和阈值（50 / 75 / 90 / 100%，默认 75 / 90 / 100）、额度恢复时提醒 |
| 实时估算 | 用本机日志实时估算、自动学习换算率（能看到当前学到的值）、手动指定每周重置时间 |
| 通用 | 语言（跟随系统 / 简体中文 / English）、开机自动启动 |

## 菜单栏里看不到宠物？

刘海屏 MacBook 的菜单栏图标一多，放不下的会被藏到刘海后面，而且系统默认把新图标放在最左边，最先被挡住。
QuotaPet 第一次启动时会把自己放到最右边、紧挨着时钟，所以一般能看到，代价是别的 App 可能被挤到刘海后面。解决办法：

- 按住 ⌘ 拖动菜单栏图标，可以调整顺序（系统会记住位置）；
- 在「系统设置 → 菜单栏」里关掉不常用 App 的菜单栏图标；
- 在 QuotaPet 设置里把菜单栏显示改成「仅宠物」，能省下一半宽度。

## 数据从哪来（不联网、不读登录凭据）

| 数据 | 来源 |
|---|---|
| 官方 5 小时 / 每周 % | Claude 桌面端运行时每 15 分钟写一次的 `~/Library/Application Support/Claude/plan-usage-history.json` |
| 两次官方读数之间的变化 | `~/.claude/projects/**/*.jsonl` 里 Claude Code 每个请求的 token，按 API 价格折算，再用自动学到的换算率换成百分比 |
| 重置时间 | 推算：窗口从上一个窗口结束后的第一次使用开始计时，读数明显下跌的地方视为重置；Claude Code 被限流时，用日志里服务器给的精确恢复时间 |
| Codex 的 % 和重置时间 | Codex 每轮对话结束时写进 `~/.codex/sessions/**/*.jsonl`（归档的在 `archived_sessions/`）的 `rate_limits`：服务器给的已用百分比、窗口长度和重置时间，不用估算 |

几点说明：

- **换算率自动学习**：「多少美元的 API 用量 ≈ 1% 额度」，所有模型用同一个数。实测额度和 API 价格大致成正比；思考程度（effort）不用单独算，它的影响已经体现在思考 token 里，而思考 token 按输出计费；唯一的例外是缓存读，在额度里只算一半左右（回归细节见产品规划第 7 节）。App 从持续记录里自动学这个数，越近的记录权重越大（半衰期 3 小时），起始值是 $0.27。设置页能看到当前学到的值。
- **持续记录**：每 15 分钟一段（官方涨了多少、本机按「模型/思考程度」花了多少）存在 `~/Library/Application Support/QuotaPet/intervals.jsonl`，一行一条 JSON，只追加。Claude Code 清理旧日志也不影响。以后数据多了，可以直接用它重新做回归。
- **只有官方读数或限流消息能宣布「用完了」**：官方读数没到 100% 之前，估算值最多显示 99%，免得宠物误睡、误发提醒。Claude Code 被限流时会在日志里记下服务器的回复（哪个额度用完、几点恢复），QuotaPet 读到就马上显示用完，倒计时也按这个时间算。
- 需要 Claude 桌面端在运行，官方读数是它记录的；桌面端没开时只能靠本机估算，面板里会提示。
- 网页端和手机端的用量不在本机日志里，要等下一次官方读数（最多 15 分钟）才会体现。读数到了以后，官方增量里本机日志解释不了的部分算作「其他端」用量：面板会标出每个窗口里其他端用了多少，消耗速度和「几点用完」也会算上它。
- 重置时间是推算的，每周重置时间不准的话，可以在设置里手动指定。
- **Codex**：只看 Codex 的总额度（`limit_id` 是 `codex` 的那组；个别模型单独的额度不显示）。读数只在本机用 Codex 时更新，网页或云端任务的用量要等下次在本机用时才看得到，读数超过 12 小时没更新时面板会提示。读数之后窗口已经过了重置时间的，算 0%、等下次使用再开始计时。日志可能有几百 MB，第一次只从最近的文件往前读到最新读数的前一天，之后每个文件只读新追加的部分。只读对话日志里的额度字段，不碰 `~/.codex/auth.json` 等登录凭据。

## 代码结构

```
Sources/
  QuotaPetCore/                 纯逻辑，不依赖 AppKit
    Models.swift                UsageProvider 协议、UsageWindow、UsageSnapshot
    Localization.swift          界面语言，tr("中文", "English")
    Formatting.swift            时间格式（跟着界面语言）、菜单栏文字
    Claude/
      ClaudeDesktopHistory      解析桌面端的官方读数
      ClaudeTranscripts         增量读取 Claude Code 日志（规则同 usage_lab.py）
      ClaudePricing             API 价格和起始换算率
      WindowInference           推算窗口开始 / 重置时间
      UsageIntervals            切出每 15 分钟的区间，持续记录到本机
      RateLearner               从记录里学换算率
      ClaudeProvider            把以上组合成一个快照
    Codex/
      CodexLogs                 增量读取 Codex 对话日志里的额度读数
      CodexProvider             把读数组合成快照（窗口、消耗速度）
    Pet/                        宠物心情和形象；PetArt.swift 是像素数据（由 design/ 导出，别手改）
    DemoProvider.swift          演示数据（Claude 和 Codex）
  QuotaPet/                     菜单栏 App
    StatusItemController        菜单栏上的宠物、文字和弹出面板
    MenuBarIcon                 菜单栏上的图：宠物头像 + 几家同时显示时的小图标
    AppWatcher                  盯着 Claude / Codex 桌面端有没有开
    UsageStore                  几家数据源一起算；FSEvents + 每分钟兜底的刷新调度
    NotificationManager         阈值提醒、恢复提醒
    Pet/                        动画播放、像素画渲染
    Views/                      SwiftUI 面板和设置页
    Tools/                      --dump、--render-previews、--render-icon
  QuotaPetChecks/               自检（命令行工具里没有 XCTest，用可执行文件代替）
```

## 改宠物形象

宠物的原型在 `design/` 里用 Python 画：头发、衣服用形状画再转成像素，眼睛手工逐格画（小眼睛用形状转像素会出杂点）。
脚本要用 Pillow 和 NumPy（`pip3 install pillow numpy`），出的图放在 `design/out/`，不进 git。

```bash
python3 design/pet_pixel.py     # 出预览图 → design/out/pixel-mid.png
python3 design/pet_pixel.py styles  # 各款形象并排 → design/out/styles.png
python3 design/export_swift.py  # 满意了，导出到 Sources/QuotaPetCore/Pet/PetArt.swift
make install
```

形象都在 `design/chibi4.py` 的 `STYLES` 里。龙娘（`dragon`）是 Codex 专用的，不在 Claude 的形象选项里（`PetStyle.claudeChoices`）；它的角、翅膀、尖耳在形状里画，中国结太小，是缩成像素后手画盖上去的（`KNOTS`）。

## 接入别的 AI

实现一个 `UsageProvider`，返回若干个 `UsageWindow` 就行，宠物、菜单栏、通知都是通用的。Codex 就是这么接进来的，可以照着 `QuotaPetCore/Codex/CodexProvider.swift` 写：

```swift
final class CursorProvider: UsageProvider, @unchecked Sendable {
    let id = ProviderID.cursor            // 先在 ProviderID 里加一个 case 和显示名
    let pollInterval: TimeInterval = 60
    var watchPaths: [String] { … }        // 相关文件一变就刷新
    func isRelevantChange(path: String) -> Bool { path.hasSuffix(".jsonl") }
    func snapshot(now: Date) throws -> UsageSnapshot { … }
}
```

然后在 `AppDelegate` 里把它加进数据源列表，在 `MenuBarIcon.glyph(for:)` 给它挑一个小图标，想让它有自己的宠物就在 `PetStyle.of` 里指定形象。没有数据的数据源不会出现在面板和菜单栏上。
