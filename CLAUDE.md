# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 环境

- 本机只有 Command Line Tools，**没有 Xcode**：不要用 `xcodebuild`、iOS 模拟器，也没有 XCTest / swift-testing。
- Swift 命令都在 `QuotaPet/` 目录下跑。工具链是 Swift 6，但 `Package.swift` 里的语言模式是 v5。

## 常用命令（在 `QuotaPet/` 下）

```bash
make check      # = swift run QuotaPetChecks，唯一的测试
swift build     # 只编译
make previews   # 把宠物、菜单栏、面板渲染成 PNG 到 build/previews（面板、设置页中英各一套；精绘形象另有 popover-<形象>）；改界面后用它验证，不用启动 App
make dump       # 在终端打印当前额度推算（读真实数据）
make run / make demo / make install
make release    # Apple 芯片 + Intel 通用版 zip（build/QuotaPet-<版本>.zip），版本号取 Resources/Info.plist
```

- 自检是 `Sources/QuotaPetChecks/main.swift` 里的一串顶层 `check(...)`，按 `// MARK:` 分组，**不能单独跑某一项**，失败时会打印行号。它用了 `@testable import`，只能 debug 构建，不要加 `-c release`。
- 仓库根目录下的 `usage_lab.py` 是做 App 之前的实验工具，只用标准库：`python3 usage_lab.py summary|snap|ratio|calibrate|backtest`。

## 架构

数据流：`UsageProvider`（`QuotaPetCore/Models.swift`）→ `UsageStore`（FSEvents 触发，另外每分钟兜底刷新，几家数据源在同一个后台串行队列上依次算快照）→ 菜单栏、面板、`NotificationManager`。宠物、菜单栏、通知只认 `UsageSnapshot`，不关心是哪家 AI；接入新的 AI 就实现一个 `UsageProvider`（例子见 `QuotaPet/README.md`）。

- 现在有 Claude（`ClaudeProvider`）和 Codex（`CodexProvider`）两家。`UsageSnapshot.visible` 决定显示哪几家：Claude 一直在，别的有数据、用户又没在设置里关掉（`AppSettings.hiddenProviders`）才出现，所以没用过 Codex 时界面和只有 Claude 时一样。关掉的那家不显示、不发提醒（提醒的记录照常更新，重新打开时不会补发一堆）。
  - 设置页按「通用 / Claude / Codex」分页（`SettingsView.Page`），本机有 Codex 的记录时才有 Codex 页（和「显示」开关无关，不然关掉后就打不开了）。`UsageSnapshot.focus` 是宠物和菜单栏跟着的那家（最紧张的，一样时 Claude 优先）。
  - 面板不止一家时顶部有切换条（`ProviderTabs`），每次打开先选 focus 那家；看的是 focus 时面板和菜单栏共用一个 `PetAnimator`，切到另一家时换成 `headerAnimator`。
  - 菜单栏不止一家时，数字前面加一个 SF Symbol 小图标（`MenuBarIcon`：星号是 Claude，终端是 Codex），和宠物画在同一张图里。
  - `@Published` 在赋值前就通知，`StatusItemController` 的订阅里要用传进来的新值，不能去读 `store` 的属性。
