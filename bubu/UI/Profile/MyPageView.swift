import SwiftUI
import PhotosUI
import CoreLocation
import UIKit
import AVFoundation

struct MyPageView: View {
    @EnvironmentObject var container: AppContainer

    @State private var selectedTab: MyArchiveTab = .cityImprints
    @State private var stats = UserStats.empty
    @State private var cities: [CityMemorySummary] = []
    @State private var navigationPath = NavigationPath()
    @State private var searchText = ""
    @State private var showingSearch = false
    @State private var showingMenu = false

    @State private var avatarImage: UIImage?
    @State private var backgroundImage: UIImage?
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var backgroundPickerItem: PhotosPickerItem?
    @State private var showingAvatarPicker = false
    @State private var showingBackgroundPicker = false
    @State private var currentFocusCoordinate: CLLocationCoordinate2D?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    profileHero
                    tabSwitcher

                    if selectedTab == .progress {
                        progressView
                    } else {
                        cityImprintsView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .background(BubuTheme.Surface.space.ignoresSafeArea())
            .onAppear {
                loadProfileAssets()
                reloadArchive()
                updateCurrentFocusCoordinate()
            }
            .sheet(isPresented: $showingSearch) {
                ArchiveSearchSheet(
                    query: $searchText,
                    cities: filteredCities,
                    onSelect: { city in
                        showingSearch = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            navigationPath.append(city.name)
                        }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .confirmationDialog("更多", isPresented: $showingMenu, titleVisibility: .hidden) {
                Button("更换头像") { showingAvatarPicker = true }
                Button("更换背景图") { showingBackgroundPicker = true }
                Button("导入记录") {}
                Button("取消", role: .cancel) {}
            }
            .photosPicker(isPresented: $showingAvatarPicker, selection: $avatarPickerItem, matching: .images)
            .photosPicker(isPresented: $showingBackgroundPicker, selection: $backgroundPickerItem, matching: .images)
            .onChange(of: avatarPickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadPickedImage(from: newValue, for: .avatar) }
            }
            .onChange(of: backgroundPickerItem) { _, newValue in
                guard let newValue else { return }
                Task { await loadPickedImage(from: newValue, for: .background) }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { cityName in
                if let city = city(named: cityName) {
                    CityGalleryView(city: city)
                } else {
                    Color.clear
                        .background(BubuTheme.Surface.space.ignoresSafeArea())
                }
            }
        }
    }

    private var profileHero: some View {
        ZStack(alignment: .top) {
            heroBackground
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay {
                    LinearGradient(
                        colors: [
                            .clear,
                            BubuTheme.Surface.space.opacity(0.32),
                            BubuTheme.Surface.space.opacity(0.78)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .frame(height: 104)
                        .mask(
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.18), .black],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }
                .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .onTapGesture {
                    showingBackgroundPicker = true
                }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    headerActionButton(systemName: "magnifyingglass") {
                        showingSearch = true
                    }
                    headerActionButton(systemName: "line.3.horizontal.decrease") {
                        showingMenu = true
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                HStack(alignment: .bottom, spacing: 14) {
                    avatarButton(size: 78)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(primaryCityName)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        HStack(spacing: 14) {
                            archiveStat(value: "\(stats.placesVisited)", label: "去过")
                            archiveStat(value: "\(stats.placesWanted)", label: "想去")
                            archiveStat(value: "\(stats.citiesVisited)", label: "城市")
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
            }
            .frame(height: 260)
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            archiveTabButton(.cityImprints, title: "城市印记")
            archiveTabButton(.progress, title: "点亮进度")
        }
        .padding(6)
        .contentShape(Rectangle())
        .background(
            Capsule()
                .fill(BubuTheme.Surface.surface1)
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .zIndex(10)
    }

    private var progressView: some View {
        VStack(spacing: 18) {
            RotatingGlobeCard(
                places: allPlaceDots,
                focusCoordinate: currentFocusCoordinate,
                stats: stats
            )

            HStack(spacing: 12) {
                archiveInfoCard(
                    title: "最近点亮",
                    value: recentHighlightTitle,
                    subtitle: "最近一次留下痕迹的城市"
                )
                archiveInfoCard(
                    title: "最熟悉",
                    value: topCityName,
                    subtitle: "目前点亮最多的城市"
                )
            }
        }
    }

    private var cityImprintsView: some View {
        VStack(spacing: 16) {
            if cities.isEmpty {
                emptyCityState
            } else {
                ForEach(cities) { city in
                    NavigationLink(value: city.name) {
                        CityPostcardCard(city: city)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyCityState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(BubuTheme.Primary.green)
            Text("还没有城市印记")
                .font(BubuFont.titleLG)
                .foregroundStyle(BubuTheme.Text.ink)
            Text("去点亮几个地方，城市明信片就会慢慢长出来。")
                .font(BubuFont.bodySM)
                .foregroundStyle(BubuTheme.Text.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var filteredCities: [CityMemorySummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return cities }
        return cities.filter { city in
            city.name.localizedCaseInsensitiveContains(q) ||
            city.entries.contains(where: { $0.placeName.localizedCaseInsensitiveContains(q) || ($0.note?.localizedCaseInsensitiveContains(q) ?? false) })
        }
    }

    private var allPlaceDots: [GlobePlaceDot] {
        cities.flatMap { city in
            city.entries.map {
                GlobePlaceDot(
                    id: $0.id,
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    intensity: $0.status == .visitedGood ? 1 : ($0.status == .visitedNeutral ? 0.72 : ($0.status == .visitedBad ? 0.56 : 0.38))
                )
            }
        }
    }

    private var recentHighlightTitle: String {
        cities
            .flatMap(\.entries)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .first?
            .cityName ?? "还没有"
    }

    private var topCityName: String {
        cities.max(by: { $0.litCount < $1.litCount })?.name ?? "还没有"
    }

    private var heroBackground: some View {
        Group {
            if let backgroundImage {
                Image(uiImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: "6B737C"),
                        Color(hex: "A9AFB4"),
                        Color(hex: "E4E1DB")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 160, style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(width: 280, height: 180)
                        .blur(radius: 10)
                        .offset(x: 48, y: -12)
                }
            }
        }
    }

    private func avatarButton(size: CGFloat) -> some View {
        Button {
            showingAvatarPicker = true
        } label: {
            avatarArtwork(size: size)
        }
        .buttonStyle(.plain)
    }

    private func avatarArtwork(size: CGFloat) -> some View {
        Group {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(hex: "D9DCE5"), Color(hex: "8D93A7")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.32, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .stroke(.white.opacity(0.9), lineWidth: 4)
        )
    }

    private func archiveStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(BubuFont.caption)
                .foregroundStyle(.white.opacity(0.66))
        }
    }

    private func archiveTabButton(_ tab: MyArchiveTab, title: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) {
                selectedTab = tab
            }
        } label: {
            Text(title)
                .font(BubuFont.titleSM)
                .foregroundStyle(selectedTab == tab ? BubuTheme.Text.ink : BubuTheme.Text.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    Capsule()
                        .fill(selectedTab == tab ? .white.opacity(0.11) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                withAnimation(.spring(duration: 0.25)) {
                    selectedTab = tab
                }
            }
        )
    }

    private func archiveInfoCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(BubuFont.caption)
                .foregroundStyle(BubuTheme.Text.tertiary)
            Text(value)
                .font(BubuFont.titleLG)
                .foregroundStyle(BubuTheme.Text.ink)
                .lineLimit(1)
            Text(subtitle)
                .font(BubuFont.bodySM)
                .foregroundStyle(BubuTheme.Text.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func headerActionButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 34, height: 34)
                .background { BubuGlassCircle() }
        }
        .buttonStyle(.plain)
    }

    private var primaryCityName: String {
        cities.first?.name ?? "步步"
    }

    private func reloadArchive() {
        let repo = container.placeRepository
        let userPlaces = repo.fetchUserPlaces()
        let summaries = CityMemorySummary.build(from: userPlaces)
        cities = summaries
        stats = UserStats(
            placesVisited: repo.countVisited(),
            placesWanted: repo.countWanted(),
            citiesVisited: Set(summaries.map(\.name)).count,
            collections: repo.countFolders(),
            explorationPercent: min(repo.countVisited() * 5, 100)
        )
    }

    private func updateCurrentFocusCoordinate() {
        currentFocusCoordinate = container.locationManager.currentLocation?.coordinate
            ?? allPlaceDots.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func city(named name: String) -> CityMemorySummary? {
        cities.first { $0.name == name }
    }

    private func loadProfileAssets() {
        avatarImage = ProfileAssetStore.load(.avatar)
        backgroundImage = ProfileAssetStore.load(.background)
    }

    private func loadPickedImage(from item: PhotosPickerItem, for kind: ProfileAssetStore.AssetKind) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let prepared = image.preparingThumbnail(of: kind == .avatar ? CGSize(width: 320, height: 320) : CGSize(width: 1600, height: 900)) ?? image
        ProfileAssetStore.save(prepared, kind: kind)
        await MainActor.run {
            switch kind {
            case .avatar: avatarImage = prepared
            case .background: backgroundImage = prepared
            }
        }
    }
}

private enum MyArchiveTab {
    case progress
    case cityImprints
}

private struct RotatingGlobeCard: View {
    let places: [GlobePlaceDot]
    let focusCoordinate: CLLocationCoordinate2D?
    let stats: UserStats

    @State private var rotationX: Double = -0.22
    @State private var rotationY: Double = 0.38
    @State private var baseRotationX: Double = -0.22
    @State private var baseRotationY: Double = 0.38

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("点亮进度")
                        .font(BubuFont.titleLG)
                        .foregroundStyle(BubuTheme.Text.ink)
                    Text("转一转，看看你的生活地图亮到了哪里。")
                        .font(BubuFont.bodySM)
                        .foregroundStyle(BubuTheme.Text.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(stats.placesVisited + stats.placesWanted)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(BubuTheme.Primary.green)
                    Text("总地点")
                        .font(BubuFont.caption)
                        .foregroundStyle(BubuTheme.Text.tertiary)
                }
            }

            GeometryReader { proxy in
                let size = proxy.size
                let globeSize = min(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(hex: "1E2335"),
                                    Color(hex: "0E1324")
                                ],
                                center: .center,
                                startRadius: 12,
                                endRadius: globeSize * 0.55
                            )
                        )
                        .frame(width: globeSize, height: globeSize)

                    Circle()
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                        .frame(width: globeSize, height: globeSize)

                    GlobeGrid(size: globeSize)
                        .rotationEffect(.radians(rotationY))
                        .opacity(0.36)

                    ForEach(projectedDots(size: globeSize, center: center)) { dot in
                        Circle()
                            .fill(BubuTheme.Primary.green)
                            .frame(width: dot.size, height: dot.size)
                            .shadow(color: BubuTheme.Primary.green.opacity(0.42), radius: dot.size * 0.8)
                            .position(dot.position)
                            .opacity(dot.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let dx = value.translation.width / 180
                            let dy = value.translation.height / 220
                            rotationY = baseRotationY + dx
                            rotationX = max(-0.65, min(0.65, baseRotationX - dy))
                        }
                        .onEnded { _ in
                            baseRotationX = rotationX
                            baseRotationY = rotationY
                        }
                )
            }
            .frame(height: 320)
            .padding(.top, 4)

            HStack(spacing: 10) {
                globePill(title: "去过", value: "\(stats.placesVisited)")
                globePill(title: "想去", value: "\(stats.placesWanted)")
                globePill(title: "城市", value: "\(stats.citiesVisited)")
            }
        }
        .padding(22)
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onAppear {
            if let focusCoordinate {
                let lat = focusCoordinate.latitude * .pi / 180
                let lon = focusCoordinate.longitude * .pi / 180
                rotationX = -lat * 0.65
                rotationY = -lon + 0.45
                baseRotationX = rotationX
                baseRotationY = rotationY
            }
        }
    }

    private func globePill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BubuFont.caption)
                .foregroundStyle(BubuTheme.Text.tertiary)
            Text(value)
                .font(BubuFont.titleMD)
                .foregroundStyle(BubuTheme.Text.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BubuTheme.Surface.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func projectedDots(size: CGFloat, center: CGPoint) -> [ProjectedDot] {
        places.compactMap { dot in
            let lat = dot.latitude * .pi / 180
            let lon = dot.longitude * .pi / 180

            let x0 = cos(lat) * sin(lon)
            let y0 = sin(lat)
            let z0 = cos(lat) * cos(lon)

            let x1 = x0 * cos(rotationY) + z0 * sin(rotationY)
            let z1 = -x0 * sin(rotationY) + z0 * cos(rotationY)
            let y1 = y0 * cos(rotationX) - z1 * sin(rotationX)
            let z2 = y0 * sin(rotationX) + z1 * cos(rotationX)

            guard z2 > -0.18 else { return nil }

            let radius = size * 0.5
            let perspective = 0.84 + (z2 * 0.22)
            let px = center.x + CGFloat(x1) * radius * perspective
            let py = center.y - CGFloat(y1) * radius * perspective
            let sizeValue = CGFloat(6 + dot.intensity * 3 + max(z2, 0) * 3)
            let opacity = 0.38 + max(z2, 0) * 0.62

            return ProjectedDot(
                id: dot.id,
                position: CGPoint(x: px, y: py),
                size: sizeValue,
                opacity: opacity
            )
        }
    }
}

