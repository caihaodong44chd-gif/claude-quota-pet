---
name: quotapet-verify
description: 验证 QuotaPet（Swift 写的 macOS 菜单栏 App）的改动真的能用：编译所有 target、跑自检、把宠物、菜单栏、面板渲染成 PNG 来看，必要时用真实数据对账或启动 App。只要改了 QuotaPet/ 下的 Swift 代码、宠物像素画、界面文字或额度计算逻辑，收尾前都用它；用户说「跑一下」「看看效果」「能用吗」「截个图」「验证一下」「提交前检查」时也用它，即使没点名这个技能。不适用于 iOS 模拟器：这是 macOS App，本机也没有 Xcode。
---

# QuotaPet 改动验证

目标是用最少的构建次数、最少的图片 token，确认改动能编译、自检通过、界面也对。下面的命令都在 `QuotaPet/` 目录下跑，除非另外写明。

## 1. 先看改了什么，决定做到哪一步

用 `git status --short` 和 `git diff --stat` 看改动范围，再按下表决定做哪几步：

| 改了什么 | 做哪几步 |
|---|---|
| 任何 Swift 文件 | 第 2 步（编译 + 自检），每次必做 |
| 界面、宠物、菜单栏的样子：`Views/`、`Pet/`、`PetArt.swift`、`Formatting.swift` 等 | 再做第 3 步（预览图） |
| `QuotaPetCore/Claude/` 下的解析、定价、窗口推算、换算率 | 再做第 4 步（真实数据对账） |
| App 运行时的行为：`AppDelegate`、`ClaudeAppWatcher`、`NotificationManager`、设置的保存、点击和菜单 | 预览图看不到，做第 5 步 |

## 2. 编译 + 自检

```bash
swift build 2>&1 | grep -E "error:|warning:|Build complete" | head -40
make check
```

- 一定要先 `swift build`：`make check` 只编译 `QuotaPetCore` 和自检程序，App 本体（界面代码）有编译错误它发现不了。
- 编译输出很长，只看 error、warning 和最后的 `Build complete`，省 token；有错误时再看完整输出。
- 改了行为就在 `Sources/QuotaPetChecks/main.swift` 对应的 `// MARK:` 分组里补一条 `check(...)`。自检不能只跑某一项，失败时会打印行号。不要加 `-c release`：自检用了 `@testable import`，只有 debug 构建能用。

## 3. 渲染预览图并查看

```bash
make previews   # 输出到 build/previews/
```

用 Read 工具打开 PNG 来看。每张图都要花不少 token，所以**只看跟改动有关的几张**：先看浅色版，改了颜色再看 `-dark` 版。

| 文件 | 内容 |
|---|---|
| `pet-sheet.png` / `pet-sheet-mono.png` | 每种心情一行、每帧一列（彩色 / 单色） |
| `menubar.png` | 菜单栏效果：浅色 / 深色、彩色 / 单色、各种百分比、限流倒计时 |
| `popover-{calm,busy,limited,empty}.png` | 面板的四种状态（假数据） |
| `settings.png` | 设置页 |
| `popover-*-en.png` / `settings-en.png` / `pet-sheet-en.png` | 英文界面（面板、设置页各有 `-dark` 版）：改了界面文字要看，英文比中文长，容易折行、截断 |
| `popover-live*.png` | **本机真实数据**：只能自己看，不能复制到 `docs/images/`，也不能提交 |

看的时候检查：文字有没有被截断、对齐和间距对不对、深浅色下是不是都看得清、宠物表情和心情对不对得上。

如果改动影响了 README 里的截图，就把对应的假数据图从 `build/previews/` 复制到 `docs/images/`。README 用到的是 `menubar`、`pet-sheet`、`popover-busy`、`popover-limited`（后两个各有 `-dark` 版）；英文版 `README.en.md` 用的是它们的 `-en` 版（`pet-sheet-en`、`popover-busy-en`、`popover-limited-en` 及 `-dark`），`menubar` 中英通用。`icon.png` 来自 `build/AppIcon.iconset/icon_128x128@2x.png`，要先跑 `make app` 才有。复制之前先告诉用户。

## 4. 用真实数据对账（改了数据逻辑时）

```bash
make dump                            # App 的推算，最后一行是「最近 24 小时（对账用）」
cd .. && python3 usage_lab.py summary   # 在仓库根目录跑，默认也是最近 24 小时
```

两边最近 24 小时的请求数和美元金额应该对得上，因为解析规则是一样的。对不上时，先查 `ClaudeTranscripts` 和 `usage_lab.py` 两边的规则是不是改了一边。这些输出是用户的真实用量，只在本地看，不要写进提交、PR 或文档。

## 5. 运行时的行为（预览图看不到的）

```bash
make run                        # 会先关掉正在运行的 QuotaPet，包括 ~/Applications 里装的那个
pgrep -lx QuotaPet              # 确认启动了
defaults read dev.quotapet.app  # 看设置有没有存上
```

- 想测「跟着 Claude 出现 / 隐藏」，可以加 `--watch-bundle-id <别的 App 的 bundle id>`，改成盯别的 App，不用真的去开关 Claude。
- 菜单栏上的实际效果和通知弹窗要靠人眼看：告诉用户看哪里、应该看到什么。除非用户要求，不要为了截屏去开 computer-use，它又慢又费 token。
- 如果测试时替换掉了用户装的那个版本，最后提醒一句：`make install` 装上新版，或者 `open ~/Applications/QuotaPet.app` 换回原来的。

## 6. 汇报

一两句话说清楚：编译有没有通过；自检多少项通过；看了哪几张图，看到了什么；哪些没法自己验证（比如通知要用户自己看）。
