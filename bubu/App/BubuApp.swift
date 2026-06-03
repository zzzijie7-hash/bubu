import SwiftUI
import CoreLocation

@main
struct BubuApp: App {
    @StateObject private var container = AppContainer.shared
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppEntryView()
                .environmentObject(container)
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .tint(BubuTheme.Primary.green)
        }
    }
}

// MARK: - App 全局状态

@MainActor
final class AppState: ObservableObject {
    @Published var isOnboardingComplete: Bool {
        didSet {
            UserDefaults.standard.set(isOnboardingComplete, forKey: "onboarding_complete")
        }
    }
    @Published var selectedTab: AppTab = .explore
    @Published var pendingSearchPlace: MapPlace?

    init() {
        self.isOnboardingComplete = UserDefaults.standard.bool(forKey: "onboarding_complete")
    }

    func completeOnboarding() {
        isOnboardingComplete = true
    }
}

enum AppTab: String, CaseIterable {
    case explore = "探索"
    case add = ""
    case profile = "我的"

    var iconName: String {
        switch self {
        case .explore: return "map.fill"
        case .add: return ""
        case .profile: return "person.fill"
        }
    }
}

// MARK: - 路由

enum AppRoute: Hashable {
    case placeDetail(placeID: UUID, userPlaceID: UUID?)
    case checkInForm(userPlaceID: UUID)
    case mediaGallery(mediaIDs: [UUID])
    case folderDetail(folderID: UUID)
    case swipeDeck(folderID: UUID)
    case importGuide
    case settings
    case about
    case checkInHistory
    case statsDashboard
}

// MARK: - App 入口

struct AppEntryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isOnboardingComplete {
            MainTabView()
        } else {
            OnboardingFlowView()
        }
    }
}

// MARK: - 悬浮底栏胶囊形状（顶部中央弧形挖空）

struct NotchedPill: Shape {
    let notchRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = rect.height / 2
        let nr = notchRadius
        let notchCenter = CGPoint(x: rect.midX, y: rect.minY)

        // 左上角圆弧 → 凹口左侧
        path.move(to: CGPoint(x: r, y: rect.minY))
        path.addLine(to: CGPoint(x: notchCenter.x - nr - 6, y: rect.minY))

        // 凹口圆弧（顺时针绕下去）
        path.addArc(center: notchCenter, radius: nr + 6,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)

        // 凹口右侧 → 右上角圆弧
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)

        // 右侧边 → 右下角
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                    radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)

        // 底边 → 左下角
        path.addLine(to: CGPoint(x: r, y: rect.maxY))
        path.addArc(center: CGPoint(x: r, y: rect.maxY - r),
                    radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)

        // 左侧边 → 左上角
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(center: CGPoint(x: r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        path.closeSubpath()
        return path
    }
}

// MARK: - 主界面：全屏地图 + 悬浮底栏

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddSearch = false

    var body: some View {
        ZStack {
            // 内容区
            Group {
                if appState.selectedTab == .explore {
                    ExploreMapView()
                } else {
                    MyPageView()
                }
            }

            // 悬浮底栏
            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $appState.selectedTab) {
                    showingAddSearch = true
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingAddSearch) {
            AddPlaceSearchSheet { place in
                appState.pendingSearchPlace = place
                appState.selectedTab = .explore
            }
        }
    }
}

// MARK: - 悬浮底栏

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let onAddTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // 胶囊背景
            NotchedPill(notchRadius: 28)
                .fill(BubuTheme.Surface.surface1)
                .frame(width: 180, height: 56)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)

            // 左侧：探索
            HStack(spacing: 0) {
                Button {
                    selectedTab = .explore
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: selectedTab == .explore ? "map.fill" : "map")
                            .font(.system(size: 18))
                        Text("探索")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == .explore ? BubuTheme.Primary.green : BubuTheme.Text.tertiary)
                    .frame(width: 60)
                }

                Spacer().frame(width: 56)

                // 右侧：我的
                Button {
                    selectedTab = .profile
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: selectedTab == .profile ? "person.fill" : "person")
                            .font(.system(size: 18))
                        Text("我的")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == .profile ? BubuTheme.Primary.green : BubuTheme.Text.tertiary)
                    .frame(width: 60)
                }
            }
            .frame(height: 56)

            // + 按钮（浮在凹口上方）
            Button(action: onAddTap) {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(BubuTheme.Text.onPrimary)
                    .frame(width: 48, height: 48)
                    .background(BubuTheme.Primary.green)
                    .clipShape(Circle())
                    .shadow(color: BubuTheme.Primary.green.opacity(0.4), radius: 8, y: 2)
            }
            .offset(y: -24)
        }
        .padding(.bottom, 24)
    }
}

// MARK: - 添加搜索 Sheet（从底导 + 触发）