private struct GlobeGrid: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2
            let color = BubuTheme.Text.tertiary.opacity(0.16)

            for ratio in stride(from: -0.6, through: 0.6, by: 0.3) {
                var path = Path()
                let ellipseHeight = radius * (1 - abs(ratio) * 0.32)
                path.addEllipse(in: CGRect(
                    x: center.x - radius * 0.98,
                    y: center.y - ellipseHeight * 0.5 + radius * CGFloat(ratio) * 0.42,
                    width: radius * 1.96,
                    height: ellipseHeight
                ))
                context.stroke(path, with: .color(color), lineWidth: 1)
            }

            for ratio in stride(from: -0.6, through: 0.6, by: 0.3) {
                var path = Path()
                path.move(to: CGPoint(x: center.x + radius * CGFloat(ratio), y: center.y - radius))
                path.addCurve(
                    to: CGPoint(x: center.x + radius * CGFloat(ratio), y: center.y + radius),
                    control1: CGPoint(x: center.x + radius * CGFloat(ratio) * 1.35, y: center.y - radius * 0.34),
                    control2: CGPoint(x: center.x + radius * CGFloat(ratio) * 1.35, y: center.y + radius * 0.34)
                )
                context.stroke(path, with: .color(color), lineWidth: 1)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct CityPostcardCard: View {
    let city: CityMemorySummary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(BubuTheme.Surface.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )

            VStack(spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    stampBoard

                    VStack(alignment: .leading, spacing: 8) {
                        Text(city.name)
                            .font(.system(size: 24, weight: .semibold, design: .serif))
                            .foregroundStyle(BubuTheme.Text.ink)
                            .lineLimit(2)

                        Text(cityArchiveCode)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(BubuTheme.Text.tertiary)

                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }

                HStack {
                    Text("已点亮 \(city.litCount) / \(city.totalCount)")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(BubuTheme.Text.secondary)
                    Spacer()
                    Text(cityYearLabel)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundStyle(BubuTheme.Text.tertiary)
                }
            }
            .padding(20)
        }
        .frame(height: 214)
    }

    private var stampBoard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "F3E9D7"), Color(hex: "E7DBC6")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 10) {
                motifHeader
                motifCanvas
                motifFooter
            }
            .padding(14)
        }
        .frame(width: 128, height: 146)
    }

    private var motifHeader: some View {
        HStack {
            Text(cityCountryLabel.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.black.opacity(0.52))
            Spacer()
            Text(cityYearLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.black.opacity(0.52))
        }
    }

    private var motifCanvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(0.24))

            Group {
                if let image = city.heroImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.26)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                CityStampMotif(cityName: city.name)
                    .padding(10)
            }
        }
        .frame(height: 74)
    }

    private var motifFooter: some View {
        HStack {
            Text("NO. \(cityArchiveCode)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Color.black.opacity(0.54))
            Spacer()
        }
    }

    private var cityArchiveCode: String {
        let base = abs(city.name.hashValue)
        return String(format: "%04d", base % 10_000)
    }

    private var cityCountryLabel: String {
        switch city.name {
        case "上海", "北京", "厦门", "广州", "深圳", "杭州", "成都", "重庆", "苏州", "南京", "武汉", "西安", "长沙", "青岛", "天津", "宁波", "福州", "大连":
            return "China"
        case "东京", "大阪", "京都":
            return "Japan"
        case "香港":
            return "Hong Kong"
        default:
            return "City"
        }
    }

    private var cityYearLabel: String {
        let earliest = city.entries.compactMap(\.date).min()
        return earliest.map {
            String(Calendar.current.component(.year, from: $0))
        } ?? "Now"
    }
}

