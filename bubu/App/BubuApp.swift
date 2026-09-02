import SwiftUI
import CoreLocation
import UIKit
import Combine
import PhotosUI
import AVFoundation
import MapKit

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
                .tint(BubuTheme.Primary.uiTint)
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
    @Published var hidesFloatingTabBar = false
    /// 地图刷新触发器：添加面板保存地点后 +1
    @Published var mapRefreshTrigger: Int = 0
    @Published var focusPlaceID: UUID?
    @Published var mapSearchCenter: CLLocationCoordinate2D?

    init() {
        self.isOnboardingComplete = UserDefaults.standard.bool(forKey: "onboarding_complete")
    }

    func completeOnboarding() {
        isOnboardingComplete = true
    }
}

enum AppTab: String, CaseIterable {
    case explore = "探索"
    case add = "添加"
    case profile = "我的"

    var iconName: String {
        switch self {
        case .explore: return "map.fill"
        case .add: return "plus"
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

// MARK: - 主界面：全屏地图 + 悬浮底栏

struct MainTabView: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAddSearch = false
    @State private var pendingImportPreview: ImportPreview?
    @State private var pendingMatchedPlace: MapPlace?
    @State private var clipboardPlaceCard: ClipboardPlaceCardModel?
    @State private var isResolvingClipboardCard = false
    @State private var dismissedClipboardChangeCount: Int?
    @State private var selectedClipboardCollectionPreview: ImportPreview?
    @State private var hasEnteredActiveOnce = false

    var body: some View {
        ZStack {
            Group {
                if appState.selectedTab == .explore {
                    ExploreMapView()
                } else {
                    MyPageView()
                }
            }

            if !appState.hidesFloatingTabBar {
                VStack {
                    Spacer()
                    FloatingTabBar(selectedTab: $appState.selectedTab) {
                        pendingImportPreview = nil
                        pendingMatchedPlace = nil
                        showingAddSearch = true
                    }
                }
            }

            if let clipboardPlaceCard {
                ClipboardQuickImportOverlay(
                    card: clipboardPlaceCard,
                    onDismiss: {
                        dismissClipboardCard(clipboardPlaceCard.preview)
                    },
                    onOpenMarking: {
                        dismissClipboardCard(clipboardPlaceCard.preview)
                        if clipboardPlaceCard.preview.kind == .collection {
                            selectedClipboardCollectionPreview = clipboardPlaceCard.preview
                        } else {
                            pendingImportPreview = clipboardPlaceCard.preview
                            pendingMatchedPlace = clipboardPlaceCard.matchedPlace
                            showingAddSearch = true
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(10)
            }

            VStack {
                Spacer()
                Color.clear
                    .frame(height: 96)
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showingAddSearch) {
            AddPlaceSearchSheet(
                initialImportPreview: pendingImportPreview,
                initialMatchedPlace: pendingMatchedPlace
            )
        }
        .sheet(item: $selectedClipboardCollectionPreview) { preview in
            CollectionImportSheet(preview: preview)
        }
        .task {
            if scenePhase == .active, !hasEnteredActiveOnce {
                hasEnteredActiveOnce = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            guard hasEnteredActiveOnce else {
                hasEnteredActiveOnce = true
                return
            }
            scheduleClipboardChecks(reason: "scene-active")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            guard scenePhase == .active else { return }
            guard hasEnteredActiveOnce else { return }
            scheduleClipboardChecks(reason: "pasteboard-changed")
        }
    }

    private func scheduleClipboardChecks(reason: String) {
        let delays: [UInt64] = [0, 250_000_000, 750_000_000, 1_500_000_000, 2_400_000_000]
        for delay in delays {
            Task {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                await detectClipboardAddressCard(trigger: reason, force: false)
            }
        }
    }

    private func detectClipboardAddressCard(trigger: String, force: Bool) async {
        guard !isResolvingClipboardCard else { return }
        isResolvingClipboardCard = true
        defer { isResolvingClipboardCard = false }

        guard let text = clipboardTextSnapshot(),
              !text.isEmpty else {
            return
        }

        let currentChangeCount = UIPasteboard.general.changeCount
        guard force || currentChangeCount != dismissedClipboardChangeCount else {
            return
        }

        guard let preview = await container.importService.detectClipboardPreview(from: text) else {
            return
        }

        if preview.kind == .collection {
            let payload = await container.importService.extractCollectionPayload(from: preview)
            await MainActor.run {
                withAnimation(.spring(duration: 0.28)) {
                    clipboardPlaceCard = ClipboardPlaceCardModel(
                        preview: preview,
                        matchedPlace: nil,
                        collectionPayload: payload
                    )
                }
            }
            return
        }

        let center = appState.mapSearchCenter
            ?? container.locationManager.currentLocation?.coordinate
            ?? preview.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
        let candidates = preview.searchQueries.isEmpty ? [preview.suggestedQuery] : preview.searchQueries

        for candidate in candidates {
            do {
                let results = try await container.mapService.searchPlaces(
                    query: candidate,
                    region: MapRegion(center: center, radius: 30_000),
                    filters: nil
                )
                await MainActor.run {
                    withAnimation(.spring(duration: 0.28)) {
                        clipboardPlaceCard = ClipboardPlaceCardModel(
                            preview: preview,
                            matchedPlace: results.first,
                            collectionPayload: nil
                        )
                    }
                }
                return
            } catch {
                continue
            }
        }

        await MainActor.run {
            withAnimation(.spring(duration: 0.28)) {
                clipboardPlaceCard = ClipboardPlaceCardModel(
                    preview: preview,
                    matchedPlace: nil,
                    collectionPayload: nil
                )
            }
        }
    }

    private func dismissClipboardCard(_ preview: ImportPreview) {
        dismissedClipboardChangeCount = UIPasteboard.general.changeCount
        withAnimation(.spring(duration: 0.24)) {
            clipboardPlaceCard = nil
        }
    }

    private func quickSaveClipboardCard(_ card: ClipboardPlaceCardModel) {
        guard let place = card.matchedPlace else { return }
        let folder = container.placeRepository.fetchFolders().first
        _ = container.placeRepository.addPlace(
            name: place.name,
            address: place.address,
            latitude: place.coordinate.latitude,
            longitude: place.coordinate.longitude,
            status: .wantToGo,
            folder: folder,
            sourceType: card.preview.sourceType,
            sourceURL: card.preview.sourceURL,
            coverImageURL: place.coverImageURL
        )
        appState.mapRefreshTrigger += 1
        dismissClipboardCard(card.preview)
    }

    private func clipboardTextSnapshot() -> String? {
        let pasteboard = UIPasteboard.general

        if let direct = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !direct.isEmpty {
            return direct
        }

        if let url = pasteboard.url?.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines),
           !url.isEmpty {
            return url
        }

        if let strings = pasteboard.strings?
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }),
           !strings.isEmpty {
            return strings.joined(separator: "\n")
        }

        for item in pasteboard.items {
            if let text = item["public.utf8-plain-text"] as? String {
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
            if let text = item["public.text"] as? String {
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
            if let text = item["public.url"] as? String {
                let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty { return cleaned }
            }
        }

        return nil
    }
}

// MARK: - 悬浮底栏

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let onAddTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(
                title: "探索",
                isSelected: selectedTab == .explore
            ) {
                selectedTab = .explore
            } icon: {
                ExploreTabIcon(isSelected: selectedTab == .explore)
            }

            tabButton(
                title: "添加",
                isSelected: false
            ) {
                onAddTap()
            } icon: {
                AddTabIcon()
            }

            tabButton(
                title: "我的",
                isSelected: selectedTab == .profile
            ) {
                selectedTab = .profile
            } icon: {
                ProfileTabIcon(isSelected: selectedTab == .profile)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        .background {
            BubuGlassCapsule()
        }
        .frame(maxWidth: 222)
        .padding(.bottom, 18)
    }

    private func tabButton<Icon: View>(title: String, isSelected: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                icon()
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? BubuTheme.Text.ink : BubuTheme.Text.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isSelected ? BubuTheme.Glass.selectedFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ExploreTabIcon: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .top) {
            TicketGlyph()
                .stroke(BubuTheme.Text.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)

            Path { path in
                path.move(to: CGPoint(x: 4, y: 12))
                path.addLine(to: CGPoint(x: 12, y: 4))
            }
            .stroke(BubuTheme.Text.ink.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 16, height: 16)

            if isSelected {
                Circle()
                    .fill(BubuTheme.Primary.green)
                    .frame(width: 5, height: 5)
                    .offset(y: -5)
            }
        }
        .frame(width: 18, height: 16)
    }
}

private struct AddTabIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(BubuTheme.Text.ink.opacity(0.92), lineWidth: 1.3)
                .frame(width: 16, height: 16)
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BubuTheme.Text.ink)
        }
        .frame(width: 18, height: 16)
    }
}

