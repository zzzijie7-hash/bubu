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
    /// 地图刷新触发器：添加面板保存地点后 +1
    @Published var mapRefreshTrigger: Int = 0

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

        path.move(to: CGPoint(x: r, y: rect.minY))
        path.addLine(to: CGPoint(x: notchCenter.x - nr - 6, y: rect.minY))
        path.addArc(center: notchCenter, radius: nr + 6,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
                    radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                    radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: r, y: rect.maxY))
        path.addArc(center: CGPoint(x: r, y: rect.maxY - r),
                    radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
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
            Group {
                if appState.selectedTab == .explore {
                    ExploreMapView()
                } else {
                    MyPageView()
                }
            }

            VStack {
                Spacer()
                FloatingTabBar(selectedTab: $appState.selectedTab) {
                    showingAddSearch = true
                }
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingAddSearch) {
            AddPlaceSearchSheet()
        }
    }
}

// MARK: - 悬浮底栏

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let onAddTap: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            NotchedPill(notchRadius: 28)
                .fill(BubuTheme.Surface.surface1)
                .frame(width: 180, height: 56)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 4)

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

// MARK: - 添加搜索 Sheet（搜→就地标→打卡 一条龙）

struct AddPlaceSearchSheet: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MapPlace] = []
    @State private var isSearching = false

    // 展开的地点（点搜索结果后展开状态选择）
    @State private var expandingPlace: MapPlace?
    @State private var selectedStatus: PlaceStatus = .wantToGo
    // 笔记
    @State private var noteText: String = ""
    @State private var visitDate: Date = Date()
    // 保存中
    @State private var isSaving = false

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
                        Button {
                            query = ""; results = []
                            expandingPlace = nil
                        } label: {
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
                                VStack(spacing: 0) {
                                    // 搜索结果行
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            if expandingPlace?.id == place.id {
                                                expandingPlace = nil
                                            } else {
                                                expandingPlace = place
                                                selectedStatus = .wantToGo
                                                noteText = ""
                                            }
                                        }
                                    } label: {
                                        PlaceSearchRow(place: place)
                                    }
                                    .buttonStyle(.plain)

                                    // 展开：状态选择 + 笔记
                                    if expandingPlace?.id == place.id {
                                        VStack(alignment: .leading, spacing: 16) {
                                            // 状态选择
                                            HStack(spacing: 10) {
                                                ForEach(PlaceStatus.allCases, id: \.rawValue) { s in
                                                    Button {
                                                        withAnimation(.easeInOut(duration: 0.15)) {
                                                            selectedStatus = s
                                                        }
                                                    } label: {
                                                        VStack(spacing: 5) {
                                                            Image(systemName: statusIcon(for: s))
                                                                .font(.system(size: 16))
                                                            Text(s.displayName)
                                                                .font(.system(size: 10))
                                                        }
                                                        .foregroundStyle(selectedStatus == s ? .white : BubuTheme.Text.secondary)
                                                        .frame(maxWidth: .infinity)
                                                        .padding(.vertical, 10)
                                                        .background(RoundedRectangle(cornerRadius: BubuRadius.sm)
                                                            .fill(selectedStatus == s ? BubuTheme.colorForStatus(s) : BubuTheme.Surface.surface2))
                                                    }
                                                }
                                            }

                                            // 笔记（去过时才显示，想去直接保存）
                                            if selectedStatus != .wantToGo {
                                                VStack(alignment: .leading, spacing: 10) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: "pencil.line")
                                                            .font(.system(size: 13))
                                                            .foregroundStyle(BubuTheme.Text.tertiary)
                                                        Text("记录这一刻")
                                                            .font(BubuFont.titleSM)
                                                            .foregroundStyle(BubuTheme.Text.secondary)
                                                    }
                                                    TextField("写点感受…", text: $noteText, axis: .vertical)
                                                        .font(BubuFont.body)
                                                        .foregroundStyle(BubuTheme.Text.ink)
                                                        .padding(12)
                                                        .background(BubuTheme.Surface.surface2)
                                                        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.sm))
                                                        .frame(minHeight: 80)

                                                    HStack {
                                                        Image(systemName: "calendar")
                                                            .font(.system(size: 13))
                                                            .foregroundStyle(BubuTheme.Text.tertiary)
                                                        DatePicker("到访日期", selection: $visitDate, displayedComponents: .date)
                                                            .labelsHidden()
                                                            .colorScheme(.dark)
                                                    }
                                                }
                                            }

                                            // 保存按钮
                                            Button {
                                                savePlace(place)
                                            } label: {
                                                HStack {
                                                    if isSaving {
                                                        ProgressView().tint(BubuTheme.Text.onPrimary)
                                                    } else {
                                                        Text("标记完成").font(BubuFont.button)
                                                    }
                                                }
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(BubuTheme.colorForStatus(selectedStatus))
                                                .foregroundStyle(.white)
                                                .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
                                            }
                                            .disabled(isSaving)
                                        }
                                        .padding(16)
                                        .background(BubuTheme.Surface.surface1)
                                        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
                                        .padding(.horizontal, 16).padding(.bottom, 12)
                                    }
                                }
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
                            .font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                        Text("换个关键词试试").font(BubuFont.caption).foregroundStyle(BubuTheme.Text.tertiary)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Spacer().frame(height: 60)
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(BubuTheme.Primary.green.opacity(0.6))
                        Text("搜一家店，开始记录").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                        Text("试试搜「火锅」「咖啡」「甜品」").font(BubuFont.caption).foregroundStyle(BubuTheme.Text.tertiary)
                        Spacer()
                    }.frame(maxWidth: .infinity)
                }
            }
            .background(BubuTheme.Surface.space)
            .navigationTitle("添加地点").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
        }
    }

    private func doSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        expandingPlace = nil
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

    private func savePlace(_ mapPlace: MapPlace) {
        isSaving = true
        let folder = container.placeRepository.fetchFolders().first
        let up = container.placeRepository.addPlace(
            name: mapPlace.name,
            address: mapPlace.address,
            latitude: mapPlace.coordinate.latitude,
            longitude: mapPlace.coordinate.longitude,
            status: selectedStatus,
            folder: folder,
            sourceType: .manual,
            sourceURL: nil
        )
        // 去过的话，写入打卡记录
        if selectedStatus != .wantToGo {
            let mood = detectMood(from: noteText)
            container.placeRepository.checkIn(
                userPlace: up,
                mood: mood,
                rating: 0,
                note: noteText.isEmpty ? nil : noteText,
                visitDate: visitDate
            )
        }
        // 从结果列表移除
        withAnimation {
            results.removeAll { $0.id == mapPlace.id }
            expandingPlace = nil
        }
        // 通知地图刷新
        appState.mapRefreshTrigger += 1
        isSaving = false
    }

    private func detectMood(from text: String) -> MoodTag? {
        let lower = text.lowercased()
        if lower.contains("好") || lower.contains("棒") || lower.contains("赞") || lower.contains("推荐") { return .happy }
        if lower.contains("差") || lower.contains("难吃") || lower.contains("坑") || lower.contains("雷") { return .disappointed }
        if lower.contains("惬意") || lower.contains("舒服") || lower.contains("安静") { return .calm }
        return nil
    }

    private func statusIcon(for status: PlaceStatus) -> String {
        switch status {
        case .wantToGo: return "bookmark.fill"
        case .visitedGood: return "hand.thumbsup.fill"
        case .visitedBad: return "hand.thumbsdown.fill"
        case .visitedNeutral: return "checkmark.circle.fill"
        }
    }
}

// MARK: - 搜索结果行

struct PlaceSearchRow: View {
    let place: MapPlace

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: categoryIcon)
                .font(.system(size: 15))
                .foregroundStyle(categoryColor)
                .frame(width: 28, height: 28)
                .background(categoryColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

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