private struct CityGalleryView: View {
    let city: CityMemorySummary
    @State private var selectedEntryID: UUID?
    @StateObject private var audioPlayer = AudioPreviewPlayer()

    var body: some View {
        ZStack {
            BubuTheme.Surface.space
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(city.name)
                            .font(.system(size: 28, weight: .medium, design: .serif))
                            .foregroundStyle(BubuTheme.Text.ink)

                        Text(cityPoem)
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(BubuTheme.Text.secondary)
                            .lineSpacing(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)

                    galleryCanvas
                        .padding(.horizontal, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("地点轨道")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(BubuTheme.Text.tertiary)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 14) {
                                ForEach(city.entries) { entry in
                                    Button {
                                        withAnimation(.spring(duration: 0.28)) {
                                            selectedEntryID = entry.id
                                        }
                                    } label: {
                                        CityGalleryRailItem(
                                            entry: entry,
                                            isSelected: selectedEntry?.id == entry.id,
                                            fallbackImage: city.heroImage
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        }
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            selectedEntryID = selectedEntryID ?? city.entries.first?.id
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var selectedEntry: CityMemoryEntry? {
        city.entries.first { $0.id == selectedEntryID } ?? city.entries.first
    }

    private var galleryCanvas: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "171E31"),
                            Color(hex: "111726")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(.white.opacity(0.06), lineWidth: 1)
                )

            if let entry = selectedEntry {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(entryDisplayTitle(for: entry))
                                .font(.system(size: 17, weight: .medium, design: .serif))
                                .foregroundStyle(BubuTheme.Text.tertiary)

                            Text(entryDisplayNote(for: entry))
                                .font(.system(size: 24, weight: .regular, design: .serif))
                                .foregroundStyle(BubuTheme.Text.ink)
                                .lineSpacing(10)
                                .fixedSize(horizontal: false, vertical: true)

                            if let url = entry.voiceMemoURL {
                                Button {
                                    audioPlayer.togglePlayback(url: url)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: audioPlayer.isPlaying ? "stop.fill" : "waveform")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(audioPlayer.isPlaying ? "正在播放语音" : "播放语音 · \(entry.voiceDurationLabel)")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                    }
                                    .foregroundStyle(BubuTheme.Primary.green)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .background(BubuTheme.Primary.green.opacity(0.10))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer(minLength: 0)

                        if let date = entry.date {
                            Text(entryFooter(for: entry, date: date))
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(BubuTheme.Text.tertiary)
                                .lineSpacing(6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 26)
                    .padding(.trailing, 152)

                    VStack {
                        Spacer(minLength: 56)
                        HStack {
                            Spacer()
                            galleryFeatureCard(entry: entry)
                        }
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(height: 510)
    }

    private func galleryFeatureCard(entry: CityMemoryEntry) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image = entry.heroImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if let fallback = city.heroImage {
                    Image(uiImage: fallback)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(hex: "7E8A9B"), Color(hex: "495669")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 186, height: 268)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.92), lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.20), radius: 22, y: 12)

            if entry.hasVoiceMemo && entry.heroImage == nil {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                    Text(entry.voiceDurationLabel)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(.black.opacity(0.28))
                .clipShape(Capsule())
                .padding(16)
            }
        }
    }

