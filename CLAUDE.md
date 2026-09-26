# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 环境

- 本机只有 Command Line Tools，**没有 Xcode**：不要用 `xcodebuild`、iOS 模拟器，也没有 XCTest / swift-testing。
- Swift 命令都在 `QuotaPet/` 目录下跑。工具链是 Swift 6，但 `Package.swift` 里的语言模式是 v5。

## 常用命令（在 `QuotaPet/` 下）

```bash
make check      # = swift run QuotaPetChecks，唯一的测试
swift build     # 只编译
make previews   # 把宠物、菜单栏、面板渲染成 PNG 到 build/previews；改界面后用它验证，不用启动 App
make dump       # 在终端打印当前额度推算（读真实数据）
make run / make demo / make install
```

- 自检是 `Sources/QuotaPetChecks/main.swift` 里的一串顶层 `check(...)`，按 `// MARK:` 分组，**不能单独跑某一项**，失败时会打印行号。它用了 `@testable import`，只能 debug 构建，不要加 `-c release`。
- 仓库根目录下的 `usage_lab.py` 是做 App 之前的实验工具，只用标准库：`python3 usage_lab.py summary|snap|ratio|calibrate|backtest`。

## 架构

数据流：`UsageProvider`（`QuotaPetCore/Models.swift`）→ `UsageStore`（FSEvents 触发，另外每分钟兜底刷新，在后台串行队列上算快照）→ 菜单栏、面板、`NotificationManager`。宠物、菜单栏、通知只认 `UsageSnapshot`，不关心是哪家 AI；接入新的 AI 就实现一个 `UsageProvider`（例子见 `QuotaPet/README.md`）。

- `QuotaPetCore` 是纯逻辑，不能依赖 AppKit，这样自检才跑得起来。界面代码都在 `QuotaPet` target 里。
- `ClaudeProvider.snapshot` 的算法：当前 % = 最近一次官方读数（桌面端每 15 分钟写一次 `plan-usage-history.json`）+ 读数之后本机日志里请求的额度加权花费（API 价格，但缓存读按半价）÷ 换算率。
  - 换算率由 `RateLearner` 从 `IntervalArchive` 学出来（`~/Library/Application Support/QuotaPet/intervals.jsonl`，只追加，半衰期 3 小时），起始值 $0.27 / 1%。
  - 窗口的开始和重置时间由 `WindowInference` 推算：5 小时窗口从第一次使用开始；每周额度按固定时间重置（`fixedCadence`），看到过一次重置（读数掉了至少 3 个点，或限流消息）后就按它每 7 天循环，多次跳变取交集收窄时间、取最晚的时刻。用户手动指定了每周重置时间时，按它往后每 7 天算一次。
  - Claude Code 被限流时会在日志里写一条 synthetic 消息，带 `quotaLimits`（`rateLimitType`、秒级 `resetsAt`）。扫描器把它记成 `ClaudeLimitEvent`：没到恢复时间前这个窗口直接算用完，重置时间以它为准。
  - 其他端（网页、手机、桌面端聊天）用量由 `OtherUsage` 算：相邻两次官方读数之间，官方增量比本机估算多出门槛以上的部分。`RateLearner` 学换算率时也用同一个门槛，跳过这种混用的区间。
  - **不变量**：官方读数没到 100 时，估算值最多 99%。只有官方读数或限流消息能宣布「用完了」，免得宠物误睡、误发提醒。
- **和 `usage_lab.py` 要保持一致的地方**，改一边就要改另一边：
  - `ClaudePricing.prices` 对应 `PRICES`，`cacheReadQuotaWeight` 对应 `CACHE_READ_WEIGHT`，`ClaudeRates.starting` 对应 `STARTING`，`OtherUsage.threshold` 对应 `OTHER_THRESHOLD`
  - `ModelFamily.of` 对应 `family()`：按模型名里的子串匹配，名字里不含 fable、opus、sonnet、haiku 的新模型族不会计价，要加 case 和价格
  - `ClaudeTranscripts` 的解析规则：按 `message.id` 去重、同一个响应的各字段取最大值、跳过 synthetic 和写到一半的行（限流消息只有 App 读，usage_lab 不需要）
- 改换算相关的逻辑之前，先看 `docs/PRODUCT_PLAN.md` 第 7 节的回归结论：所有模型用一个系数，思考程度（effort）不单独算，缓存读按半价。改完用 `python3 usage_lab.py backtest` 回测，和改之前比一比。
- `QuotaPetCore/Pet/PetArt.swift` 是 `design/export_swift.py` 生成的，**不要手改**。改宠物的流程：改 `design/pet_pixel.py` → 运行它出预览图 → 运行 `export_swift.py` 导出（要装 Pillow 和 NumPy）。
  - 可选的形象（经典、猫耳、青春、魔女）在 `design/chibi4.py` 的 `STYLES` 里：可以换发型、饰品、配色、眼睛（`pet_pixel.EYE_SETS`）、嘴和腮红，`SsPW` 的颜色不能改（单色模式靠它们挖空脸）。标了 `draft` 的是设计稿，不导出。加一款要同时在 `PetSprites.swift` 的 `PetStyle` 里加 case。`python3 design/pet_pixel.py styles` 会把各款并排出一张对比图。
- 命令行参数（`--demo`、`--dump`、`--render-previews` 等）都在 `Sources/QuotaPet/main.swift` 里分发。

## 隐私（仓库是公开的）

- 只读本机文件：不联网，不读任何登录凭据。「用凭据调官方 usage 接口」是刻意不做的。
- `make previews` 会额外生成 `popover-live.png` 和 `popover-live-dark.png`，用的是**本机真实额度数据**，不能复制进 `docs/images/` 或提交；其余预览图都是假数据。
- `make dump` 和 `usage_lab.py` 的输出、`snapshots.jsonl`、`intervals.jsonl` 都是真实数据，不进 git，也不贴进 issue 或 PR。
- `.githooks/pre-commit` 会在提交时拦住 `.jsonl` 文件、截图、`popover-live*`、本机绝对路径和不是 noreply 的邮箱。它是用 `git config core.hooksPath .githooks` 启用的，被拦了就改内容，不要加 `--no-verify` 绕过。

## 什么时候用哪个技能

| 场景 | 技能 |
|---|---|
| 改完代码要确认能用 | `quotapet-verify`（编译 + 自检 + 渲染预览图并查看） |
| 更新模型价格或加新模型 | `claude-api`（查当前价格），然后同步改 `usage_lab.py` |
| 一个功能写完 | `/simplify`；改动较大就用 `/code-review` |
| push 之前 | `/security-review`：重点看有没有联网、读凭据、真实数据进 git |