private struct ProfileTabIcon: View {
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .top) {
            if isSelected {
                VStack(spacing: 2.5) {
                    Circle()
                        .fill(BubuTheme.Text.ink)
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(BubuTheme.Text.ink)
                        .frame(width: 14, height: 7)
                }
            } else {
                VStack(spacing: 2.5) {
                    Circle()
                        .stroke(BubuTheme.Text.ink, lineWidth: 1.4)
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(BubuTheme.Text.ink, lineWidth: 1.4)
                        .frame(width: 14, height: 7)
                }
            }

            if isSelected {
                Circle()
                    .fill(BubuTheme.Primary.green)
                    .frame(width: 5, height: 5)
                    .offset(y: -5)
            }
        }
        .frame(width: 18, height: 16)
    }
}

private struct TicketGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) * 0.26
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r * 1.3, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r * 1.1), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

// MARK: - 添加搜索 Sheet（搜→就地标→打卡 一条龙）

struct AddPlaceSearchSheet: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let initialImportPreview: ImportPreview?
    let initialMatchedPlace: MapPlace?

    @State private var query = ""
    @State private var results: [MapPlace] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var isCreatingManualPlace = false
    @State private var presentationDetent: PresentationDetent = .medium
    @State private var activeImportPreview: ImportPreview?
    @State private var importMessage: String?
    @State private var selectedCollectionPreview: ImportPreview?

    @State private var expandingPlace: MapPlace?
    @State private var lightingMode: LightingMode = .wantToGo
    @State private var visitedMood: VisitedMood?
    @State private var noteText: String = ""
    @State private var visitDate: Date = Date()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var recordedVoiceMemo: RecordedVoiceMemo?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if shouldShowLightingFlow, let place = expandingPlace {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            PlaceMemoryComposerCard(
                                place: place,
                                lightingMode: $lightingMode,
                                visitedMood: $visitedMood,
                                noteText: $noteText,
                                visitDate: $visitDate,
                                selectedPhotoItems: $selectedPhotoItems,
                                selectedImages: $selectedImages,
                                recordedVoiceMemo: $recordedVoiceMemo,
                                isSaving: isSaving,
                                checkInCount: 0,
                                canChangeMode: true,
                                actionTitle: "标记",
                                onSubmit: { savePlace(place) }
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)
                    }
                } else if isCreatingManualPlace {
                    ScrollView(showsIndicators: false) {
                        ManualPlaceCreatorContent(
                            initialName: query,
                            coordinate: mapSearchCenter,
                            onCreate: { place in
                                isCreatingManualPlace = false
                                expandingPlace = place
                                resetMemoryInputs()
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                } else {
                    searchContent
                }
            }
            .background(BubuTheme.Surface.space)
            .navigationTitle(
                shouldShowLightingFlow ? "" :
                    (isCreatingManualPlace ? "创建地点" : (initialImportPreview == nil ? "添加地点" : "点亮这个地点"))
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(shouldShowLightingFlow ? .hidden : .visible, for: .navigationBar)
            .toolbar {
                if !shouldShowLightingFlow {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isCreatingManualPlace ? "返回" : "完成") {
                            if isCreatingManualPlace {
                                isCreatingManualPlace = false
                                presentationDetent = .medium
                            } else {
                                dismiss()
                            }
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large], selection: $presentationDetent)
            .presentationDragIndicator(.visible)
            .task {
                guard let initialImportPreview else { return }
                await MainActor.run {
                    activeImportPreview = initialImportPreview
                    if initialImportPreview.kind == .singlePlace, initialMatchedPlace == nil {
                        query = initialImportPreview.searchQueries.first ?? initialImportPreview.suggestedQuery
                        isSearching = true
                    }
                }
                if let initialMatchedPlace, initialImportPreview.kind == .singlePlace {
                    await MainActor.run {
                        results = [initialMatchedPlace]
                        expandingPlace = initialMatchedPlace
                        query = initialMatchedPlace.name
                        importMessage = "已为你带入候选地点，补充一点记忆就可以点亮。"
                        resetMemoryInputs()
                    }
                } else if initialImportPreview.kind == .singlePlace {
                    await resolveImportedPlace(initialImportPreview)
                }
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task { await loadSelectedImages(from: newItems) }
            }
            .sheet(item: $selectedCollectionPreview) { preview in
                CollectionImportSheet(preview: preview)
            }
        }
    }

    private func doSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isSearching = true
        hasSearched = true
        isCreatingManualPlace = false
        expandingPlace = nil
        activeImportPreview = nil
        importMessage = nil
        Task {
            do {
                results = try await container.mapService.searchPlaces(
                    query: q,
                    region: MapRegion(center: mapSearchCenter, radius: 30000),
                    filters: nil
                )
            } catch { results = [] }
            isSearching = false
        }
    }

    @MainActor
    private func resolveImportedPlace(_ preview: ImportPreview) async {
        let searchCenter = preview.coordinate
            ?? appState.mapSearchCenter
            ?? container.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
        let radius = preview.coordinate == nil ? 30_000.0 : 8_000.0

        do {
            var fetched: [MapPlace] = []
            let candidates = preview.searchQueries.isEmpty ? [preview.suggestedQuery] : preview.searchQueries

            for candidate in candidates {
                let result = try await container.mapService.searchPlaces(
                    query: candidate,
                    region: MapRegion(center: searchCenter, radius: radius),
                    filters: nil
                )
                if !result.isEmpty {
                    fetched = result
                    await MainActor.run {
                        query = candidate
                    }
                    break
                }
            }

            var mergedResults = fetched
            if mergedResults.isEmpty, let coordinate = preview.coordinate {
                mergedResults = [
                    MapPlace(
                        id: "import_\(UUID().uuidString)",
                        name: preview.title,
                        address: preview.candidateAddress,
                        coordinate: coordinate,
                        poiID: nil,
                        category: nil,
                        phone: nil,
                        coverImageURL: nil,
                        rating: nil,
                        distance: nil
                    )
                ]
            }

            results = mergedResults
            expandingPlace = mergedResults.first
            resetMemoryInputs()
            importMessage = mergedResults.isEmpty
                ? "没有直接匹配到地点，建议补充更具体的店名或地址。"
                : "已为你匹配到候选地点，确认后即可收藏。"
        } catch {
            results = []
            importMessage = "导入解析到了线索，但地点匹配失败了，试试手动搜索更短的关键词。"
        }

        isSearching = false
    }

    private func savePlace(_ mapPlace: MapPlace) {
        isSaving = true
        let folder = container.placeRepository.fetchFolders().first
        let sourceType = activeImportPreview?.sourceType ?? .manual
        let sourceURL = activeImportPreview?.sourceURL
        let resolvedStatus = selectedStatus
        let up = container.placeRepository.addPlace(
            name: mapPlace.name,
            address: mapPlace.address,
            latitude: mapPlace.coordinate.latitude,
            longitude: mapPlace.coordinate.longitude,
            status: resolvedStatus,
            folder: folder,
            sourceType: sourceType,
            sourceURL: sourceURL,
            coverImageURL: mapPlace.coverImageURL
        )
        if resolvedStatus != .wantToGo {
            let checkIn = container.placeRepository.checkIn(
                userPlace: up,
                mood: selectedMoodTag,
                rating: 0,
                note: noteText.isEmpty ? nil : noteText,
                visitDate: visitDate
            )
            container.placeRepository.attachPhotos(selectedImages, to: checkIn, userPlace: up)
            if let recordedVoiceMemo {
                container.placeRepository.attachVoiceMemo(recordedVoiceMemo.fileURL, to: checkIn, userPlace: up)
            }
        } else {
            container.placeRepository.attachPhotos(selectedImages, to: up)
            if let recordedVoiceMemo {
                container.placeRepository.attachVoiceMemo(recordedVoiceMemo.fileURL, to: nil, userPlace: up)
            }
        }
        withAnimation {
            results.removeAll { $0.id == mapPlace.id }
            expandingPlace = nil
        }
        appState.mapRefreshTrigger += 1
        appState.focusPlaceID = up.place?.id
        appState.selectedTab = .explore
        activeImportPreview = nil
        importMessage = nil
        isSaving = false
        resetMemoryInputs()
        dismiss()
    }

    private var selectedStatus: PlaceStatus {
        switch lightingMode {
        case .wantToGo:
            return .wantToGo
        case .visited:
            switch visitedMood {
            case .good: return .visitedGood
            case .bad: return .visitedBad
            case .neutral, .none: return .visitedNeutral
            }
        }
    }

    private var selectedMoodTag: MoodTag? {
        switch visitedMood {
        case .good: return .happy
        case .neutral: return .calm
        case .bad: return .disappointed
        case .none: return nil
        }
    }

    private var shouldShowLightingFlow: Bool {
        expandingPlace != nil && selectedCollectionPreview == nil
    }

    @ViewBuilder
    private var searchContent: some View {
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
                    query = ""
                    results = []
                    expandingPlace = nil
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(BubuTheme.Text.tertiary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(BubuTheme.Surface.surface1)
        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)

        if let activeImportPreview {
            ImportObjectCard(
                preview: activeImportPreview,
                importMessage: importMessage,
                onCollectionTap: {
                    selectedCollectionPreview = activeImportPreview
                }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }

        Divider().background(BubuTheme.Text.tertiary).padding(.horizontal, 16)

        if isSearching {
            Spacer()
            ProgressView().tint(BubuTheme.Primary.green)
            Spacer()
        } else if !results.isEmpty {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { place in
                        VStack(spacing: 0) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandingPlace?.id == place.id {
                                        expandingPlace = nil
                                    } else {
                                        expandingPlace = place
                                        resetMemoryInputs()
                                    }
                                }
                            } label: {
                                PlaceSearchRow(place: place)
                            }
                            .buttonStyle(.plain)
                        }
                        Divider().background(BubuTheme.Text.tertiary).padding(.leading, 52)
                    }
                }
                .padding(.horizontal, 16)
            }
        } else if results.isEmpty && hasSearched && !query.isEmpty {
            VStack(spacing: 12) {
                Spacer().frame(height: 60)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(BubuTheme.Text.tertiary)
                Text("没有找到「\(query)」")
                    .font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                Text("没搜到？也可以自己创建一个地点")
                    .font(BubuFont.caption)
                    .foregroundStyle(BubuTheme.Text.tertiary)
                Button {
                    isCreatingManualPlace = true
                    presentationDetent = .large
                } label: {
                    Label("创建地点", systemImage: "plus")
                        .font(BubuFont.titleSM)
                        .foregroundStyle(BubuTheme.Surface.space)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(BubuTheme.Primary.green)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 16) {
                Spacer().frame(height: 60)
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(BubuTheme.Primary.green.opacity(0.6))
                Text("搜一家店，开始记录").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                Text("试试搜「火锅」「咖啡」「甜品」").font(BubuFont.caption).foregroundStyle(BubuTheme.Text.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func resetMemoryInputs() {
        lightingMode = .wantToGo
        visitedMood = nil
        noteText = ""
        visitDate = Date()
        selectedPhotoItems = []
        selectedImages = []
        recordedVoiceMemo = nil
    }

    private var mapSearchCenter: CLLocationCoordinate2D {
        appState.mapSearchCenter
            ?? container.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
    }

    @MainActor
    private func loadSelectedImages(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            selectedImages = []
            return
        }

        var loaded: [UIImage] = []
        for item in items.prefix(5) {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        selectedImages = loaded
    }
}

private struct ManualPlaceCreatorContent: View {
    let initialName: String
    let onCreate: (MapPlace) -> Void

    @EnvironmentObject private var container: AppContainer
    @State private var name = ""
    @State private var address = ""
    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var mapCamera: MapCameraPosition
    @State private var isReadingClipboard = false
    @State private var clipboardMessage: String?

    init(
        initialName: String,
        coordinate: CLLocationCoordinate2D,
        onCreate: @escaping (MapPlace) -> Void
    ) {
        self.initialName = initialName
        self.onCreate = onCreate
        _selectedCoordinate = State(initialValue: coordinate)
        _mapCamera = State(
            initialValue: .region(
                MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1_000,
                    longitudinalMeters: 1_000
                )
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BubuTheme.Primary.green.opacity(0.16))
                        .frame(width: 42, height: 42)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(BubuTheme.Primary.green)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("创建地点")
                        .font(BubuFont.titleMD)
                        .foregroundStyle(BubuTheme.Text.ink)
                    Text("地图暂时没有收录也没关系")
                        .font(BubuFont.caption)
                        .foregroundStyle(BubuTheme.Text.secondary)
                }

            }

            VStack(spacing: 10) {
                TextField("地点名称", text: $name)
                    .font(BubuFont.body)
                    .foregroundStyle(BubuTheme.Text.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md, style: .continuous))

                TextField("地址（可选）", text: $address)
                    .font(BubuFont.body)
                    .foregroundStyle(BubuTheme.Text.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md, style: .continuous))
            }

            Button {
                readClipboard()
            } label: {
                HStack(spacing: 8) {
                    if isReadingClipboard {
                        ProgressView().tint(BubuTheme.Primary.green)
                    } else {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text(isReadingClipboard ? "正在识别剪贴板" : "从剪贴板带入地点信息")
                        .font(BubuFont.caption)
                    Spacer()
                }
                .foregroundStyle(BubuTheme.Primary.green)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(BubuTheme.Primary.green.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md, style: .continuous))
            }
            .disabled(isReadingClipboard)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("拖动地图，标记大概位置")
                        .font(BubuFont.caption)
                        .foregroundStyle(BubuTheme.Text.secondary)
                    Spacer()
                    if let clipboardMessage {
                        Text(clipboardMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(BubuTheme.Text.tertiary)
                            .lineLimit(1)
                    }
                }

                ZStack {
                    Map(position: $mapCamera, interactionModes: [.pan, .zoom])
                        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                        .allowsHitTesting(true)
                        .onMapCameraChange(frequency: .onEnd) { context in
                            selectedCoordinate = context.region.center
                        }

                    VStack(spacing: 0) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 31))
                            .foregroundStyle(BubuTheme.Primary.green)
                            .shadow(color: .black.opacity(0.22), radius: 5, y: 3)
                        Circle()
                            .fill(BubuTheme.Primary.green.opacity(0.28))
                            .frame(width: 18, height: 5)
                            .blur(radius: 3)
                    }
                    .allowsHitTesting(false)
                    .offset(y: -14)
                }
                .frame(height: 128)
                .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md, style: .continuous))
            }

            Button {
                let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
                onCreate(
                    MapPlace(
                        id: "manual_\(UUID().uuidString)",
                        name: trimmedName,
                        address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                        coordinate: selectedCoordinate,
                        poiID: nil,
                        category: nil,
                        phone: nil,
                        coverImageURL: nil,
                        rating: nil,
                        distance: nil
                    )
                )
            } label: {
                Text("继续标记")
                    .font(BubuFont.titleSM)
                    .foregroundStyle(BubuTheme.Surface.space)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BubuTheme.Primary.green)
                    .clipShape(Capsule())
            }
            .disabled(trimmedName.isEmpty)
            .opacity(trimmedName.isEmpty ? 0.42 : 1)

            Spacer(minLength: 0)
        }
        .padding(20)
        .background(BubuTheme.Surface.space)
        .onAppear { name = initialName }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readClipboard() {
        guard let text = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            clipboardMessage = "剪贴板里没有可识别文字"
            return
        }

        isReadingClipboard = true
        clipboardMessage = nil
        Task {
            let preview = await container.importService.detectClipboardPreview(from: text)
            await MainActor.run {
                if let preview {
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == initialName {
                        name = preview.title
                    }
                    if let candidateAddress = preview.candidateAddress, !candidateAddress.isEmpty {
                        address = candidateAddress
                    }
                    if let coordinate = preview.coordinate {
                        selectedCoordinate = coordinate
                        mapCamera = .region(
                            MKCoordinateRegion(
                                center: coordinate,
                                latitudinalMeters: 1_000,
                                longitudinalMeters: 1_000
                            )
                        )
                    }
                    clipboardMessage = "已带入地点信息"
                } else {
                    clipboardMessage = "没有识别出地点信息"
                }
                isReadingClipboard = false
            }
        }
    }
}