- 提醒的判断和措辞在 `QuotaPetCore/UsageAlerts.swift`（能进自检），`NotificationManager` 只发通知、把每个窗口的记录（`last`、`notified`、`warned`、`cycleEnd`）存进 UserDefaults。每个窗口每个周期，每个阈值和「快用完」各只提醒一次；用量掉到 5% 以下，或者重置时间往后跳了半个窗口以上，算新周期。「快用完」= `projectedExhaustion` 落在 `warningLead` 以内（5 小时窗口半小时，一天以上的窗口一天），归在「用量提醒」总开关下面；和阈值提醒同时发生时并成一条。
- 宠物在面板上说的话在 `QuotaPetCore/Pet/PetTalk.swift`（能进自检）：按实际情况挑（`Situation`，从上到下就是优先级：用完了、刚恢复、眼看要用完、烧得快、每周节奏、别处在用、闲着、深夜…），同一种情况有几句，面板每打开一次换一句（`PopoverState.nextTalk`）。通知里的话还是 `PetMood.line`。
  - 心情 = 档位 + 趋势（`PetMood.from(snapshot:now:recoveredAt:)`，规则在 `PetTrend.mood`）：快用完了先哭、5 小时额度烧得快先慌（`nervous`，已经用到七成半就还是累）、刚恢复开心一阵（`revived`）、不紧张又半小时没用就歇着（`resting`）。趋势和台词看的是同一份 `PetTrend`，表情和台词对得上（自检会查）。`PetMood.from(percent:)` 只看档位。
  - **不变量**：只有档位能让她睡着（100% 只能来自官方读数或限流消息），趋势再急也只到「快撑不住」。
  - 加心情：`PetMood` 加 case，像素和精绘的帧（`PetSprites`）、标题、颜色（`Level.mood`）都要补；没开动画时停在第一帧，第一帧要能代表这个心情。
  - 「刚恢复」要知道上一次的读数：`UsageStore.recoveredAt` 在刷新时记（只在内存里），标准和「额度恢复」提醒一样（`UsageAlerts.recovered`）；之后 10 分钟内、恢复的窗口还没用到 20% 才算。「这么晚还在忙」一晚只说一次，面板说了哪种情况会回调 `PopoverState.said`。
  - 点面板里的宠物（`OverviewView` 的 `onPoke`）：`PetAnimator.react()` 把 `PetSprites.reaction(for:style:)` 播一遍再回到原来的动画（没开动画也播），她说一句 `PetTalk.poked`（3 秒），然后换成这种情况的下一句。上一句还没说完又戳算连戳，心情好的时候（`PetMood.pouts`）连戳到第 5 下开始闹别扭：表情换成 `pout`，说生气的话。看的是 focus 那家时菜单栏上的宠物是同一个 `PetAnimator`，会跟着一起动。反应的第一帧要和这个心情平时的第一帧不一样（自检会查）。
  - 加台词或加情况：中英都要写；自检「宠物说的话」一节每种情况都要试到（有一条检查会数），试过的输入会在「多语言」一节再查一遍英文。
- 消耗速度按 `UsageWindow.burnUnit` 说：一天以上的窗口按天（每天 20%），5 小时窗口按小时；`projectedExhaustion` 的门槛也是每个单位 1%。
- `UsageWindow.pace`：一天以上的窗口（每周额度等）和平均节奏比，画成面板进度条上的刻度和下面那行「比平均节奏多用 N 个点 · 之后每天可用约 X%」。5 小时窗口从第一次使用才开始计时，不看节奏；Claude 每周额度还没看到过重置时（`scheduleKnown` 为 false，重置时间是按第一次使用猜的）也不看。

- `QuotaPetCore` 是纯逻辑，不能依赖 AppKit，这样自检才跑得起来。界面代码都在 `QuotaPet` target 里。
- `ClaudeProvider.snapshot` 的算法：当前 % = 最近一次官方读数（桌面端每 15 分钟写一次 `plan-usage-history.json`）+ 读数之后本机日志里请求的额度加权花费（API 价格，但缓存读按半价）÷ 换算率。
  - 换算率由 `RateLearner` 从 `IntervalArchive` 学出来（`~/Library/Application Support/QuotaPet/intervals.jsonl`，只追加，半衰期 3 小时），起始值 $0.27 / 1%。
  - 窗口的开始和重置时间由 `WindowInference` 推算：5 小时窗口从第一次使用开始；每周额度按固定时间重置（`fixedCadence`），看到过一次重置（读数掉了至少 3 个点，或限流消息）后就按它每 7 天循环，多次跳变取交集收窄时间、取最晚的时刻。用户手动指定了每周重置时间时，按它往后每 7 天算一次。
  - Claude Code 被限流时会在日志里写一条 synthetic 消息，带 `quotaLimits`（`rateLimitType`、秒级 `resetsAt`）。扫描器把它记成 `ClaudeLimitEvent`：没到恢复时间前这个窗口直接算用完，重置时间以它为准。
  - 其他端（网页、手机、桌面端聊天）用量由 `OtherUsage` 算：相邻两次官方读数之间，官方增量比本机估算多出门槛以上的部分。`RateLearner` 学换算率时也用同一个门槛，跳过这种混用的区间。
  - **不变量**：官方读数没到 100 时，估算值最多 99%。只有官方读数或限流消息能宣布「用完了」，免得宠物误睡、误发提醒。