    private var cityPoem: String {
        let visited = city.entries.filter { $0.status != .wantToGo }
        let wanted = city.entries.filter { $0.status == .wantToGo }
        let favoriteNames = Array(visited.prefix(2).map(\.placeName))
        let wantedNames = Array(wanted.prefix(1).map(\.placeName))

        if !favoriteNames.isEmpty && !wantedNames.isEmpty {
            return "你把 \(favoriteNames.joined(separator: "、")) 留在了 \(city.name) 的日常里，\n而 \(wantedNames[0]) 还在等下一次认真经过。"
        }

        if !favoriteNames.isEmpty {
            return "\(city.name) 被你点亮成了 \(favoriteNames.joined(separator: "、")) 和更多熟悉的停留，\n像一册慢慢写满的城市明信片。"
        }

        if !wantedNames.isEmpty {
            return "\(wantedNames[0]) 让这座城先亮起了一角，\n接下来你会慢慢把 \(city.name) 走成自己的路线。"
        }

        return "这些留下来的片刻，正在把 \(city.name) 变成一座只属于你的城市展册。"
    }

    private func entryDisplayTitle(for entry: CityMemoryEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        if let date = entry.date {
            return "\(entry.placeName) · \(formatter.string(from: date))"
        }
        return entry.placeName
    }