enum LightingMode: String, CaseIterable {
    case wantToGo = "想去"
    case visited = "去过"
}

enum VisitedMood: String, CaseIterable {
    case good = "好"
    case neutral = "一般"
    case bad = "差"

    var iconName: String {
        switch self {
        case .good: return "hand.thumbsup.fill"
        case .neutral: return "circle.lefthalf.filled"
        case .bad: return "hand.thumbsdown.fill"
        }
    }

    var tint: Color {
        switch self {
        case .good: return BubuTheme.Primary.green
        case .neutral: return BubuTheme.Semantic.visitedNeutral
        case .bad: return BubuTheme.Semantic.visitedBad
        }
    }
}

struct PlaceMemoryComposerCard: View {
    let place: MapPlace
    @Binding var lightingMode: LightingMode
    @Binding var visitedMood: VisitedMood?
    @Binding var noteText: String
    @Binding var visitDate: Date
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Binding var selectedImages: [UIImage]
    @Binding var recordedVoiceMemo: RecordedVoiceMemo?
    let isSaving: Bool
    let checkInCount: Int
    let canChangeMode: Bool
    let actionTitle: String
    let onSubmit: () -> Void
    @StateObject private var voiceRecorder = VoiceMemoRecorder()
    @StateObject private var voicePreviewPlayer = AudioPreviewPlayer()
    @State private var showingCamera = false
    @State private var showingMoodSheet = false
    @State private var showingVoiceSheet = false
    @State private var showingDateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                coverView
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(alignment: .leading, spacing: 8) {
                    Text(place.name)
                        .font(BubuFont.titleMD)
                        .foregroundStyle(BubuTheme.Text.ink)
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        if let rating = place.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Primary.green)
                        }

                        if let distance = place.distance {
                            Text(distanceText(distance))
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Text.secondary)
                        }

                        if let category = place.category, !category.isEmpty {
                            Text(category)
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Text.secondary)
                        }
                    }

                    if lightingMode == .visited {
                        Button {
                            showingDateSheet = true
                        } label: {
                            Text(visitDate.formatted(date: .abbreviated, time: .omitted))
                                .font(BubuFont.caption)
                            .foregroundStyle(BubuTheme.Text.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(BubuTheme.Surface.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }

            if canChangeMode {
                HStack(spacing: 10) {
                    ForEach(LightingMode.allCases, id: \.self) { mode in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                lightingMode = mode
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(BubuFont.titleSM)
                                .foregroundStyle(lightingMode == mode ? BubuTheme.Text.ink : BubuTheme.Text.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: BubuRadius.lg)
                                        .fill(lightingMode == mode ? BubuTheme.Primary.green.opacity(0.14) : BubuTheme.Surface.surface2)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: BubuRadius.lg)
                                                .stroke(lightingMode == mode ? BubuTheme.Primary.green.opacity(0.34) : BubuTheme.Surface.surface3, lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                noteInputArea
                .padding(.top, 2)

                Divider().background(BubuTheme.Surface.surface3)
            }

            if !selectedImages.isEmpty {
                capturedMediaPreview
            }

            journalToolbar

            Button {
                onSubmit()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView().tint(BubuTheme.Text.onPrimary)
                    } else {
                        Text(actionTitle)
                            .font(BubuFont.button)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(BubuTheme.Primary.green)
                .foregroundStyle(BubuTheme.Text.onPrimary)
                .clipShape(RoundedRectangle(cornerRadius: BubuRadius.xl))
            }
            .disabled(isSaving)
        }
        .padding(22)
        .background(BubuTheme.Surface.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 34)
                .stroke(BubuTheme.Surface.surface3, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .clipShape(RoundedRectangle(cornerRadius: 34))
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView { image in
                selectedImages.append(image)
            }
        }
        .sheet(isPresented: $showingMoodSheet) {
            MoodSelectionSheet(selectedMood: $visitedMood)
                .presentationDetents([.fraction(0.3)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingVoiceSheet) {
            VoiceRecordingSheet(
                recorder: voiceRecorder,
                recordedVoiceMemo: $recordedVoiceMemo
            )
            .presentationDetents([.height(340)])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showingDateSheet) {
            VisitDateSheet(visitDate: $visitDate)
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: voiceRecorder.recordedMemo) { _, newValue in
            if let newValue {
                recordedVoiceMemo = newValue
            }
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if let coverURL = place.coverImageURL {
            AsyncImage(url: coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                FlagSeedPlaceholder()
            }
        } else {
            FlagSeedPlaceholder()
        }
    }

    @ViewBuilder
    private var journalToolbar: some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 5, matching: .images) {
                toolbarIcon("photo.on.rectangle.angled")
            }
            .buttonStyle(.plain)

            Button {
                showingCamera = true
            } label: {
                toolbarIcon("camera")
            }
            .buttonStyle(.plain)

            Button {
                showingVoiceSheet = true
            } label: {
                toolbarIcon(recordedVoiceMemo == nil ? "waveform" : "waveform.badge.checkmark")
                    .foregroundStyle(recordedVoiceMemo == nil ? BubuTheme.Text.ink : BubuTheme.Primary.green)
            }
            .buttonStyle(.plain)

            Button {
                showingMoodSheet = true
            } label: {
                toolbarIcon("sparkles")
                    .foregroundStyle(visitedMood == nil ? BubuTheme.Text.ink : moodGlowColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(BubuTheme.Surface.surface2)
        .overlay(
            Capsule()
                .stroke(BubuTheme.Surface.surface3, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private func toolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
    }

    @ViewBuilder
    private var capturedMediaPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))

                                Button {
                                    selectedImages.remove(at: index)
                                    if index < selectedPhotoItems.count {
                                        selectedPhotoItems.remove(at: index)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(BubuTheme.Text.secondary)
                                        .frame(width: 18, height: 18)
                                        .background(BubuTheme.Surface.surface2.opacity(0.96))
                                        .overlay(
                                            Circle()
                                                .stroke(BubuTheme.Surface.surface3, lineWidth: 0.8)
                                        )
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
        }
    }

    private var hasInlineInputChips: Bool {
        visitedMood != nil || recordedVoiceMemo != nil
    }

    @ViewBuilder
    private var noteInputArea: some View {
        HStack(alignment: .center, spacing: 8) {
            if hasInlineInputChips {
                inlineInputChips
            }
            noteField
        }
        .frame(height: 30, alignment: .leading)
    }

    private var inlineInputChips: some View {
        HStack(alignment: .center, spacing: 8) {
            if let currentMood = visitedMood {
                inlineInputChip(
                    icon: "sparkles",
                    title: currentMood.rawValue,
                    tint: moodGlowColor,
                    onDelete: { self.visitedMood = nil }
                )
            }

            if let currentVoiceMemo = recordedVoiceMemo {
                inlineInputChip(
                    icon: "waveform",
                    title: currentVoiceMemo.shortDurationLabel,
                    tint: BubuTheme.Primary.green,
                    onTap: {
                        voicePreviewPlayer.togglePlayback(url: currentVoiceMemo.fileURL)
                    },
                    onDelete: {
                        self.recordedVoiceMemo = nil
                        voiceRecorder.clearRecording()
                        voicePreviewPlayer.stop()
                    }
                )
            }

        }
    }

    private var noteField: some View {
        TextField(
            "",
            text: $noteText,
            prompt: Text("记录一句话")
                .foregroundStyle(BubuTheme.Text.tertiary)
        )
            .font(BubuFont.body)
            .foregroundStyle(BubuTheme.Text.ink)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .tint(BubuTheme.Primary.uiTint)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.clear)
    }

    @ViewBuilder
    private func inlineInputChip(icon: String, title: String, tint: Color, onTap: (() -> Void)? = nil, onDelete: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onTap?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                    Text(title)
                        .font(BubuFont.caption)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .padding(.trailing, 12)
                .background(tint.opacity(0.14))
                .overlay(
                    Capsule()
                        .stroke(tint.opacity(0.26), lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(BubuTheme.Text.secondary)
                    .frame(width: 16, height: 16)
                    .background(BubuTheme.Surface.surface2.opacity(0.96))
                    .overlay(
                        Circle()
                            .stroke(BubuTheme.Surface.surface3, lineWidth: 0.8)
                    )
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private var moodGlowColor: Color {
        switch visitedMood {
        case .good: return BubuTheme.Primary.green
        case .bad: return BubuTheme.Semantic.visitedBad
        case .neutral, .none: return BubuTheme.Semantic.visitedNeutral
        }
    }

    private func distanceText(_ distance: Double) -> String {
        distance < 1000 ? "\(Int(distance))m" : String(format: "%.1fkm", distance / 1000)
    }
}

struct FlagSeedPlaceholder: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BubuRadius.xl)
                .fill(
                    LinearGradient(
                        colors: [BubuTheme.Surface.surface2, BubuTheme.Surface.surface1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(BubuTheme.Surface.surface3)
                .frame(width: 56, height: 56)
            VStack(spacing: 2) {
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color(hex: "DEE7BF"))
                        .frame(width: 3, height: 26)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 14, y: 5))
                        path.addLine(to: CGPoint(x: 0, y: 10))
                        path.closeSubpath()
                    }
                    .fill(Color(hex: "E55757"))
                    .frame(width: 14, height: 10)
                    .offset(x: 7, y: -12)
                }
                Capsule()
                    .fill(Color(hex: "7FA85E"))
                    .frame(width: 34, height: 10)
            }
        }
    }
}

struct RecordedVoiceMemo: Equatable {
    let fileURL: URL
    let duration: TimeInterval

    var durationLabel: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var shortDurationLabel: String {
        let rounded = max(1, Int(duration.rounded()))
        return "\(rounded)秒"
    }
}

struct MoodSelectionSheet: View {
    @Binding var selectedMood: VisitedMood?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {
            Text("选择当下感受")
                .font(BubuFont.titleSM)
                .foregroundStyle(BubuTheme.Text.ink)
                .padding(.top, 10)

            HStack(spacing: 28) {
                moodOrb(.bad, title: "差")
                moodOrb(.neutral, title: "一般")
                moodOrb(.good, title: "好")
            }

            Button("完成") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(BubuButtonModifier(variant: .primary))
        }
        .padding(20)
        .background(BubuTheme.Surface.surface1)
    }

    @ViewBuilder
    private func moodOrb(_ mood: VisitedMood, title: String) -> some View {
        Button {
            selectedMood = mood
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color(for: mood).opacity(selectedMood == mood ? 0.24 : 0.08))
                        .frame(width: 54, height: 54)
                        .blur(radius: selectedMood == mood ? 12 : 0)
                    Circle()
                        .fill(color(for: mood))
                        .frame(width: selectedMood == mood ? 20 : 14, height: selectedMood == mood ? 20 : 14)
                }
                Text(title)
                    .font(BubuFont.caption)
                    .foregroundStyle(selectedMood == mood ? BubuTheme.Text.ink : BubuTheme.Text.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func color(for mood: VisitedMood) -> Color {
        switch mood {
        case .good: return BubuTheme.Primary.green
        case .bad: return BubuTheme.Semantic.visitedBad
        case .neutral: return BubuTheme.Semantic.visitedNeutral
        }
    }
}

struct VoiceRecordingSheet: View {
    @ObservedObject var recorder: VoiceMemoRecorder
    @Binding var recordedVoiceMemo: RecordedVoiceMemo?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 18) {
            Text(recorder.currentDurationLabel)
                .font(.system(size: 22, weight: .regular, design: .rounded))
                .foregroundStyle(BubuTheme.Text.secondary)
                .padding(.top, 18)

            Text(recorder.isRecording ? "正在录音" : "开始录音")
                .font(BubuFont.body)
                .foregroundStyle(BubuTheme.Text.secondary.opacity(0.72))

            if recorder.isRecording {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate * 7.5
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(Array(waveHeights.enumerated()), id: \.offset) { index, height in
                            Capsule()
                                .fill(BubuTheme.Primary.green.opacity(0.18 + (Double(index % 3) * 0.08)))
                                .frame(width: 6, height: animatedWaveHeight(base: height, phase: phase, index: index))
                        }
                    }
                }
                .frame(height: 28)
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            Button {
                if recorder.isRecording {
                    recorder.stopRecording()
                    recordedVoiceMemo = recorder.recordedMemo
                    dismiss()
                } else {
                    recorder.startRecording()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(BubuTheme.Primary.green.opacity(0.14))
                        .frame(width: 88, height: 88)
                    Circle()
                        .stroke(BubuTheme.Primary.green.opacity(0.28), lineWidth: 2)
                        .frame(width: 88, height: 88)
                    Group {
                        if recorder.isRecording {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BubuTheme.Primary.green)
                                .frame(width: 34, height: 34)
                        } else {
                            Circle()
                                .fill(BubuTheme.Primary.green)
                                .frame(width: 54, height: 54)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .background(BubuTheme.Surface.surface1)
        .onDisappear {
            if recorder.isRecording {
                recorder.cancelRecording()
                recordedVoiceMemo = nil
            } else if recordedVoiceMemo == nil {
                recorder.clearRecording()
            }
        }
    }

    private var waveHeights: [CGFloat] {
        [10, 16, 22, 14, 26, 18, 24, 14, 20, 12]
    }

    private func animatedWaveHeight(base: CGFloat, phase: Double, index: Int) -> CGFloat {
        let wobble = sin(phase + Double(index) * 0.55) * 5
        return max(8, base + wobble)
    }
}

struct VisitDateSheet: View {
    @Binding var visitDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            DatePicker(
                "",
                selection: $visitDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(BubuTheme.Primary.uiTint)
            .colorScheme(.dark)
            .frame(maxWidth: .infinity)

            Button("完成") {
                dismiss()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(BubuButtonModifier(variant: .primary))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(BubuTheme.Surface.surface1)
    }
}

@MainActor
final class VoiceMemoRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordedMemo: RecordedVoiceMemo?
    @Published var currentDuration: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func clearRecording() {
        recordedMemo = nil
        recorder = nil
        isRecording = false
        currentDuration = 0
        timer?.invalidate()
        timer = nil
    }

    func cancelRecording() {
        guard let recorder else {
            clearRecording()
            return
        }
        let url = recorder.url
        recorder.stop()
        recorder.deleteRecording()
        try? FileManager.default.removeItem(at: url)
        try? AVAudioSession.sharedInstance().setActive(false)
        clearRecording()
    }

    func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else { return }
            Task { @MainActor in
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)

                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VoiceDrafts", isDirectory: true)
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let fileURL = directory.appendingPathComponent("\(UUID().uuidString).m4a")

                    let settings: [String: Any] = [
                        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                        AVSampleRateKey: 12_000,
                        AVNumberOfChannelsKey: 1,
                        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                    ]

                    let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
                    recorder.delegate = self
                    recorder.record()
                    self?.recorder = recorder
                    self?.isRecording = true
                    self?.currentDuration = 0
                    self?.startTimer()
                } catch {
                    self?.isRecording = false
                }
            }
        }
    }

    func stopRecording() {
        recorder?.stop()
        isRecording = false
        timer?.invalidate()
        timer = nil
        guard let recorder else { return }
        currentDuration = recorder.currentTime
        recordedMemo = RecordedVoiceMemo(fileURL: recorder.url, duration: recorder.currentTime)
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            self.currentDuration = recorder.currentTime
        }
    }

    var currentDurationLabel: String {
        let minutes = Int(currentDuration) / 60
        let seconds = Int(currentDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@MainActor
final class AudioPreviewPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?

    func togglePlayback(url: URL) {
        if isPlaying {
            stop()
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        stop()
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(_ parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }
    }
}

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    var body: some View {
        _FlowLayout(spacing: spacing, lineSpacing: lineSpacing) {
            content
        }
    }
}

private struct _FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct ClipboardPlaceCardModel: Equatable {
    let preview: ImportPreview
    let matchedPlace: MapPlace?
    let collectionPayload: ImportCollectionPayload?
}

struct ClipboardQuickImportOverlay: View {
    let card: ClipboardPlaceCardModel
    let onDismiss: () -> Void
    let onOpenMarking: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(BubuTheme.Primary.green.opacity(0.16))
                                .frame(width: 38, height: 38)
                            Image(systemName: sourceIcon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(BubuTheme.Primary.green)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(primaryTitle)
                                .font(BubuFont.titleSM)
                                .foregroundStyle(BubuTheme.Text.ink)
                                .lineLimit(2)
                            Text(sourceLabel)
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Text.secondary)
                        }

                        Spacer()

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(BubuTheme.Text.tertiary)
                                .frame(width: 28, height: 28)
                                .background(BubuTheme.Surface.surface2)
                                .clipShape(Circle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if card.preview.kind == .singlePlace,
                           let address = card.matchedPlace?.address ?? card.preview.candidateAddress {
                            Label(address, systemImage: "mappin.and.ellipse")
                                .font(BubuFont.bodySM)
                                .foregroundStyle(BubuTheme.Text.secondary)
                                .lineLimit(2)
                        }

                        if let descriptionText {
                            Text(descriptionText)
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Text.tertiary)
                        }
                    }

                    HStack(spacing: 10) {
                        Button(primaryActionTitle) {
                            onOpenMarking()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(BubuButtonModifier(variant: .primary))
                    }
                }
                .padding(18)
                .background(BubuTheme.Surface.surface1)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(BubuTheme.Primary.green.opacity(0.14), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.22), radius: 26, y: 10)
                .padding(.horizontal, 22)
                .padding(.bottom, 120)
            }
        }
    }

    private var sourceIcon: String {
        switch card.preview.sourceType {
        case .redbook: return "book.closed.fill"
        case .amapFavorite: return "map.fill"
        case .manual, .friendRecommend, .curated, .other: return "sparkles"
        }
    }

    private var sourceLabel: String {
        switch card.preview.sourceType {
        case .redbook: return "来自小红书分享"
        case .amapFavorite: return "来自高德分享"
        case .manual: return "来自剪贴板文本"
        case .friendRecommend: return "来自朋友推荐"
        case .curated: return "来自步步精选"
        case .other: return "来自外部内容"
        }
    }

    private var descriptionText: String? {
        if card.preview.kind == .collection {
            if let count = card.collectionPayload?.items.count, count > 0 {
                return "识别到 \(count) 个地点，默认全选后可一键添加进步步。"
            }
            return "已经认出这是一份高德收藏夹分享，继续导入后会直接整理里面的地点。"
        }

        return nil
    }

    private var primaryActionTitle: String {
        card.preview.kind == .collection ? "继续导入" : "点亮"
    }

    private var primaryTitle: String {
        if card.preview.kind == .collection {
            return card.collectionPayload?.title ?? card.preview.title
        }
        return card.matchedPlace?.name ?? card.preview.title
    }
}

