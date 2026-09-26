import SwiftUI
import QuotaPetCore

@MainActor
final class PopoverState: ObservableObject {
    enum Page { case overview, settings }
    @Published var page: Page = .overview
    /// 面板最高多高：菜单栏所在的屏幕放得下多少。小屏幕上设置页放不下，超出的部分滚动
    @Published var maxHeight: CGFloat = .infinity
}

struct PopoverRoot: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var state: PopoverState
    /// 不用 @ObservedObject：动画每秒好几帧，只让宠物那一小块跟着刷新
    let animator: PetAnimator
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
                OverviewView(
                    snapshot: store.snapshot,
                    errorMessage: store.errorMessage,
                    mood: store.snapshot == nil && store.errorMessage != nil ? .confused : PetMood.from(snapshot: store.snapshot),
                    pet: LivePet(animator: animator),
                    onRefresh: { store.refresh() },
                    onSettings: { state.page = .settings },
                    onQuit: onQuit)
            case .settings:
                SettingsView(settings: settings,
                             suggestedWeeklyReset: store.snapshot?.window("seven_day")?.resetsAt,
                             estimation: store.snapshot?.estimation,
                             onBack: { state.page = .overview })
            }
        }
        .id(settings.language)  // 换语言时整个面板重建：输入没变的子视图 SwiftUI 不会重画，文字会停在旧语言
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