    private func entryDisplayNote(for entry: CityMemoryEntry) -> String {
        if let note = entry.note, !note.isEmpty {
            return note
        }
        if entry.hasVoiceMemo {
            return "那次停留没有写下文字，\n只把声音留在了这里。"
        }
        return "这一次没有留下太多字句，\n只是把这个地方收进了 \(city.name) 的记忆里。"
    }

    private func entryFooter(for entry: CityMemoryEntry, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        var pieces = [formatter.string(from: date)]
        if entry.status == .wantToGo {
            pieces.append("想去")
        } else {
            pieces.append("已点亮")
        }
        return pieces.joined(separator: "  ·  ")
    }
}

private struct CityGalleryRailItem: View {
    let entry: CityMemoryEntry
    let isSelected: Bool
    let fallbackImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image = entry.heroImage ?? fallbackImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(hex: "637188"), Color(hex: "3E495A")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(width: 86, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? BubuTheme.Primary.green.opacity(0.8) : .white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )

            Text(entry.placeName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? BubuTheme.Text.ink : BubuTheme.Text.secondary)
                .lineLimit(2)
        }
        .frame(width: 86, alignment: .leading)
    }
}

private struct CityStampMotif: View {
    let cityName: String

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                switch motifKind {
                case .harbor:
                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.66))
                        path.addCurve(
                            to: CGPoint(x: size.width * 0.92, y: size.height * 0.62),
                            control1: CGPoint(x: size.width * 0.34, y: size.height * 0.48),
                            control2: CGPoint(x: size.width * 0.66, y: size.height * 0.74)
                        )
                    }
                    .stroke(Color(hex: "294F7A"), style: StrokeStyle(lineWidth: 3, lineCap: .round))

                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.24, y: size.height * 0.26))
                        path.addLine(to: CGPoint(x: size.width * 0.24, y: size.height * 0.72))
                        path.move(to: CGPoint(x: size.width * 0.24, y: size.height * 0.30))
                        path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.30))
                    }
                    .stroke(Color(hex: "D86B3A"), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))

                case .rings:
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .stroke(index == 0 ? Color(hex: "C77A49") : Color(hex: "2D4C78"), lineWidth: index == 0 ? 3 : 1.8)
                            .frame(width: size.width * (0.24 + CGFloat(index) * 0.20))
                    }

                case .axis:
                    VStack(spacing: size.height * 0.08) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(hex: "1B3B69"))
                                .frame(width: size.width * 0.66, height: 5)
                        }
                    }
                    .rotationEffect(.degrees(-18))

                case .torii:
                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.24, y: size.height * 0.66))
                        path.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.66))
                        path.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.66))
                        path.addLine(to: CGPoint(x: size.width * 0.36, y: size.height * 0.28))
                        path.move(to: CGPoint(x: size.width * 0.70, y: size.height * 0.66))
                        path.addLine(to: CGPoint(x: size.width * 0.64, y: size.height * 0.28))
                        path.move(to: CGPoint(x: size.width * 0.20, y: size.height * 0.28))
                        path.addLine(to: CGPoint(x: size.width * 0.80, y: size.height * 0.28))
                    }
                    .stroke(Color(hex: "C34735"), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var motifKind: MotifKind {
        switch cityName {
        case "上海", "厦门", "香港":
            return .harbor
        case "北京":
            return .rings
        case "东京", "大阪":
            return .axis
        case "京都":
            return .torii
        default:
            return .axis
        }
    }

    private enum MotifKind {
        case harbor
        case rings
        case axis
        case torii
    }
}