struct ImportObjectCard: View {
    let preview: ImportPreview
    let importMessage: String?
    let onCollectionTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(BubuTheme.Primary.green.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Image(systemName: sourceIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(BubuTheme.Primary.green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(sourceTitle)
                            .font(BubuFont.caption)
                            .foregroundStyle(BubuTheme.Primary.green)
                        Text(kindBadge)
                            .font(BubuFont.caption)
                            .foregroundStyle(BubuTheme.Text.onPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(BubuTheme.Primary.green.opacity(0.9))
                            .clipShape(Capsule())
                    }

                    Text(preview.title)
                        .font(BubuFont.titleMD)
                        .foregroundStyle(BubuTheme.Text.ink)
                        .lineLimit(2)

                    Text(primaryDescription)
                        .font(BubuFont.bodySM)
                        .foregroundStyle(BubuTheme.Text.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }

            if let importMessage {
                Text(importMessage)
                    .font(BubuFont.caption)
                    .foregroundStyle(BubuTheme.Text.tertiary)
            }

            if preview.kind == .collection {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BubuTheme.Primary.green)
                        Text("把这份外部收藏，变成你在步步里的地点清单。")
                            .font(BubuFont.caption)
                            .foregroundStyle(BubuTheme.Text.secondary)
                    }

                    Button("继续导入") {
                        onCollectionTap()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(BubuButtonModifier(variant: .primary))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BubuTheme.Surface.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: BubuRadius.lg)
                .stroke(BubuTheme.Primary.green.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: BubuTheme.Primary.green.opacity(0.08), radius: 20, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
    }

    private var kindBadge: String {
        switch preview.kind {
        case .singlePlace: return "地点卡"
        case .collection: return "收藏夹卡"
        }
    }

    private var sourceTitle: String {
        switch preview.sourceType {
        case .redbook: return "来自小红书"
        case .amapFavorite: return preview.kind == .collection ? "来自高德收藏夹" : "来自高德"
        case .manual: return "来自粘贴文本"
        case .friendRecommend: return "来自朋友推荐"
        case .curated: return "来自步步精选"
        case .other: return "来自外部内容"
        }
    }

    private var sourceIcon: String {
        switch preview.sourceType {
        case .redbook: return "book.closed.fill"
        case .amapFavorite: return preview.kind == .collection ? "square.stack.3d.up.fill" : "map.fill"
        case .manual, .friendRecommend, .curated, .other: return "sparkles"
        }
    }

    private var primaryDescription: String {
        if preview.kind == .collection {
            return "已识别为高德收藏夹分享，接下来会进入批量导入流程，而不是一条条手动添加。"
        }
        return preview.subtitle ?? "我们会先帮你匹配地点，确认后再保存到步步。"
    }
}

struct CollectionImportSheet: View {
    let preview: ImportPreview
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var payload: ImportCollectionPayload?
    @State private var displayItems: [CollectionImportDisplayItem] = []
    @State private var selectedIDs = Set<UUID>()
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var importResult: (imported: Int, skipped: Int)?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(displayTitle)
                        .font(BubuFont.titleLG)
                        .foregroundStyle(BubuTheme.Text.ink)
                    Text(displayIntro)
                        .font(BubuFont.bodySM)
                        .foregroundStyle(BubuTheme.Text.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(BubuTheme.Primary.green.opacity(0.14))
                                .frame(width: 48, height: 48)
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(BubuTheme.Primary.green)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("来自高德")
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Primary.green)
                            Text(displayTitle)
                                .font(BubuFont.titleMD)
                                .foregroundStyle(BubuTheme.Text.ink)
                            Text("来自高德收藏夹分享")
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Text.secondary)
                        }
                    }

                    if let count = payload?.items.count, count > 0 {
                        Text("识别到 \(count) 个地点，默认全选。确认后会先加入你的想去清单。")
                            .font(BubuFont.bodySM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                    } else if let summary = payload?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(BubuFont.bodySM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                    } else if let subtitle = preview.subtitle {
                        Text(subtitle.replacingOccurrences(of: "收藏夹 ID: ", with: ""))
                            .font(BubuFont.bodySM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                    }
                }
                .padding(16)
                .background(BubuTheme.Surface.surface1)
                .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))

                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(BubuTheme.Primary.green)
                        Text("正在读取这份收藏夹里的地点…")
                            .font(BubuFont.bodySM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
                } else if payload != nil {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("识别到 \(displayItems.count) 个地点")
                                .font(BubuFont.titleSM)
                                .foregroundStyle(BubuTheme.Text.ink)
                            Spacer()
                            Button(selectedIDs.count == displayItems.count ? "取消全选" : "全选") {
                                if selectedIDs.count == displayItems.count {
                                    selectedIDs.removeAll()
                                } else {
                                    selectedIDs = Set(displayItems.map(\.id))
                                }
                            }
                            .font(BubuFont.caption)
                            .foregroundStyle(BubuTheme.Primary.green)
                        }

                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(displayItems) { item in
                                    Button {
                                        toggleSelection(for: item.id)
                                    } label: {
                                        CollectionImportRow(item: item, isSelected: selectedIDs.contains(item.id))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxHeight: 360)

                        if let importResult {
                            Text(importResult.skipped > 0 ? "已添加 \(importResult.imported) 个地点，跳过 \(importResult.skipped) 个重复项。" : "已添加 \(importResult.imported) 个地点。")
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Text.tertiary)
                        } else {
                            Text("会默认先收进你的“想去”清单，之后你可以慢慢再点亮。")
                                .font(BubuFont.caption)
                                .foregroundStyle(BubuTheme.Text.tertiary)
                        }
                    }
                    .padding(16)
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("这次还没顺利提取出地点清单")
                            .font(BubuFont.titleSM)
                            .foregroundStyle(BubuTheme.Text.ink)
                        Text(errorMessage ?? "分享入口已经认出来了，但地点列表还没被稳定读到。")
                            .font(BubuFont.bodySM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                        Button("重新尝试") {
                            Task { await loadCollection() }
                        }
                        .buttonStyle(BubuButtonModifier(variant: .secondary))
                    }
                    .padding(16)
                    .background(BubuTheme.Surface.surface1)
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.lg))
                }

                Spacer()

                if payload != nil && !displayItems.isEmpty {
                    Button(importResult == nil ? "一键添加已选 \(selectedIDs.count) 个地点" : "完成") {
                        if importResult == nil {
                            importSelectedPlaces()
                        } else {
                            dismiss()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(BubuButtonModifier(variant: .primary))
                    .disabled(isImporting || selectedIDs.isEmpty)
                } else {
                    Button("关闭") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(BubuButtonModifier(variant: .secondary))
                }
            }
            .padding(20)
            .background(BubuTheme.Surface.space)
            .navigationTitle("导入地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                await loadCollection()
            }
        }
    }

    @MainActor
    private func loadCollection() async {
        isLoading = true
        errorMessage = nil
        importResult = nil
        payload = await container.importService.extractCollectionPayload(from: preview)
        if let payload {
            displayItems = await resolveDisplayItems(from: payload)
            selectedIDs = Set(displayItems.map(\.id))
        } else {
            displayItems = []
            selectedIDs = []
            errorMessage = "我们已经识别到这是收藏夹分享，但还没从里面稳定提取出地点列表。"
        }
        isLoading = false
    }

    private func importSelectedPlaces() {
        isImporting = true
        let folder = container.placeRepository.fetchFolders().first
        let selectedPlaces = displayItems
            .filter { selectedIDs.contains($0.id) }
            .map(\.source)
        importResult = container.placeRepository.importPlaces(selectedPlaces, status: .wantToGo, folder: folder)
        appState.mapRefreshTrigger += 1
        isImporting = false
    }

    private func toggleSelection(for id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func resolveDisplayItems(from payload: ImportCollectionPayload) async -> [CollectionImportDisplayItem] {
        let center = appState.mapSearchCenter
            ?? container.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
        var resolved: [CollectionImportDisplayItem] = []

        for place in payload.items {
            let query = [place.name, place.address].compactMap { $0 }.joined(separator: " ")
            let matched = try? await container.mapService.searchPlaces(
                query: query,
                region: MapRegion(center: center, radius: 30_000),
                filters: nil
            ).first

            var averageCost: String?
            if let poiID = matched?.poiID,
               let detail = try? await container.mapService.fetchPlaceDetail(poiID: poiID),
               let priceRange = detail.priceRange, !priceRange.isEmpty {
                averageCost = "¥\(priceRange)/人"
            }

            resolved.append(
                CollectionImportDisplayItem(
                    source: place,
                    matchedPlace: matched,
                    averageCost: averageCost
                )
            )
        }

        return resolved
    }

    private var displayTitle: String {
        payload?.title ?? preview.title
    }

    private var displayIntro: String {
        if let count = payload?.items.count, count > 0 {
            return "识别到 \(count) 个地点，默认全选。你可以检查一遍后，一键带进步步。"
        }
        return "把你在高德存过的一批地点带进步步，以后就不用从零重新整理。"
    }
}

