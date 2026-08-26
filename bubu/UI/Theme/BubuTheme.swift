import SwiftUI
import UIKit

// MARK: - 步步设计系统
// 参考: /bubu/DESIGN.md
// 单绿色 + 暗色阶梯 + 宇宙装饰

enum BubuTheme {
    // MARK: - 品牌色

    enum Primary {
        static let green = Color(hex: "E7FF72")
        static let active = Color(hex: "D7F45E")
        static let soft = Color(hex: "46591A")
        static let uiTint = Color(hex: "8FAE2A")
    }

    // MARK: - 表面层级（墨蓝）

    enum Surface {
        static let space = Color(hex: "060816")
        static let surface1 = Color(hex: "0C1021")
        static let surface2 = Color(hex: "12172B")
        static let surface3 = Color(hex: "20263B")
    }

    enum Glass {
        static let topHighlight = Color.white.opacity(0.16)
        static let bottomShadow = Color.black.opacity(0.18)
        static let stroke = Color.white.opacity(0.14)
        static let innerStroke = Color.white.opacity(0.05)
        static let selectedFill = Color.white.opacity(0.10)
    }

    // MARK: - 文字

    enum Text {
        static let ink = Color(hex: "F2F5FB")
        static let secondary = Color(hex: "B7BED3")
        static let tertiary = Color(hex: "6F7894")
        static let onPrimary = Color(hex: "11150A")
    }

    // MARK: - 语义色（尽量不用）

    enum Semantic {
        static let visitedBad = Text.secondary
        static let visitedNeutral = Primary.green.opacity(0.42)
    }

    // MARK: - 宇宙装饰色（仅装饰层使用）

    enum Cosmic {
        static let starBright = Color(hex: "FFFFFF")
        static let starDim = Color(hex: "8E97B8")
        static let nebulaPurple = Color(hex: "434A78")
        static let nebulaTeal = Color(hex: "7AAE7D")
    }

    // MARK: - 地点状态映射

    static func colorForStatus(_ status: PlaceStatus) -> Color {
        switch status {
        case .wantToGo:     return Text.tertiary
        case .visitedGood:  return Primary.green
        case .visitedBad:   return Semantic.visitedBad
        case .visitedNeutral: return Semantic.visitedNeutral
        }
    }

    static func foregroundForStatus(_ status: PlaceStatus) -> Color {
        switch status {
        case .wantToGo:
            return Surface.space
        case .visitedGood:
            return Text.onPrimary
        case .visitedBad:
            return Text.ink
        case .visitedNeutral:
            return Text.onPrimary
        }
    }

    static func readableText(on color: Color) -> Color {
        let resolved = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return Text.ink
        }

        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.6 ? Text.onPrimary : Text.ink
    }

    static func mapMarkerColor(for status: PlaceStatus) -> Color {
        switch status {
        case .wantToGo:     return Text.tertiary
        case .visitedGood:  return Primary.green
        case .visitedBad:   return Semantic.visitedBad
        case .visitedNeutral: return Semantic.visitedNeutral
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - 字体

enum BubuFont {
    // 标题
    static let titleXL = Font.system(size: 28, weight: .bold, design: .rounded)
    static let titleLG = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let titleMD = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let titleSM = Font.system(size: 15, weight: .medium, design: .rounded)

    // 正文
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySM = Font.system(size: 13, weight: .regular, design: .default)

    // 辅助
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let button = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let tab = Font.system(size: 10, weight: .medium, design: .rounded)

    // 装饰（仅 Welcome 页）
    static let displayRounded = Font.system(size: 32, weight: .bold, design: .rounded)
}

// MARK: - 间距

enum BubuSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - 圆角

enum BubuRadius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 30
    static let full: CGFloat = 999
}

// MARK: - 触控

enum BubuTouch {
    static let minTarget: CGFloat = 44
    static let buttonHeight: CGFloat = 48
}

// MARK: - View Modifiers

struct BubuCardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .background(elevated ? BubuTheme.Surface.surface2 : BubuTheme.Surface.surface1)
            .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
    }
}

struct BubuButtonModifier: ButtonStyle {
    let variant: ButtonVariant

    enum ButtonVariant {
        case primary, secondary, ghost
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BubuFont.button)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 24)
            .frame(minHeight: BubuTouch.buttonHeight)
            .background(background(for: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
            .overlay(border)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: BubuRadius.md)
            .stroke(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        switch variant {
        case .primary: return .clear
        case .secondary: return BubuTheme.Surface.surface3
        case .ghost: return .clear
        }
    }

    private func background(for isPressed: Bool) -> Color {
        switch variant {
        case .primary:
            return isPressed ? BubuTheme.Primary.active : BubuTheme.Primary.green
        case .secondary:
            return .clear
        case .ghost:
            return .clear
        }
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary: return BubuTheme.Text.onPrimary
        case .secondary: return BubuTheme.Text.ink
        case .ghost: return BubuTheme.Text.secondary
        }
    }
}

extension View {
    func bubuCard(elevated: Bool = false) -> some View {
        modifier(BubuCardModifier(elevated: elevated))
    }
}

// ButtonStyle 不能直接用在 View extension，用 convenience 方法
extension View {
    func bubuButtonStyle(_ variant: BubuButtonModifier.ButtonVariant) -> some View {
        buttonStyle(BubuButtonModifier(variant: variant))
    }
}

struct BubuGlassCapsule: View {
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                BubuTheme.Glass.topHighlight,
                                .white.opacity(0.04)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Capsule()
                    .stroke(BubuTheme.Glass.stroke, lineWidth: 0.9)
            )
            .shadow(color: BubuTheme.Glass.bottomShadow, radius: 18, y: 10)
    }
}

struct BubuGlassCircle: View {
    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                BubuTheme.Glass.topHighlight,
                                .white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                Circle()
                    .stroke(BubuTheme.Glass.stroke, lineWidth: 0.9)
            )
            .shadow(color: BubuTheme.Glass.bottomShadow, radius: 16, y: 8)
    }
}

struct BubuGlassRounded: View {
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                BubuTheme.Glass.topHighlight,
                                .white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(BubuTheme.Glass.stroke, lineWidth: 0.9)
            )
            .shadow(color: BubuTheme.Glass.bottomShadow, radius: 16, y: 8)
    }
}
