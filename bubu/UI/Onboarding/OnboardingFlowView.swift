import SwiftUI

// MARK: - 引导流程

struct OnboardingFlowView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentStep: OnboardingStep = .welcome

    var body: some View {
        NavigationStack {
            VStack {
                // 进度指示 + 跳过按钮
                HStack {
                    HStack(spacing: 4) {
                        ForEach(OnboardingStep.allCases.indices, id: \.self) { index in
                            Capsule()
                                .fill(
                                    index <= currentStep.index
                                        ? BubuTheme.Primary.green
                                        : BubuTheme.Text.tertiary
                                )
                                .frame(width: index == currentStep.index ? 24 : 8, height: 4)
                                .animation(.easeInOut(duration: 0.3), value: currentStep)
                        }
                    }
                    Spacer()
                    Button("跳过") {
                        completeOnboarding()
                    }
                    .font(BubuFont.titleSM)
                    .foregroundStyle(BubuTheme.Text.tertiary)
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)

                // 步骤内容
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeView(onNext: { advanceStep() })
                    case .tutorialSwipe:
                        TutorialSwipeView(onComplete: { advanceStep() })
                    case .categoryPreference:
                        CategoryPreferenceView(onNext: { advanceStep() })
                    case .importGuide:
                        ImportGuideView(onComplete: { completeOnboarding() })
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing),
                    removal: .move(edge: .leading)
                ))
            }
            .animation(.easeInOut(duration: 0.35), value: currentStep)
        }
    }

    private func advanceStep() {
        guard let index = OnboardingStep.allCases.firstIndex(of: currentStep),
              index + 1 < OnboardingStep.allCases.count else { return }
        currentStep = OnboardingStep.allCases[index + 1]
    }

    private func completeOnboarding() {
        appState.completeOnboarding()
    }
}

enum OnboardingStep: CaseIterable {
    case welcome
    case tutorialSwipe
    case categoryPreference
    case importGuide

    var index: Int { OnboardingStep.allCases.firstIndex(of: self) ?? 0 }
}

// MARK: - Welcome 页面

struct WelcomeView: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Logo 区域
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BubuTheme.Primary.green, BubuTheme.Cosmic.nebulaTeal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)

                    Image(systemName: "shoe.2.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-10))
                }

                Text("步步")
                    .font(BubuFont.titleXL)
                    .foregroundStyle(BubuTheme.Text.ink)

                Text("Bubu · Walk Your World")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BubuTheme.Text.tertiary)
            }

            // 核心价值
            VStack(spacing: 20) {
                FeatureRow(icon: "map.fill", title: "点亮地图", description: "标记每一个你去过和想去的地方")
                FeatureRow(icon: "heart.text.square.fill", title: "留下记忆", description: "评价、心情、照片，记录当下的感受")
                FeatureRow(icon: "sparkles", title: "发现美好", description: "探索城市里那些值得一去的好地方")
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onNext) {
                Text("开始探索")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BubuButtonModifier(variant: .primary))
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(BubuTheme.Surface.space)
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(BubuTheme.Primary.green)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BubuFont.titleMD)
                    .foregroundStyle(BubuTheme.Text.ink)
                Text(description)
                    .font(BubuFont.caption)
                    .foregroundStyle(BubuTheme.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tutorial Tinder 卡片页面

struct TutorialSwipeView: View {
    let onComplete: () -> Void
    @State private var currentIndex = 0
    @State private var offset: CGSize = .zero
    @State private var curatedPlaces = TutorialSwipeView.samplePlaces

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("发现你感兴趣的地方")
                .font(BubuFont.titleLG)
                .foregroundStyle(BubuTheme.Text.ink)

            Text("右滑「想去」· 左滑「不感兴趣」")
                .font(BubuFont.caption)
                .foregroundStyle(BubuTheme.Text.secondary)

            // 卡片堆
            ZStack {
                ForEach(Array(curatedPlaces.enumerated().prefix(3)), id: \.element.id) { index, place in
                    DiscoverCardView(place: place)
                        .offset(index == currentIndex ? offset : .zero)
                        .rotationEffect(
                            index == currentIndex
                                ? .degrees(Double(offset.width / 10))
                                : .zero
                        )
                        .gesture(
                            index == currentIndex
                                ? DragGesture()
                                    .onChanged { gesture in
                                        offset = gesture.translation
                                    }
                                    .onEnded { gesture in
                                        let threshold: CGFloat = 100
                                        if gesture.translation.width > threshold {
                                            swipeRight()
                                        } else if gesture.translation.width < -threshold {
                                            swipeLeft()
                                        } else {
                                            withAnimation(.spring()) {
                                                offset = .zero
                                            }
                                        }
                                    }
                                : nil
                        )
                        .opacity(index < currentIndex ? 0 : 1)
                        .scaleEffect(index < currentIndex ? 0.8 : 1 - CGFloat(index - currentIndex) * 0.05)
                        .animation(.spring(response: 0.4), value: currentIndex)
                }
            }
            .frame(height: 400)

            // 左右按钮
            HStack(spacing: 48) {
                Button {
                    swipeLeft()
                } label: {
                    Circle()
                        .stroke(BubuTheme.Semantic.visitedBad, lineWidth: 2)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundStyle(BubuTheme.Semantic.visitedBad)
                        )
                }

                Button {
                    swipeRight()
                } label: {
                    Circle()
                        .fill(BubuTheme.Primary.green)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Image(systemName: "heart.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                        )
                }
            }

            Spacer()

            if currentIndex >= curatedPlaces.count {
                Button("继续") {
                    onComplete()
                }
                .buttonStyle(BubuButtonModifier(variant: .primary))
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .transition(.opacity)
            }
        }
        .background(BubuTheme.Surface.space)
    }

    private func swipeRight() {
        withAnimation(.spring()) {
            offset = CGSize(width: 500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            currentIndex += 1
            offset = .zero
        }
    }

    private func swipeLeft() {
        withAnimation(.spring()) {
            offset = CGSize(width: -500, height: 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            currentIndex += 1
            offset = .zero
        }
    }

    static let samplePlaces: [CuratedPlace] = [
        CuratedPlace(id: UUID(), name: "故宫博物院", address: "北京市东城区", latitude: 39.9163, longitude: 116.3972, category: .museum, description: "中国最著名的宫殿建筑群", imageURL: nil, tag: "必去"),
        CuratedPlace(id: UUID(), name: "南锣鼓巷", address: "北京市东城区", latitude: 39.937, longitude: 116.4039, category: .landmark, description: "老北京胡同文化街区", imageURL: nil, tag: "扫街"),
        CuratedPlace(id: UUID(), name: "四季民福烤鸭店", address: "北京市东城区", latitude: 39.91, longitude: 116.41, category: .restaurant, description: "地道北京烤鸭", imageURL: nil, tag: "必吃"),
        CuratedPlace(id: UUID(), name: "798艺术区", address: "北京市朝阳区", latitude: 39.9842, longitude: 116.4951, category: .museum, description: "当代艺术聚集地", imageURL: nil, tag: "文艺"),
        CuratedPlace(id: UUID(), name: "什刹海", address: "北京市西城区", latitude: 39.937, longitude: 116.385, category: .scenic, description: "京城水乡，夜景很美", imageURL: nil, tag: "散步")
    ]
}

struct DiscoverCardView: View {
    let place: CuratedPlace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 图片区域
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [place.category.color.opacity(0.6), BubuTheme.Surface.surface1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 220)

                if let tag = place.tag {
                    Text(tag)
                        .font(BubuFont.titleSM)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(BubuTheme.Primary.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding(16)
                }
            }

            // 信息区域
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(place.category.rawValue, systemImage: place.category.iconName)
                        .font(BubuFont.caption)
                        .foregroundStyle(place.category.color)
                    Spacer()
                }

                Text(place.name)
                    .font(BubuFont.titleLG)
                    .foregroundStyle(BubuTheme.Text.ink)

                Text(place.description)
                    .font(BubuFont.caption)
                    .foregroundStyle(BubuTheme.Text.secondary)
                    .lineLimit(2)

                Text(place.address)
                    .font(BubuFont.caption)
                    .foregroundStyle(BubuTheme.Text.tertiary)
            }
            .padding(16)
        }
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .padding(.horizontal, 24)
    }
}