- `CodexProvider`：Codex（命令行和桌面端）每轮对话结束时把服务器给的额度写进 `~/.codex/sessions/**/*.jsonl`（归档的在 `archived_sessions/`）的 `token_count` 事件（`payload.rate_limits`：`primary` / `secondary` 各有 `used_percent`、`window_minutes`、秒级 `resets_at`；老版本是 `resets_in_seconds`）。
  - 读数就是官方百分比，不用估算；只看总额度（`limit_id` 是 `codex` 或没有），个别模型单独的额度桶不显示。300 分钟和 10080 分钟的窗口用和 Claude 一样的 id（`five_hour`、`seven_day`），菜单栏的「5 小时」「5h + 周」对两家都管用；某家没有这种窗口时退回最紧张的窗口。
  - 最近一次读数之后已经过了重置时间的窗口算 0%、没有重置时间（等下次使用）。消耗速度用同一个窗口里的历次读数算，回看时长和 Claude 一样（5 小时窗口 30 分钟，其他 24 小时）。
  - 日志可能有几百 MB：`CodexLogScanner` 第一次从最近改过的文件往前读，比最新读数早 25 小时以上的文件只从末尾往后跟。两家的扫描器都用 `LineCursor` 增量读：分块读、每块包在 `autoreleasepool` 里，不然第一次扫描时内存会涨几百 MB。
  - `UsageStore` 按数据源分开刷新：文件变了只重算那一家（`providersAffected`），每分钟兜底全部重算，也顺便给启动后才出现的目录补上监听。
  - 只解析带 `rate_limits` 的行，只取时间和额度字段；`~/.codex` 下别的文件（`auth.json` 登录凭据、数据库）都不碰。
- **和 `usage_lab.py` 要保持一致的地方**，改一边就要改另一边（只涉及 Claude；Codex 不用估算，usage_lab 里没有它）：
  - `ClaudePricing.currentPrice` 对应 `PRICES`（各族当前这一代），`olderPrices` 对应 `OLDER_PRICES`（同一族里价格不一样的老版本），`cacheReadQuotaWeight` 对应 `CACHE_READ_WEIGHT`，`ClaudeRates.starting` 对应 `STARTING`，`OtherUsage.threshold` 对应 `OTHER_THRESHOLD`
  - `ModelFamily.of` 对应 `family()`：按模型名里的子串匹配（Mythos 算 Fable），名字里不含 fable、mythos、opus、sonnet、haiku 的新模型族不会计价，要加 case 和价格
  - `ClaudePricing.version` / `price(model:family:)` 对应 `version()` / `price()`：每个请求按模型名里的版本号定价（`claude-opus-5` 按 Opus 5 的价格，不是 Opus 5.5 的）。出了新一代、价格变了时，把旧的当前价挪进老版本表，再改当前价
  - `ClaudeTranscripts` 的解析规则：按 `message.id` 去重、同一个响应的各字段取最大值、跳过 synthetic 和写到一半的行（限流消息只有 App 读，usage_lab 不需要）