private struct ArchiveSearchSheet: View {
    @Binding var query: String
    let cities: [CityMemorySummary]
    let onSelect: (CityMemorySummary) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField("搜索城市、地点、记录", text: $query)
                    .font(BubuFont.body)
                    .foregroundStyle(BubuTheme.Text.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cities) { city in
                            Button {
                                onSelect(city)
                            } label: {
                                HStack(spacing: 12) {
                                    thumbnail(for: city)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(city.name)
                                            .font(BubuFont.titleSM)
                                            .foregroundStyle(BubuTheme.Text.ink)
                                        Text("已点亮 \(city.litCount) / \(city.totalCount)")
                                            .font(BubuFont.caption)
                                            .foregroundStyle(BubuTheme.Text.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(14)
                                .background(BubuTheme.Surface.surface1)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .padding(.top, 16)
            .background(BubuTheme.Surface.space)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func thumbnail(for city: CityMemorySummary) -> some View {
        Group {
            if let image = city.heroImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(hex: "4F5C72"), Color(hex: "9AA7B8")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct GlobePlaceDot: Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let intensity: Double
}

private struct ProjectedDot: Identifiable {
    let id: UUID
    let position: CGPoint
    let size: CGFloat
    let opacity: Double
}

private struct CityMemorySummary: Identifiable {
    let id = UUID()
    let name: String
    let totalCount: Int
    let litCount: Int
    let wantCount: Int
    let heroImage: UIImage?
    let entries: [CityMemoryEntry]

    static func build(from userPlaces: [CDUserPlace]) -> [CityMemorySummary] {
        let grouped = Dictionary(grouping: userPlaces) { userPlace in
            inferredCity(from: userPlace)
        }

        return grouped.map { cityName, places in
            let entries = places.map(CityMemoryEntry.init(userPlace:)).sorted {
                ($0.date ?? .distantPast) > ($1.date ?? .distantPast)
            }
            let heroImage = entries.first(where: { $0.heroImage != nil })?.heroImage
            let litCount = entries.filter { $0.status != .wantToGo }.count
            let wantCount = entries.filter { $0.status == .wantToGo }.count
            return CityMemorySummary(
                name: cityName,
                totalCount: entries.count,
                litCount: litCount,
                wantCount: wantCount,
                heroImage: heroImage,
                entries: entries
            )
        }
        .sorted { lhs, rhs in
            if lhs.litCount != rhs.litCount { return lhs.litCount > rhs.litCount }
            return lhs.totalCount > rhs.totalCount
        }
    }

    fileprivate static func inferredCity(from userPlace: CDUserPlace) -> String {
        let address = userPlace.place?.address ?? ""
        let name = userPlace.place?.name ?? ""
        let candidates = [
            "上海", "北京", "厦门", "广州", "深圳", "杭州", "成都", "重庆", "苏州",
            "南京", "武汉", "西安", "长沙", "青岛", "天津", "宁波", "福州", "大连", "香港", "东京", "大阪", "京都"
        ]
        if let hit = candidates.first(where: { address.contains($0) || name.contains($0) }) {
            return hit
        }

        let districtMap: [String: String] = [
            "黄浦": "上海", "徐汇": "上海", "静安": "上海", "长宁": "上海", "普陀": "上海",
            "杨浦": "上海", "虹口": "上海", "浦东": "上海", "闵行": "上海", "宝山": "上海",
            "思明": "厦门", "湖里": "厦门", "集美": "厦门", "海淀": "北京", "朝阳": "北京"
        ]
        if let mapped = districtMap.first(where: { address.contains($0.key) })?.value {
            return mapped
        }

        let coordinate = CLLocationCoordinate2D(
            latitude: userPlace.place?.latitude ?? 0,
            longitude: userPlace.place?.longitude ?? 0
        )
        if let nearest = nearestKnownCity(to: coordinate) {
            return nearest
        }

        return "未命名"
    }

    private static func nearestKnownCity(to coordinate: CLLocationCoordinate2D) -> String? {
        guard coordinate.latitude != 0 || coordinate.longitude != 0 else { return nil }

        let knownCities: [(name: String, lat: Double, lon: Double)] = [
            ("上海", 31.2304, 121.4737),
            ("北京", 39.9042, 116.4074),
            ("厦门", 24.4798, 118.0894),
            ("广州", 23.1291, 113.2644),
            ("深圳", 22.5431, 114.0579),
            ("杭州", 30.2741, 120.1551),
            ("成都", 30.5728, 104.0668),
            ("重庆", 29.5630, 106.5516),
            ("苏州", 31.2989, 120.5853),
            ("南京", 32.0603, 118.7969),
            ("武汉", 30.5928, 114.3055),
            ("西安", 34.3416, 108.9398),
            ("长沙", 28.2282, 112.9388),
            ("青岛", 36.0671, 120.3826),
            ("天津", 39.0842, 117.2000),
            ("宁波", 29.8683, 121.5440),
            ("福州", 26.0745, 119.2965),
            ("大连", 38.9140, 121.6147),
            ("香港", 22.3193, 114.1694),
            ("东京", 35.6762, 139.6503),
            ("大阪", 34.6937, 135.5023),
            ("京都", 35.0116, 135.7681)
        ]

        let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = knownCities
            .map { city in
                let location = CLLocation(latitude: city.lat, longitude: city.lon)
                return (city.name, current.distance(from: location))
            }
            .min(by: { $0.1 < $1.1 })

        guard let nearest, nearest.1 < 120_000 else { return nil }
        return nearest.0
    }
}

private struct CityMemoryEntry: Identifiable {
    let id: UUID
    let cityName: String
    let placeName: String
    let note: String?
    let date: Date?
    let status: PlaceStatus
    let mood: MoodTag?
    let coordinate: CLLocationCoordinate2D
    let heroImage: UIImage?
    let hasVoiceMemo: Bool
    let voiceMemoURL: URL?
    let voiceDuration: TimeInterval?

    init(userPlace: CDUserPlace) {
        id = userPlace.id ?? UUID()
        cityName = CityMemorySummary.inferredCity(from: userPlace)
        placeName = userPlace.place?.name ?? "未命名地点"
        note = userPlace.reviewText
        date = userPlace.visitDate ?? userPlace.updatedAt ?? userPlace.createdAt
        status = PlaceStatus(rawValue: userPlace.statusValue) ?? .wantToGo
        mood = userPlace.mood.flatMap(MoodTag.init(rawValue:))
        coordinate = CLLocationCoordinate2D(
            latitude: userPlace.place?.latitude ?? 0,
            longitude: userPlace.place?.longitude ?? 0
        )
        let sortedMedia = (userPlace.media ?? []).sorted {
            if let lhs = $0.createdAt, let rhs = $1.createdAt, lhs != rhs {
                return lhs > rhs
            }
            return $0.sortOrder < $1.sortOrder
        }
        heroImage = sortedMedia.first(where: { $0.typeValue == MediaType.photo.rawValue }).flatMap { media in
            if let data = media.thumbnailData { return UIImage(data: data) }
            if let url = media.localFileURL, let data = try? Data(contentsOf: url) { return UIImage(data: data) }
            return nil
        }
        let voiceMedia = sortedMedia.first(where: { $0.typeValue == MediaType.voiceNote.rawValue })
        voiceMemoURL = voiceMedia?.localFileURL
        voiceDuration = voiceMemoURL.flatMap { url in
            let asset = AVURLAsset(url: url)
            let seconds = CMTimeGetSeconds(asset.duration)
            return seconds.isFinite ? seconds : nil
        }
        hasVoiceMemo = voiceMemoURL != nil
    }

    var voiceDurationLabel: String {
        guard let voiceDuration else { return "语音" }
        let seconds = max(1, Int(round(voiceDuration)))
        return "\(seconds)秒"
    }
}

private enum ProfileAssetStore {
    enum AssetKind: String {
        case avatar
        case background
    }

    private static func url(for kind: AssetKind) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("profile-\(kind.rawValue).jpg")
    }

    static func load(_ kind: AssetKind) -> UIImage? {
        let url = url(for: kind)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func save(_ image: UIImage, kind: AssetKind) {
        let url = url(for: kind)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let data = image.jpegData(compressionQuality: 0.84)
        try? data?.write(to: url, options: .atomic)
    }
}