// MARK: - 类别偏好选择页

struct CategoryPreferenceView: View {
    let onNext: () -> Void
    @State private var selectedCategories: Set<PlaceCategoryType> = [.restaurant, .cafe, .scenic, .park]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("你对哪些地方感兴趣？")
                .font(BubuFont.titleLG)
                .foregroundStyle(BubuTheme.Text.ink)

            Text("选择你喜欢的类别，我们会推荐相关好去处")
                .font(BubuFont.caption)
                .foregroundStyle(BubuTheme.Text.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach(PlaceCategoryType.allCases, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategories.contains(category)
                    )
                    .onTapGesture {
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            Button("下一步") {
                onNext()
            }
            .buttonStyle(BubuButtonModifier(variant: .primary))
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(BubuTheme.Surface.space)
    }
}

struct CategoryChip: View {
    let category: PlaceCategoryType
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: category.iconName)
                .font(.title2)
                .foregroundStyle(isSelected ? .white : category.color)

            Text(category.rawValue)
                .font(BubuFont.caption)
                .foregroundStyle(isSelected ? .white : BubuTheme.Text.secondary)
        }
        .frame(width: 90, height: 80)
        .background(
            RoundedRectangle(cornerRadius: BubuRadius.md)
                .fill(isSelected ? category.color : BubuTheme.Surface.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: BubuRadius.md)
                        .stroke(isSelected ? Color.clear : BubuTheme.Text.tertiary, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

// MARK: - 导入引导页

struct ImportGuideView: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("导入你的收藏")
                .font(BubuFont.titleLG)
                .foregroundStyle(BubuTheme.Text.ink)

            Text("把小红书的种草、高德的标记\n一起导入步步，开始点亮地图")
                .font(BubuFont.caption)
                .foregroundStyle(BubuTheme.Text.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 16) {
                ImportOptionCard(
                    icon: "doc.text.magnifyingglass",
                    title: "解析小红书链接",
                    description: "复制帖子链接，自动提取店名和地点"
                )

                ImportOptionCard(
                    icon: "square.and.arrow.up",
                    title: "从高德导入",
                    description: "授权后同步高德收藏夹"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button("立即导入") {
                    // TODO: 触发导入流程
                    onComplete()
                }
                .buttonStyle(BubuButtonModifier(variant: .primary))

                Button("先跳过，稍后再说") {
                    onComplete()
                }
                .font(BubuFont.caption)
                .foregroundStyle(BubuTheme.Text.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(BubuTheme.Surface.space)
    }
}

struct ImportOptionCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(BubuTheme.Text.secondary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BubuFont.titleMD)
                    .foregroundStyle(BubuTheme.Text.ink)
                Text(description)
                    .font(BubuFont.caption)
                    .foregroundStyle(BubuTheme.Text.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
    }
}