- 改换算相关的逻辑之前，先看 `docs/PRODUCT_PLAN.md` 第 7 节的回归结论：所有模型用一个系数，思考程度（effort）不单独算，缓存读按半价。改完用 `python3 usage_lab.py backtest` 回测，和改之前比一比。
- 宠物有两种画法，`PetFrame` 里的图是 `PetPicture`：像素画（`PixelGrid`）或精绘（`PaintedPicture`）。`PetStyle.art` / `isPainted` 区分。现在经典、龙娘、墨镜是精绘，其余五款是像素画（计划全部换成精绘，换完再删像素画和「单色宠物」）。
- `QuotaPetCore/Pet/PetArt.swift` 是 `design/export_swift.py` 生成的，**不要手改**。改像素宠物的流程：改 `design/pet_pixel.py` → 运行它出预览图 → 运行 `export_swift.py` 导出（要装 Pillow 和 NumPy）。
  - 可选的形象（经典、猫耳、青春、魔女）在 `design/chibi4.py` 的 `STYLES` 里：可以换发型、饰品、配色、眼睛（`pet_pixel.EYE_SETS`）、嘴和腮红，`SsPW` 的颜色不能改（单色模式靠它们挖空脸）。标了 `draft` 的是设计稿，不导出。加一款要同时在 `PetSprites.swift` 的 `PetStyle` 里加 case。`python3 design/pet_pixel.py styles` 会把各款并排出一张对比图。
  - 每款形象各带一张调色板（`PetPalette`，挂在 `PixelGrid.palette` 上）：导出时不再给改了颜色的字符换字符，同一个字符在不同形象里是不同的颜色，形象再多也不会不够用。
  - 两家各有一组形象，互不重叠：Claude 是 `PetStyle.claudeChoices`（经典、猫耳、青春、魔女、墨镜 `shades`），Codex 是 `codexChoices`（龙娘 `dragon`、汉服 `hanfu`、极客 `geek`）。`PetStyle.of(_:claudeStyle:codexStyle:)` 决定每家用哪个，存的形象不在那组里就用那组第一款。加一款时要放进其中一组。
  - 新部件的开关都在 `STYLES` 里：`accessory`（`horns` 龙角，形状在 `HORN`，画在头发上、自己带描边 / `hairpin` 步摇 / `headphones` 耳机）、`knot`（鬓角的中国结）、`buns`（丸子头）、`collar`（`knot` 立领 / `cross` 交领 / `hoodie` 连帽衫）、`wings`（小龙翼，现在没有款式用）、`elf`（尖耳）。中国结、盘扣太小，用形状画会糊成一团，是在 `decorate` 里缩成像素之后手画盖上去的（`KNOTS`、`BUTTONS`）。
- 精绘形象（经典 `classic`、龙娘 `dragon`、墨镜 `shades`）：GPT 出图，`design/painted/export_painted.py` 按 `design/painted/<形象>.json` 切成 `Resources/Pets/<形象>/{portrait,icon}-<表情>.png`（192 / 44 像素的 2 倍图，面板 96pt、菜单栏 22pt，像素款的菜单栏头像是 16pt），同时生成 `QuotaPetCore/Pet/PaintedArt.swift`（**不要手改**）。流程见 `QuotaPet/README.md`「精绘形象」。
  - 流水线：`make_pack.py <形象>`（按配置里的 `character` 生成提示词和参考图）→ 用户在 GPT 里出底图和 9 个表情 → `pipeline.py <形象>`（检查原图、自动定位并写进配置、导出）→ 把 `PetStyle.art` 改成 `.painted`。配置里已有的位置不会被覆盖（`--relocate` 才重新定位）。经典、龙娘的像素画还留在 `PetArt.swift` 和 `chibi4.py` 里，App 不用了，只给出图包当参考图 1。
  - 原图在 `anime-sheet/精绘出图/<形象>/GPT出图/`，出图包（`提示词.md`、参考图）在它的上一级；只有墨镜在旧位置 `anime-sheet/精绘出图/GPT出图/`。`anime-sheet/` 是本机的素材文件夹，只写在 `.git/info/exclude` 里，里面的东西不能挪进会被跟踪的地方。
  - App 图标用经典款：配置里写了 `appIcon` 的那款，导出时另外生成 1024 像素的 `Resources/AppIcon.png`，`IconRenderer` 画大图标时用，`build-app.sh` 不把它拷进 App 包。
  - 表情图先对齐到底图，只取脸的椭圆盖上去，头发、衣服各表情一样；脸以外的小块（太阳穴的汗珠）用配置里的 `patches` 从一张复制到几张（`tired-wavy` 的汗珠复制到 `closed-wavy` 和 `nervous`）。
  - 每款 14 张表情图（`export_painted.FACES`，第一张是底图）。后补的四张：`drowsy` 迷糊（刚启动、睡着或歇着时被戳）、`nervous` 紧张（「有点慌」）、`surprised` 惊讶（被戳）、`pout` 生气（戳烦了）。像素款没有这四张，用现有的眼睛和嘴凑（`PetSprites` 里像素的分支）。
  - 加表情：`FACES` 和 `make_pack.py` 的 `EXPRESSIONS` 一起加，`make_pack.py --prompt <表情…>` 打印提示词。**每一款精绘的图都齐了再跑导出**：`export_painted.py` 每次都会重写 `PaintedArt.swift` 的表情清单，哪款缺图自检就会失败。表情不能改变脸的轮廓（只取脸的椭圆盖到底图上），所以「生气」不能真的鼓脸。
  - 不叠小道具：汗珠、眼泪画在表情里，睡着（`sleep`）、疑惑（`puzzled`）是单独的表情，动画帧是 `PetSprites.paintedFrames`（和像素款帧数不同）。没有单色版：`MenuBarIcon`、`PetRenderer` 遇到精绘一律画彩色，设置页的单色开关下面会说明。
  - 找图（`PaintedArt.root`，在 Core 里，App 和自检共用）：打包后在 `Contents/Resources/Pets`（`build-app.sh` 拷进去）；开发时从可执行文件往上找 `Resources/Pets`。不能用 `#filePath` 或 `Bundle.module`，它们会把本机绝对路径编进发布包。
  - 配置文件名就是 `PetStyle` 的 rawValue，图片尺寸是 `PetSprites.paintedIconPoints` / `portraitPoints` 的 2 倍，自检拿导出的图核对。
