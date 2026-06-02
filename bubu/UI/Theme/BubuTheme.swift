import SwiftUI

// MARK: - 步步设计系统
// 参考: /bubu/DESIGN.md
// 单绿色 + 暗色阶梯 + 宇宙装饰

enum BubuTheme {
    // MARK: - 品牌色（仅一个彩色）

    enum Primary {
        static let green = Color(hex: "4ADE80")
        static let active = Color(hex: "22C55E")
        static let soft = Color(hex: "166534")
    }

    // MARK: - 表面层级

    enum Surface {
        static let space = Color(hex: "0A0A0F")
        static let surface1 = Color(hex: "12121A")
        static let surface2 = Color(hex: "1A1A24")
        static let surface3 = Color(hex: "24243A")
    }

    // MARK: - 文字

    enum Text {
        static let ink = Color(hex: "F5F5F7")
        static let secondary = Color(hex: "A1A1AA")
        static let tertiary = Color(hex: "6B6B76")
        static let onPrimary = Color(hex: "0A0A0F")
    }

    // MARK: - 语义色（尽量不用）

    enum Semantic {
        static let visitedBad = Color(hex: "F87171")
        static let visitedNeutral = Color(hex: "FBBF24")
    }

    // MARK: - 宇宙装饰色（仅装饰层使用）

    enum Cosmic {
        static let starBright = Color(hex: "FFFFFF")
        static let starDim = Color(hex: "A5B4FC")
        static let nebulaPurple = Color(hex: "7C3AED")
        static let nebulaTeal = Color(hex: "2DD4BF")
    }

    // MARK: - 地点状态映射

    static func colorForStatus(_ status: PlaceStatus) -> Color {
        switch status {
        case .wantToGo:     return Text.secondary
        case .visitedGood:  return Primary.green
        case .visitedBad:   return Semantic.visitedBad
        case .visitedNeutral: return Semantic.visitedNeutral
        }
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
    static let titleXL = Font.system(size: 28, weight: .bold, design: .default)
    static let titleLG = Font.system(size: 22, weight: .semibold, design: .default)
    static let titleMD = Font.system(size: 17, weight: .semibold, design: .default)
    static let titleSM = Font.system(size: 15, weight: .medium, design: .default)

    // 正文
    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let bodySM = Font.system(size: 13, weight: .regular, design: .default)

    // 辅助
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let button = Font.system(size: 15, weight: .medium, design: .default)
    static let tab = Font.system(size: 10, weight: .medium, design: .default)

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
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
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