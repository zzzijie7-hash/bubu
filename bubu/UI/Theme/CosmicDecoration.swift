import SwiftUI

// MARK: - 宇宙装饰组件

/// 星点粒子背景 — 随机分布的微小光点
struct StarfieldView: View {
    let density: StarDensity
    let maxOpacity: Double

    enum StarDensity {
        case low    // 地图页 — 不干扰标记
        case medium // 列表页
        case high   // Welcome 页

        var count: Int {
            switch self {
            case .low: return 30
            case .medium: return 60
            case .high: return 100
            }
        }

        var minSize: CGFloat {
            switch self {
            case .low: return 1
            case .medium: return 1
            case .high: return 1
            }
        }

        var maxSize: CGFloat {
            switch self {
            case .low: return 2
            case .medium: return 2.5
            case .high: return 3
            }
        }
    }

    init(density: StarDensity = .medium, maxOpacity: Double = 0.4) {
        self.density = density
        self.maxOpacity = maxOpacity
    }

    // 使用固定 seed 保证每次渲染一致（不是每次重绘都变位置）
    private struct Star: Identifiable {
        let id: Int
        let xFraction: CGFloat
        let yFraction: CGFloat
        let size: CGFloat
        let opacity: Double
        let isBright: Bool
    }

    private var stars: [Star] {
        var rng = SeededRandom(seed: 42)
        return (0..<density.count).map { i in
            let isBright = rng.next() < 0.15
            let opacity = isBright
                ? Double.random(in: maxOpacity * 0.6...maxOpacity, using: &rng)
                : Double.random(in: maxOpacity * 0.15...maxOpacity * 0.35, using: &rng)
            return Star(
                id: i,
                xFraction: rng.next(),
                yFraction: rng.next(),
                size: CGFloat.random(in: density.minSize...density.maxSize, using: &rng),
                opacity: opacity,
                isBright: isBright
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(stars) { star in
                Circle()
                    .fill(star.isBright ? BubuTheme.Cosmic.starBright : BubuTheme.Cosmic.starDim)
                    .frame(width: star.size, height: star.size)
                    .opacity(star.opacity)
                    .position(
                        x: star.xFraction * geo.size.width,
                        y: star.yFraction * geo.size.height
                    )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 星云渐变 — 大半径模糊的大气光效
struct NebulaBackground: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 紫色星云 — 右上角
                Circle()
                    .fill(BubuTheme.Cosmic.nebulaPurple.opacity(0.05))
                    .frame(width: geo.size.width * 0.7)
                    .blur(radius: 80)
                    .position(x: geo.size.width * 0.75, y: geo.size.height * 0.15)

                // 青色星云 — 左下角
                Circle()
                    .fill(BubuTheme.Cosmic.nebulaTeal.opacity(0.04))
                    .frame(width: geo.size.width * 0.6)
                    .blur(radius: 70)
                    .position(x: geo.size.width * 0.2, y: geo.size.height * 0.7)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// 宇宙画布 — Starfield + Nebula 组合
struct CosmicCanvas<Content: View>: View {
    let starDensity: StarfieldView.StarDensity
    let showNebula: Bool
    @ViewBuilder let content: () -> Content

    init(
        starDensity: StarfieldView.StarDensity = .medium,
        showNebula: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.starDensity = starDensity
        self.showNebula = showNebula
        self.content = content
    }

    var body: some View {
        ZStack {
            BubuTheme.Surface.space
                .ignoresSafeArea()

            if showNebula {
                NebulaBackground()
            }

            StarfieldView(density: starDensity)

            content()
        }
    }
}

/// 地图画布 — 暗色底 + 低密度星点（不加星云避免干扰地图）
struct MapCanvas<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            BubuTheme.Surface.space
                .ignoresSafeArea()

            StarfieldView(density: .low, maxOpacity: 0.25)

            content()
        }
    }
}

/// "点亮"光晕扩散动效
struct LightUpEffect: View {
    @State private var isAnimating = false
    let color: Color

    init(color: Color = BubuTheme.Primary.green) {
        self.color = color
    }

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(color.opacity(isAnimating ? 0 : 0.5), lineWidth: 1.5)
                    .scaleEffect(isAnimating ? 2.5 + CGFloat(i) * 0.8 : 0.3)
                    .opacity(isAnimating ? 0 : 0.6)
                    .animation(
                        .easeOut(duration: 0.5).delay(Double(i) * 0.08),
                        value: isAnimating
                    )
            }
        }
        .frame(width: 20, height: 20)
        .onAppear { isAnimating = true }
    }
}

// MARK: - 确定性随机数生成器（保证每次渲染星点位置不变）

struct SeededRandom {
    private var seed: UInt64

    init(seed: UInt64) {
        self.seed = seed
    }

    mutating func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed % 10000) / 10000.0
    }
}

extension CGFloat {
    static func random(in range: ClosedRange<CGFloat>, using rng: inout SeededRandom) -> CGFloat {
        range.lowerBound + rng.next() * (range.upperBound - range.lowerBound)
    }
}

extension Double {
    static func random(in range: ClosedRange<Double>, using rng: inout SeededRandom) -> Double {
        range.lowerBound + Double(rng.next()) * (range.upperBound - range.lowerBound)
    }
}