struct AddPlaceSearchSheet: View {
    @EnvironmentObject var container: AppContainer
    let onSelect: (MapPlace) -> Void
    @State private var query = ""
    @State private var results: [MapPlace] = []
    @State private var isSearching = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 搜索框常驻顶部
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundStyle(BubuTheme.Text.tertiary)
                    TextField("搜索地点", text: $query)
                        .font(BubuFont.body)
                        .foregroundStyle(BubuTheme.Text.ink)
                        .onSubmit { doSearch() }
                    if !query.isEmpty {
                        Button { query = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(BubuTheme.Text.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(BubuTheme.Surface.surface1)
                .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

                Divider().background(BubuTheme.Text.tertiary).padding(.horizontal, 16)

                // 内容区
                if isSearching {
                    Spacer()
                    ProgressView().tint(BubuTheme.Primary.green)
                    Spacer()
                } else if !results.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { place in
                                Button { onSelect(place); dismiss() } label: {
                                    PlaceSearchRow(place: place)
                                }
                                .buttonStyle(.plain)
                                Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                } else if results.isEmpty && !query.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 60)
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(BubuTheme.Text.tertiary)
                        Text("没有找到「\(query)」")
                            .font(BubuFont.titleSM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                        Text("换个关键词试试")
                            .font(BubuFont.caption)
                            .foregroundStyle(BubuTheme.Text.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(BubuTheme.Primary.green.opacity(0.6))
                        Text("搜一家店，开始记录")
                            .font(BubuFont.titleSM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                        Text("试试搜「火锅」「咖啡」「甜品」")
                            .font(BubuFont.caption)
                            .foregroundStyle(BubuTheme.Text.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(BubuTheme.Surface.space)
            .navigationTitle("添加地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func doSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        let center = container.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
        Task {
            do {
                results = try await container.mapService.searchPlaces(
                    query: q,
                    region: MapRegion(center: center, radius: 30000),
                    filters: nil
                )
            } catch { results = [] }
            isSearching = false
        }
    }
}

// MARK: - 搜索结果行（添加面板专用）

struct PlaceSearchRow: View {
    let place: MapPlace

    var body: some View {
        HStack(spacing: 12) {
            // 类别图标
            Image(systemName: categoryIcon)
                .font(.system(size: 15))
                .foregroundStyle(categoryColor)
                .frame(width: 28, height: 28)
                .background(categoryColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // 名称 + 地址
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(BubuFont.titleSM)
                    .foregroundStyle(BubuTheme.Text.ink)
                    .lineLimit(1)
                if let addr = place.address {
                    Text(addr)
                        .font(.system(size: 11))
                        .foregroundStyle(BubuTheme.Text.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 高德评分 + 距离
            VStack(alignment: .trailing, spacing: 3) {
                if let rating = place.rating {
                    HStack(spacing: 3) {
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(BubuTheme.Semantic.visitedNeutral)
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(BubuTheme.Semantic.visitedNeutral)
                    }
                }
                if let dist = place.distance {
                    Text(formatDistance(dist))
                        .font(.system(size: 11))
                        .foregroundStyle(BubuTheme.Text.tertiary)
                }
            }
        }
        .padding(.vertical, 14)
    }

    private var categoryIcon: String {
        guard let cat = place.category else { return "mappin" }
        if cat.contains("餐饮") || cat.contains("餐厅") { return "fork.knife" }
        if cat.contains("咖啡") || cat.contains("茶") { return "cup.and.saucer.fill" }
        if cat.contains("酒吧") { return "wineglass.fill" }
        if cat.contains("购物") { return "bag.fill" }
        if cat.contains("公园") { return "leaf.fill" }
        if cat.contains("景点") || cat.contains("风景") { return "mountain.2.fill" }
        if cat.contains("博物馆") || cat.contains("展览") { return "building.columns.fill" }
        if cat.contains("住宿") || cat.contains("酒店") { return "bed.double.fill" }
        if cat.contains("娱乐") { return "sparkles" }
        if cat.contains("运动") { return "figure.run" }
        return "mappin"
    }
    private var categoryColor: Color {
        guard let cat = place.category else { return BubuTheme.Text.tertiary }
        if cat.contains("餐饮") || cat.contains("餐厅") { return .orange }
        if cat.contains("咖啡") || cat.contains("茶") { return .brown }
        if cat.contains("酒吧") { return .purple }
        if cat.contains("购物") { return .blue }
        if cat.contains("公园") { return .mint }
        if cat.contains("景点") { return .green }
        return BubuTheme.Primary.green
    }
}

private func formatDistance(_ meters: Double) -> String {
    if meters < 1000 { return "\(Int(meters))m" }
    let km = meters / 1000
    return String(format: "%.1fkm", km)
}