- 命令行参数（`--demo`、`--dump`、`--render-previews` 等）都在 `Sources/QuotaPet/main.swift` 里分发。
- 第一次启动（`QuotaPetCore/FirstLaunch.swift`，设置里只有 NS 开头的 AppKit 键才算）时宠物一直显示到退出，并弹出面板；开机自启先挂起（`loginItemPending`），等 App 在「应用程序」文件夹里运行时才打开（下载版第一次常在「下载」里被 macOS 挪到临时目录运行），用户自己开关过就不再管。
- 界面支持简体中文和英文（`QuotaPetCore/Localization.swift`），默认跟随系统，设置 → 通用 → 语言可以改：
  - 每句界面文字都写成 `tr("中文", "English")`，两种语言写在一起；新加或改界面文字时两种都要写。英文里的数量用 `plural(n, "day")` 分单复数。
  - 当前语言在 `L10n.language`，由 `AppSettings.language` 在 willSet 里同步（订阅者要读到新语言）。快照里的窗口名、说明文字是后台按当前语言算的，换语言时 `UsageStore` 会重算，面板用 `.id(settings.language)` 整个重建。
  - 自检开头固定成中文；「多语言」一节查英文，并检查英文里没混进中文。App 本体的文字自检覆盖不到，改了要看 `make previews` 的 `-en` 图。
  - `--dump` 是对账工具，固定输出中文。App 在访达、通知里显示的名字在 `Resources/*.lproj/InfoPlist.strings`。
  - 仓库首页有中英两份：`README.md` 和 `README.en.md`（英文版还收了 `QuotaPet/README.md` 里的用法和设置项）。改了功能、设置项或截图，两份都要改。

## 隐私（仓库是公开的）

- 只读本机文件：不联网，不读任何登录凭据。「用凭据调官方 usage 接口」是刻意不做的。Codex 也一样：只读 `~/.codex` 下对话日志里的额度字段，不读 `~/.codex/auth.json`。
- `make previews` 会额外生成 `popover-live.png` 和 `popover-live-dark.png`，用的是**本机真实额度数据**（Claude 和 Codex），不能复制进 `docs/images/` 或提交；其余预览图都是假数据。
- `make dump` 和 `usage_lab.py` 的输出、`snapshots.jsonl`、`intervals.jsonl` 都是真实数据，不进 git，也不贴进 issue 或 PR。
- `.githooks/pre-commit` 会在提交时拦住 `.jsonl` 文件、截图、`popover-live*`、本机绝对路径和不是 noreply 的邮箱。它是用 `git config core.hooksPath .githooks` 启用的，被拦了就改内容，不要加 `--no-verify` 绕过。
- 发 Release 的包也不能带本机信息：`build-app.sh` 会 `strip -S` 去掉调试符号（里面记着编译时的本机绝对路径和用户名），`make release` 打完包会查一遍 `/Users/`，有就失败。

## 什么时候用哪个技能

| 场景 | 技能 |
|---|---|
| 改完代码要确认能用 | `quotapet-verify`（编译 + 自检 + 渲染预览图并查看） |
| 更新模型价格或加新模型 | `claude-api`（查当前价格），然后同步改 `usage_lab.py` |
| 一个功能写完 | `/simplify`；改动较大就用 `/code-review` |
| push 之前 | `/security-review`：重点看有没有联网、读凭据、真实数据进 git |
