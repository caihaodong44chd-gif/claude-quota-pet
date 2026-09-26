import SwiftUI
import QuotaPetCore

@MainActor
final class PopoverState: ObservableObject {
    enum Page { case overview, settings }
    @Published var page: Page = .overview
    /// 同时有几家时，面板上看的是哪家；每次打开面板先看宠物跟着的那家
    @Published var selected: ProviderID = .claude
    @Published var isShown = false
    /// 面板最高多高：菜单栏所在的屏幕放得下多少。小屏幕上设置页放不下，超出的部分滚动
    @Published var maxHeight: CGFloat = .infinity
}

struct PopoverRoot: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: PopoverState
    /// 不用 @ObservedObject：动画每秒好几帧，只让宠物那一小块跟着刷新。
    /// animator 是菜单栏上的宠物；面板切到另一家时换成 headerAnimator
    let animator: PetAnimator
    let headerAnimator: PetAnimator
    var onQuit: () -> Void

    var body: some View {
        ScrollView {  // 内容放得下时 ScrollView 和内容一样高，不会出现滚动条
            pages
        }
        .frame(width: 340)
        .frame(maxHeight: state.maxHeight)
    }

    private var pages: some View {
        Group {
            switch state.page {
            case .overview:
                let shown = store.shown
                let focus = store.focus?.provider
                // 选中的那家没数据了（比如 Codex 的记录过期了）就回到宠物跟着的那家
                let selected = shown.contains { $0.provider == state.selected } ? state.selected : focus ?? .claude
                let snapshot = store.snapshot(for: selected)
                let look = PetLook(mood: PetMood.of(snapshot, failed: store.errors[selected] != nil),
                                   style: PetStyle.of(selected, claudeStyle: settings.petStyle, codexStyle: settings.codexPetStyle))
                OverviewView(
                    snapshot: snapshot,
                    errorMessage: store.errors[selected],
                    mood: look.mood,
                    pet: LivePet(animator: selected == focus ? animator : headerAnimator),
                    tabs: shown.count > 1 ? shown : [],
                    focus: focus,
                    onSelect: { state.selected = $0 },
                    onRefresh: { store.refresh() },
                    onSettings: { state.page = .settings },
                    onQuit: onQuit)
                    .onChange(of: look, initial: true) { _, look in headerAnimator.show(mood: look.mood, style: look.style) }
            case .settings:
                let claude = store.snapshot(for: .claude)
                SettingsView(settings: settings,
                             suggestedWeeklyReset: claude?.window("seven_day")?.resetsAt,
                             estimation: claude?.estimation,
                             hasCodex: store.snapshot(for: .codex)?.hasData == true,
                             codexReadingAt: store.snapshot(for: .codex)?.officialAt,
                             onBack: { state.page = .overview })
            }
        }
        .id(settings.language)  // 换语言时整个面板重建：输入没变的子视图 SwiftUI 不会重画，文字会停在旧语言
    }
}

/// 面板上的宠物长什么样：哪种心情、哪个形象
struct PetLook: Equatable {
    var mood: PetMood
    var style: PetStyle
}

extension PetMood {
    /// 这家的心情；还一次都没算出来又出错了时是疑惑
    static func of(_ snapshot: UsageSnapshot?, failed: Bool) -> PetMood {
        snapshot == nil && failed ? .confused : PetMood.from(snapshot: snapshot)
    }
}

/// 跟着动画走的宠物
struct LivePet: View {
    @ObservedObject var animator: PetAnimator

    var body: some View { PetImage(grid: animator.frame.portrait) }
}

/// 面板里的半身像：64×64，每格 1.5pt，显示成 96pt
struct PetImage: View {
    var grid: PixelGrid
    var pixel: CGFloat = 1.5

    var body: some View {
        Image(nsImage: PetRenderer.image(grid, pixel: pixel, template: false))
            .frame(width: CGFloat(grid.width) * pixel, height: CGFloat(grid.height) * pixel)
            .accessibilityHidden(true)
    }
}

/// 使用率对应的颜色
enum Level {
    static func bar(_ percent: Double) -> Color {
        switch percent {
        case ..<50: return Color(nsColor: .systemGreen)
        case ..<75: return Color(nsColor: .systemYellow)
        case ..<90: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    static func text(_ percent: Double) -> Color {
        switch percent {
        case ..<75: return .primary
        case ..<90: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    static func mood(_ mood: PetMood) -> Color {
        switch mood {
        case .energetic: return Color(nsColor: .systemGreen)
        case .normal: return Color(nsColor: .systemTeal)
        case .tired: return Color(nsColor: .systemOrange)
        case .exhausted: return Color(nsColor: .systemRed)
        case .sleeping: return Color(nsColor: .systemIndigo)
        case .confused, .loading: return Color(nsColor: .systemGray)
        }
    }
}

struct IconButton: View {
    var systemName: String
    var help: String
    /// 旋转角度（刷新按钮点一下转一圈）
    var rotation: Double = 0
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .rotationEffect(.degrees(rotation))
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
    }
}