struct CollectionImportDisplayItem: Identifiable {
    let id = UUID()
    let source: ImportablePlace
    let matchedPlace: MapPlace?
    let averageCost: String?
}

struct CollectionImportRow: View {
    let item: CollectionImportDisplayItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let imageURL = item.matchedPlace?.coverImageURL ?? item.source.imageURL {
                    AsyncImage(url: imageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        placeholderCover
                    }
                } else {
                    placeholderCover
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.matchedPlace?.name ?? item.source.name)
                    .font(BubuFont.body)
                    .foregroundStyle(BubuTheme.Text.ink)
                    .lineLimit(2)

                if let address = item.matchedPlace?.address ?? item.source.address {
                    Text(address)
                        .font(BubuFont.caption)
                        .foregroundStyle(BubuTheme.Text.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if let rating = item.matchedPlace?.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BubuTheme.Primary.green)
                    }

                    if let distance = item.matchedPlace?.distance {
                        Text(distance < 1000 ? "\(Int(distance))m" : String(format: "%.1fkm", distance / 1000))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BubuTheme.Text.tertiary)
                    }

                    if let averageCost = item.averageCost {
                        Text(averageCost)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(BubuTheme.Text.tertiary)
                    }
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? BubuTheme.Primary.green : BubuTheme.Text.tertiary)
        }
        .padding(12)
        .background(BubuTheme.Surface.surface2)
        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(
                LinearGradient(
                    colors: [BubuTheme.Primary.green.opacity(0.22), BubuTheme.Surface.surface1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BubuTheme.Text.tertiary)
            )
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
