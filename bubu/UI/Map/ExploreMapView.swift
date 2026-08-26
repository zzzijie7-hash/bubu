import SwiftUI
import CoreLocation
import MapKit
import PhotosUI

// MARK: - 探索地图页（全屏地图 + 顶部浮层）

struct ExploreMapView: View {
    @EnvironmentObject var container: AppContainer
    @State private var camera: MapCameraPosition = .automatic
    @State private var showingFilter = false
    @State private var filter = PlaceFilter()
    @State private var allUserPlaces: [CDUserPlace] = []
    @State private var selectedUserPlace: CDUserPlace?
    @State private var selectedAnnotationID: String?
    @State private var currentAddress = "SOHO复兴广场"
    @State private var showingAddressPicker = false
    @State private var savedAddresses = SavedAddress.load()
    @State private var addressSearchHistory: [String] = SavedAddress.loadSearchHistory()
    @State private var currentZoomLevel: Double = 1000
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Map(position: $camera, interactionModes: .all, selection: $selectedAnnotationID) {
                // 当前位置（头像风格浮标）
                if let loc = container.locationManager.currentLocation {
                    Annotation("", coordinate: loc.coordinate) {
                        VStack(spacing: 3) {
                            DirectionTriangle()
                                .fill(BubuTheme.Primary.green)
                                .frame(width: 11, height: 9)
                                .shadow(color: BubuTheme.Primary.green.opacity(0.22), radius: 6, y: 1)

                            ZStack {
                                Circle()
                                    .fill(BubuTheme.Primary.green.opacity(0.20))
                                    .frame(width: 22, height: 22)
                                Circle()
                                    .stroke(.white, lineWidth: 4)
                                    .frame(width: 18, height: 18)
                                Circle()
                                    .fill(BubuTheme.Primary.green)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }

                // 用户标记
                ForEach(allUserPlaces, id: \.id) { up in
                    let p = up.place
                    let coord = CLLocationCoordinate2D(latitude: p?.latitude ?? 0, longitude: p?.longitude ?? 0)
                    let status = PlaceStatus(rawValue: up.statusValue) ?? .wantToGo
                    Annotation("", coordinate: coord) {
                        UserPlaceMarker(
                            status: status,
                            color: BubuTheme.mapMarkerColor(for: status),
                            name: p?.name ?? "",
                            photoData: markerPhotoData(for: up)
                        )
                    }
                    .tag("user_\(p?.id?.uuidString ?? "")")
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .mapControls { MapCompass() }
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .onChange(of: selectedAnnotationID) { _, tagID in
                guard let tagID, tagID.hasPrefix("user_") else { return }
                let id = String(tagID.dropFirst(5))
                if let up = allUserPlaces.first(where: { $0.place?.id?.uuidString == id }),
                   let p = up.place {
                    let c = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
                    withAnimation(.easeInOut(duration: 0.24)) { zoomTo(center: c, meters: 500) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { selectedUserPlace = up }
                }
            }

            // 顶部浮层
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { showingAddressPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2).foregroundStyle(BubuTheme.Primary.green)
                            Text(currentAddress).font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.ink).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(BubuTheme.Text.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background { BubuGlassCapsule() }
                    }

                    Button { goToMyLocation() } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 14)).foregroundStyle(BubuTheme.Text.ink)
                            .frame(width: 38, height: 38)
                            .background { BubuGlassCircle() }
                    }

                    Spacer()

                    VStack(spacing: 1) {
                        Button { zoomIn() } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BubuTheme.Text.ink).frame(width: 34, height: 34)
                                .background { BubuGlassRounded(radius: 10) }
                        }
                        Divider().frame(width: 22)
                        Button { zoomOut() } label: {
                            Image(systemName: "minus").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BubuTheme.Text.ink).frame(width: 34, height: 34)
                                .background { BubuGlassRounded(radius: 10) }
                        }
                    }

                    Button { showingFilter.toggle() } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(filter.isEmpty ? BubuTheme.Text.ink : BubuTheme.Primary.green)
                            .frame(width: 38, height: 38)
                            .background { BubuGlassCircle() }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 54)

                if !filter.isEmpty {
                    FilterChipBar(filter: $filter)
                        .padding(.horizontal, 16).padding(.top, 8)
                }

                Spacer()
            }
        }
        .onAppear {
            container.locationManager.requestPermission()
            reloadUserPlaces()
            reverseGeocodeCurrent()
            goToMyLocation()
        }
        .onChange(of: appState.mapRefreshTrigger) { _ in
            reloadUserPlaces()
            focusIfNeeded()
        }
        .onChange(of: container.locationManager.currentLocation) { _, newLoc in
            guard let loc = newLoc else { return }
            zoomTo(center: loc.coordinate, meters: 1000)
            reverseGeocodeCurrent()
        }
        .onChange(of: savedAddresses) { _, newValue in
            SavedAddress.save(newValue)
        }
        .onChange(of: addressSearchHistory) { _, newValue in
            SavedAddress.saveSearchHistory(newValue)
        }
        .sheet(isPresented: $showingFilter) { FilterPanelView(filter: $filter) }
        .sheet(item: $selectedUserPlace) { up in
            UserPlaceMarkingSheet(userPlace: up)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingAddressPicker) {
            AddressSearchView(
                currentAddress: $currentAddress, savedAddresses: $savedAddresses,
                searchHistory: $addressSearchHistory,
                onSelect: { addr in
                    showingAddressPicker = false
                    if addr.label == nil, addr.name != "当前位置" {
                        currentAddress = addr.name
                    }
                    if !addressSearchHistory.contains(addr.name) {
                        addressSearchHistory.insert(addr.name, at: 0)
                        if addressSearchHistory.count > 10 { addressSearchHistory.removeLast() }
                    }
                    zoomTo(center: addr.coordinate, meters: 1000)
                }
            )
        }
    }

    // MARK: - 缩放

    private func goToMyLocation() {
        if let loc = container.locationManager.currentLocation {
            zoomTo(center: loc.coordinate, meters: 1000)
            reverseGeocodeCurrent()
        }
    }

    private func zoomIn() { currentZoomLevel = max(100, currentZoomLevel / 2); zoomToCurrent() }
    private func zoomOut() { currentZoomLevel = min(50000, currentZoomLevel * 2); zoomToCurrent() }

    private func zoomToCurrent() {
        let center = appState.mapSearchCenter
            ?? container.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
        zoomTo(center: center, meters: currentZoomLevel)
    }

    private func zoomTo(center: CLLocationCoordinate2D, meters: Double) {
        currentZoomLevel = meters
        appState.mapSearchCenter = center
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .region(MKCoordinateRegion(center: center, latitudinalMeters: meters, longitudinalMeters: meters))
        }
    }

    // MARK: - 数据

    private func reverseGeocodeCurrent() {
        guard let loc = container.locationManager.currentLocation else { return }
        Task {
            do { currentAddress = try await container.mapService.reverseGeocode(coordinate: loc.coordinate) }
            catch { currentAddress = "SOHO复兴广场" }
        }
    }

    private func reloadUserPlaces() { allUserPlaces = container.placeRepository.fetchUserPlaces() }

    private func focusIfNeeded() {
        guard let focusPlaceID = appState.focusPlaceID else { return }
        guard let up = allUserPlaces.first(where: { $0.place?.id == focusPlaceID }),
              let place = up.place else { return }

        let coordinate = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        withAnimation(.easeInOut(duration: 0.35)) {
            zoomTo(center: coordinate, meters: 450)
        }
        appState.selectedTab = .explore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            appState.focusPlaceID = nil
        }
    }

    private func markerPhotoData(for userPlace: CDUserPlace) -> Data? {
        let media = (userPlace.media ?? [])
            .filter { $0.typeValue == MediaType.photo.rawValue }
            .sorted {
                if let lhs = $0.createdAt, let rhs = $1.createdAt, lhs != rhs {
                    return lhs > rhs
                }
                return $0.sortOrder < $1.sortOrder
            }

        return media.first?.thumbnailData
    }
}

// MARK: - 用户地点标记

struct UserPlaceMarker: View {
    let status: PlaceStatus
    let color: Color
    let name: String
    let photoData: Data?

    var body: some View {
        VStack(spacing: 0) {
            if let photoData, let uiImage = UIImage(data: photoData) {
                VStack(spacing: 0) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 62, height: 62)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(.white, lineWidth: 4)
                        )
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

                    Triangle()
                        .fill(.white)
                        .frame(width: 16, height: 12)
                        .offset(y: -2)
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)

                    ZStack {
                        Circle()
                            .fill(color.opacity(0.2))
                            .frame(width: 24, height: 24)
                        Image(systemName: statusIcon)
                            .font(.system(size: status == .visitedNeutral ? 10 : 11, weight: .bold))
                            .foregroundStyle(color)
                    }
                    .offset(y: -3)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 24, height: 24)
                    Image(systemName: statusIcon)
                        .font(.system(size: status == .visitedNeutral ? 10 : 11, weight: .bold))
                        .foregroundStyle(color)
                }
            }
        }
    }

    private var statusIcon: String {
        switch status {
        case .wantToGo: return "bookmark.fill"
        case .visitedGood: return "hand.thumbsup.fill"
        case .visitedBad: return "hand.thumbsdown.fill"
        case .visitedNeutral: return "checkmark"
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let leftTop = CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.08)
        let rightTop = CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.08)
        let leftShoulder = CGPoint(x: rect.midX - rect.width * 0.16, y: rect.maxY - rect.height * 0.34)
        let rightShoulder = CGPoint(x: rect.midX + rect.width * 0.16, y: rect.maxY - rect.height * 0.34)

        path.move(to: leftTop)
        path.addQuadCurve(
            to: rightTop,
            control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.12)
        )
        path.addQuadCurve(
            to: rightShoulder,
            control: CGPoint(x: rect.maxX + rect.width * 0.04, y: rect.maxY * 0.42)
        )
        path.addQuadCurve(
            to: tip,
            control: CGPoint(x: rect.midX + rect.width * 0.08, y: rect.maxY - rect.height * 0.06)
        )
        path.addQuadCurve(
            to: leftShoulder,
            control: CGPoint(x: rect.midX - rect.width * 0.08, y: rect.maxY - rect.height * 0.06)
        )
        path.addQuadCurve(
            to: leftTop,
            control: CGPoint(x: rect.minX - rect.width * 0.04, y: rect.maxY * 0.42)
        )
        path.closeSubpath()
        return path
    }
}

struct DirectionTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: rect.maxY)
        let cornerRadius = min(rect.width, rect.height) * 0.18

        func insetPoint(from point: CGPoint, toward target: CGPoint, by distance: CGFloat) -> CGPoint {
            let dx = target.x - point.x
            let dy = target.y - point.y
            let length = max(0.001, sqrt(dx * dx + dy * dy))
            return CGPoint(
                x: point.x + dx / length * distance,
                y: point.y + dy / length * distance
            )
        }

        let topToRight = insetPoint(from: top, toward: right, by: cornerRadius)
        let rightToTop = insetPoint(from: right, toward: top, by: cornerRadius)
        let rightToLeft = insetPoint(from: right, toward: left, by: cornerRadius)
        let leftToRight = insetPoint(from: left, toward: right, by: cornerRadius)
        let leftToTop = insetPoint(from: left, toward: top, by: cornerRadius)
        let topToLeft = insetPoint(from: top, toward: left, by: cornerRadius)

        var path = Path()
        path.move(to: topToRight)
        path.addQuadCurve(to: rightToTop, control: right)
        path.addLine(to: rightToLeft)
        path.addQuadCurve(to: leftToRight, control: CGPoint(x: rect.midX, y: rect.maxY + cornerRadius * 0.1))
        path.addLine(to: leftToTop)
        path.addQuadCurve(to: topToLeft, control: left)
        path.closeSubpath()
        return path
    }
}

// MARK: - 用户地点编辑 Sheet

struct UserPlaceMarkingSheet: View {
    let userPlace: CDUserPlace
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var lightingMode: LightingMode = .wantToGo
    @State private var visitedMood: VisitedMood?
    @State private var noteText: String = ""
    @State private var visitDate: Date = Date()
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var recordedVoiceMemo: RecordedVoiceMemo?
    @State private var isSaving = false
    @State private var editingCheckIn: CDCheckIn?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                PlaceMemoryComposerCard(
                    place: mapPlace,
                    lightingMode: $lightingMode,
                    visitedMood: $visitedMood,
                    noteText: $noteText,
                    visitDate: $visitDate,
                    selectedPhotoItems: $selectedPhotoItems,
                    selectedImages: $selectedImages,
                    recordedVoiceMemo: $recordedVoiceMemo,
                    isSaving: isSaving,
                    checkInCount: checkIns.count,
                    canChangeMode: canChangeMode,
                    actionTitle: "保存",
                    onSubmit: save
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)

                if !checkIns.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("打卡记录")
                            .font(BubuFont.titleSM)
                            .foregroundStyle(BubuTheme.Text.secondary)
                            .padding(.horizontal, 16)

                        VStack(spacing: 10) {
                            ForEach(Array(checkIns.enumerated()), id: \.element.id) { index, checkIn in
                                SwipeableCheckInRow(
                                    checkIn: checkIn,
                                    isLast: index == checkIns.count - 1,
                                    onEdit: { beginEditing(checkIn) },
                                    onDelete: { delete(checkIn) }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
            }
            .background(BubuTheme.Surface.space)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task { seedFields() }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task { await loadSelectedImages(from: newItems) }
            }
        }
    }

    private var mapPlace: MapPlace {
        let place = userPlace.place
        return MapPlace(
            id: place?.id?.uuidString ?? UUID().uuidString,
            name: place?.name ?? "未知地点",
            address: place?.address,
            coordinate: CLLocationCoordinate2D(latitude: place?.latitude ?? 0, longitude: place?.longitude ?? 0),
            poiID: place?.poiID,
            category: place?.categoryName,
            phone: place?.phone,
            coverImageURL: place?.coverImageURL,
            rating: userPlace.rating > 0 ? Double(userPlace.rating) : nil,
            distance: nil
        )
    }

    private var checkIns: [CDCheckIn] {
        (userPlace.checkIns?.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } ?? [])
    }

    private var canChangeMode: Bool {
        let status = PlaceStatus(rawValue: userPlace.statusValue) ?? .wantToGo
        return status == .wantToGo
    }

    private func seedFields() {
        let status = PlaceStatus(rawValue: userPlace.statusValue) ?? .wantToGo
        lightingMode = status == .wantToGo ? .wantToGo : .visited
        editingCheckIn = nil
        noteText = ""
        visitDate = Date()
        visitedMood = nil
        selectedPhotoItems = []
        selectedImages = []
        recordedVoiceMemo = nil
    }

    private func save() {
        isSaving = true
        if let editingCheckIn {
            container.placeRepository.updateCheckIn(
                editingCheckIn,
                mood: selectedMoodTag,
                note: noteText.isEmpty ? nil : noteText,
                visitDate: visitDate,
                images: selectedImages,
                voiceMemoURL: recordedVoiceMemo?.fileURL
            )
            self.editingCheckIn = nil
        } else {
            container.placeRepository.updateMark(
                userPlace: userPlace,
                status: selectedStatus,
                mood: selectedMoodTag,
                note: noteText.isEmpty ? nil : noteText,
                visitDate: visitDate,
                images: selectedImages,
                voiceMemoURL: recordedVoiceMemo?.fileURL
            )
        }
        appState.mapRefreshTrigger += 1
        appState.focusPlaceID = userPlace.place?.id
        isSaving = false
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

    private func beginEditing(_ checkIn: CDCheckIn) {
        editingCheckIn = checkIn
        lightingMode = .visited
        noteText = checkIn.note ?? ""
        visitDate = checkIn.visitDate ?? checkIn.timestamp ?? Date()
        visitedMood = switch checkIn.mood {
        case MoodTag.happy.rawValue: .good
        case MoodTag.calm.rawValue: .neutral
        case MoodTag.disappointed.rawValue: .bad
        default: nil
        }
        selectedPhotoItems = []
        selectedImages = existingImages(for: checkIn)
        recordedVoiceMemo = nil
    }

    private func delete(_ checkIn: CDCheckIn) {
        container.placeRepository.deleteCheckIn(checkIn)
        appState.mapRefreshTrigger += 1
    }

    private func existingImages(for checkIn: CDCheckIn) -> [UIImage] {
        ((checkIn.media ?? [])
            .filter { $0.typeValue == MediaType.photo.rawValue }
            .sorted { $0.sortOrder < $1.sortOrder })
            .compactMap { media in
                if let data = media.thumbnailData, let image = UIImage(data: data) {
                    return image
                }
                if let url = media.localFileURL,
                   let data = try? Data(contentsOf: url),
                   let image = UIImage(data: data) {
                    return image
                }
                return nil
            }
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

struct CheckInRowView: View {
    let checkIn: CDCheckIn
    let isLast: Bool
    @StateObject private var voicePreviewPlayer = AudioPreviewPlayer()

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                Text(dayText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(BubuTheme.Text.tertiary)
                Text(monthText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BubuTheme.Text.tertiary)

                ZStack {
                    Circle()
                        .fill(BubuTheme.Surface.surface2)
                        .frame(width: 18, height: 18)
                    Circle()
                        .fill(moodTint)
                        .frame(width: 10, height: 10)
                }

                if !isLast {
                    Rectangle()
                        .fill(BubuTheme.Surface.surface3)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 2)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Text(moodEmoji)
                        .font(.system(size: 16))

                    Spacer()

                    if let ts = checkIn.timestamp {
                        Text(ts.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(BubuTheme.Text.tertiary)
                    }
                }

                if let note = checkIn.note, !note.isEmpty {
                    Text(note)
                        .font(BubuFont.bodySM)
                        .foregroundStyle(BubuTheme.Text.secondary)
                        .lineSpacing(2)
                } else if photoMediaItems.isEmpty && !hasVoiceMemo {
                    Text("默默地打卡了")
                        .font(BubuFont.bodySM)
                        .foregroundStyle(BubuTheme.Text.tertiary)
                }

                if hasVoiceMemo {
                    if let voiceMedia = voiceMemoMedia {
                        Button {
                            voicePreviewPlayer.togglePlayback(url: voiceMedia.localFileURL!)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: voicePreviewPlayer.isPlaying ? "speaker.wave.2.fill" : "waveform")
                                    .font(.system(size: 11, weight: .medium))
                                Text(voiceDurationLabel(for: voiceMedia))
                                    .font(BubuFont.caption)
                            }
                            .foregroundStyle(BubuTheme.Primary.green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(BubuTheme.Primary.green.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .stroke(BubuTheme.Primary.green.opacity(0.24), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !photoMediaItems.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photoMediaItems.enumerated()), id: \.element.id) { _, media in
                                checkInImage(for: media)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(BubuTheme.Surface.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var moodEmoji: String {
        MoodTag.allCases.first(where: { $0.rawValue == checkIn.mood })?.emoji ?? "📝"
    }

    private var moodTint: Color {
        switch checkIn.mood {
        case MoodTag.happy.rawValue:
            return BubuTheme.Primary.green
        case MoodTag.calm.rawValue:
            return BubuTheme.Semantic.visitedNeutral
        case MoodTag.disappointed.rawValue:
            return BubuTheme.Semantic.visitedBad
        default:
            return BubuTheme.Text.tertiary
        }
    }

    private var dayText: String {
        (checkIn.visitDate ?? checkIn.timestamp ?? Date()).formatted(.dateTime.day())
    }

    private var monthText: String {
        (checkIn.visitDate ?? checkIn.timestamp ?? Date()).formatted(.dateTime.month(.abbreviated))
    }

    private var mediaItems: [CDMedia] {
        (checkIn.media ?? [])
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
            }
    }

    private var photoMediaItems: [CDMedia] {
        mediaItems.filter { $0.typeValue == MediaType.photo.rawValue }
    }

    private var hasVoiceMemo: Bool {
        mediaItems.contains { $0.typeValue == MediaType.voiceNote.rawValue }
    }

    private var voiceMemoMedia: CDMedia? {
        mediaItems.first(where: { $0.typeValue == MediaType.voiceNote.rawValue && $0.localFileURL != nil })
    }

    private func voiceDurationLabel(for media: CDMedia) -> String {
        guard let url = media.localFileURL,
              let player = try? AVAudioPlayer(contentsOf: url) else {
            return "语音"
        }
        let seconds = max(1, Int(player.duration.rounded()))
        return "\(seconds)秒"
    }

    @ViewBuilder
    private func checkInImage(for media: CDMedia) -> some View {
        if let thumbnailData = media.thumbnailData,
           let image = UIImage(data: thumbnailData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else if let url = media.localFileURL,
                  let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct SwipeableCheckInRow: View {
    let checkIn: CDCheckIn
    let isLast: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offsetX: CGFloat = 0

    private let actionWidth: CGFloat = 132

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                        offsetX = 0
                    }
                    onEdit()
                } label: {
                    actionButton("编辑", systemName: "square.and.pencil", color: BubuTheme.Primary.green.opacity(0.2))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                        offsetX = 0
                    }
                    onDelete()
                } label: {
                    actionButton("删除", systemName: "trash", color: BubuTheme.Semantic.visitedBad.opacity(0.22))
                }
                .buttonStyle(.plain)
            }
            .frame(width: actionWidth)
            .opacity(offsetX == 0 ? 0 : 1)

            CheckInRowView(checkIn: checkIn, isLast: isLast)
                .offset(x: offsetX)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation.width
                            if translation < 0 {
                                offsetX = max(translation, -actionWidth)
                            } else if offsetX < 0 {
                                offsetX = min(0, -actionWidth + translation)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                                offsetX = value.translation.width < -50 ? -actionWidth : 0
                            }
                        }
                )
                .onTapGesture {
                    if offsetX != 0 {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                            offsetX = 0
                        }
                    }
                }
        }
        .clipped()
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemName: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
        }
        .foregroundStyle(BubuTheme.Text.ink)
        .frame(width: 56)
        .frame(maxHeight: .infinity)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - 地址/筛选等

struct SavedAddress: Identifiable, Codable, Equatable {
    var id = UUID(); let name: String; let lat: Double; let lon: Double; let label: String?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    private static let savedAddressesKey = "bubu.saved_addresses"
    private static let addressSearchHistoryKey = "bubu.address_search_history"
    private static let defaultAddresses: [SavedAddress] = [
        SavedAddress(name: "SOHO复兴广场", lat: 31.215070, lon: 121.474434, label: "办公室"),
        SavedAddress(name: "新天地", lat: 31.219568, lon: 121.475262, label: "附近"),
        SavedAddress(name: "外滩", lat: 31.239666, lon: 121.490012, label: "景点"),
        SavedAddress(name: "陆家嘴", lat: 31.235929, lon: 121.499740, label: "商圈")
    ]

    static func load() -> [SavedAddress] {
        if let data = UserDefaults.standard.data(forKey: savedAddressesKey),
           let decoded = try? JSONDecoder().decode([SavedAddress].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return defaultAddresses
    }

    static func save(_ addresses: [SavedAddress]) {
        guard let data = try? JSONEncoder().encode(addresses) else { return }
        UserDefaults.standard.set(data, forKey: savedAddressesKey)
    }

    static func loadSearchHistory() -> [String] {
        UserDefaults.standard.stringArray(forKey: addressSearchHistoryKey) ?? []
    }

    static func saveSearchHistory(_ history: [String]) {
        UserDefaults.standard.set(history, forKey: addressSearchHistoryKey)
    }
}

struct SearchResultRow: View {
    let place: MapPlace
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill").font(.title3).foregroundStyle(BubuTheme.Primary.green)
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name).font(BubuFont.titleMD).foregroundStyle(BubuTheme.Text.ink)
                if let a = place.address { Text(a).font(BubuFont.caption).foregroundStyle(BubuTheme.Text.secondary).lineLimit(1) }
            }
            Spacer()
            if let c = place.category { Text(c).font(BubuFont.caption).foregroundStyle(BubuTheme.Primary.green).padding(.horizontal,8).padding(.vertical,4).background(BubuTheme.Primary.green.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius:6)) }
        }.padding(.vertical,4)
    }
}

struct AddressSearchView: View {
    @Binding var currentAddress: String; @Binding var savedAddresses: [SavedAddress]; @Binding var searchHistory: [String]
    let onSelect: (SavedAddress) -> Void
    @Environment(\.dismiss) private var dismiss; @EnvironmentObject var container: AppContainer; @EnvironmentObject var appState: AppState
    @State private var query = ""; @State private var searchResults: [MapPlace] = []; @State private var isSearching = false
    @State private var locationAddress = "" // 当前位置的真实地址

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(BubuTheme.Text.tertiary); TextField("搜索地址...", text: $query).font(BubuFont.body).foregroundStyle(BubuTheme.Text.ink).onSubmit { searchAddress() } }
                    .padding(12).background(BubuTheme.Surface.surface1).clipShape(RoundedRectangle(cornerRadius: BubuRadius.md)).padding(16)

                if isSearching { Spacer(); ProgressView().tint(BubuTheme.Primary.green); Spacer() }
                else if !searchResults.isEmpty {
                    List {
                        Section("搜索结果") {
                            currentLocationRow
                            ForEach(searchResults) { p in
                                Button {
                                    let a = SavedAddress(name: p.name, lat: p.coordinate.latitude, lon: p.coordinate.longitude, label: nil)
                                    if !savedAddresses.contains(where: { $0.name == p.name }) { savedAddresses.append(a) }
                                    onSelect(a)
                                } label: { SearchResultRow(place: p) }.listRowBackground(BubuTheme.Surface.surface1)
                            }
                        }
                    }.listStyle(.plain)
                } else {
                    List {
                        Section {
                            currentLocationRow
                        }
                        Section("常用地址") { ForEach(savedAddresses) { a in Button { onSelect(a) } label: { AddressRow(addr: a) }.listRowBackground(BubuTheme.Surface.surface1) } }
                        if !searchHistory.isEmpty {
                            Section("搜索历史") { ForEach(searchHistory, id: \.self) { h in Button { query = h; searchAddress() } label: { HStack { Image(systemName: "clock").font(.caption).foregroundStyle(BubuTheme.Text.tertiary); Text(h).font(BubuFont.body).foregroundStyle(BubuTheme.Text.secondary) } }.listRowBackground(BubuTheme.Surface.surface1) } }
                        }
                    }.scrollContentBackground(.hidden)
                }
            }.background(BubuTheme.Surface.space).navigationTitle("选择位置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
                .task { resolveAddress() }
        }
    }

    private var currentLocationRow: some View {
        Button {
            if let loc = container.locationManager.currentLocation {
                let addr = SavedAddress(name: locationAddress.isEmpty ? "当前位置" : locationAddress, lat: loc.coordinate.latitude, lon: loc.coordinate.longitude, label: nil)
                onSelect(addr)
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(BubuTheme.Primary.green.opacity(0.15)).frame(width: 32, height: 32)
                    Image(systemName: "location.north.line.fill").font(.system(size: 14)).foregroundStyle(BubuTheme.Primary.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(locationAddress.isEmpty ? "正在获取位置..." : locationAddress)
                        .font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.ink)
                        .lineLimit(1)
                    Text("当前位置").font(.system(size: 11)).foregroundStyle(BubuTheme.Text.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(BubuTheme.Text.tertiary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(BubuTheme.Surface.surface1)
    }

    private func resolveAddress() {
        guard let loc = container.locationManager.currentLocation else { return }
        Task {
            do { locationAddress = try await container.mapService.reverseGeocode(coordinate: loc.coordinate) }
            catch { locationAddress = "" }
        }
    }

    private func searchAddress() {
        guard !query.isEmpty else { return }
        isSearching = true
        let center = appState.mapSearchCenter
            ?? container.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
        Task { do { searchResults = try await container.mapService.searchPlaces(query: query, region: MapRegion(center: center, radius: 100000), filters: nil) } catch { searchResults = [] }; isSearching = false }
    }
}

struct AddressRow: View {
    let addr: SavedAddress
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: addr.label == "办公室" ? "building.2.fill" : "mappin.circle.fill").font(.title3).foregroundStyle(BubuTheme.Primary.green)
            VStack(alignment: .leading, spacing: 2) { Text(addr.name).font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.ink); if let l = addr.label { Text(l).font(BubuFont.caption).foregroundStyle(BubuTheme.Text.tertiary) } }
        }
    }
}

// MARK: - 筛选面板

struct FilterPanelView: View {
    @Binding var filter: PlaceFilter; @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("地点状态").font(BubuFont.titleMD).foregroundStyle(BubuTheme.Text.ink)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PlaceStatus.allCases, id: \.rawValue) { s in
                        FilterToggle(label: s.displayName, icon: s.iconName, color: BubuTheme.colorForStatus(s), isOn: filter.statuses.contains(s)) { if filter.statuses.contains(s) { filter.statuses.remove(s) } else { filter.statuses.insert(s) } }
                    }
                }
                Divider().background(BubuTheme.Text.tertiary)
                Text("地点类别").font(BubuFont.titleMD).foregroundStyle(BubuTheme.Text.ink)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(PlaceCategoryType.allCases, id: \.self) { c in
                        FilterToggle(label: c.rawValue, icon: c.iconName, color: c.color, isOn: filter.categories.contains(c)) { if filter.categories.contains(c) { filter.categories.remove(c) } else { filter.categories.insert(c) } }
                    }
                }
                Divider().background(BubuTheme.Text.tertiary)
                Toggle(isOn: $filter.hideDisliked) { HStack { Image(systemName: "hand.thumbsdown.fill").foregroundStyle(BubuTheme.Semantic.visitedBad); Text("隐藏踩雷").font(BubuFont.titleMD).foregroundStyle(BubuTheme.Text.ink) } }.tint(BubuTheme.Primary.green)
                Spacer()
                HStack(spacing: 12) { Button("重置") { withAnimation { filter = PlaceFilter() } }.buttonStyle(BubuButtonModifier(variant: .secondary)).frame(maxWidth: .infinity); Button("应用") { dismiss() }.buttonStyle(BubuButtonModifier(variant: .primary)).frame(maxWidth: .infinity) }
            }.padding(20).background(BubuTheme.Surface.space).navigationTitle("筛选").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct FilterToggle: View {
    let label: String; let icon: String; let color: Color; let isOn: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { HStack(spacing: 6) { Image(systemName: icon); Text(label) }.font(BubuFont.titleSM).foregroundStyle(isOn ? BubuTheme.readableText(on: color) : BubuTheme.Text.secondary).padding(.horizontal,12).padding(.vertical,8).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(isOn ? color : BubuTheme.Surface.surface1).overlay(RoundedRectangle(cornerRadius: 8).stroke(isOn ? Color.clear : BubuTheme.Text.tertiary, lineWidth:1))) }
    }
}

struct FilterChipBar: View {
    @Binding var filter: PlaceFilter
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { if filter.hideDisliked { FilterTag(text: "隐藏踩雷", color: BubuTheme.Semantic.visitedBad) { filter.hideDisliked = false } }; ForEach(Array(filter.statuses), id: \.self) { s in FilterTag(text: s.displayName, color: BubuTheme.colorForStatus(s)) { filter.statuses.remove(s) } }; ForEach(Array(filter.categories), id: \.self) { c in FilterTag(text: c.rawValue, color: c.color) { filter.categories.remove(c) } }; Button("清除") { withAnimation { filter = PlaceFilter() } }.font(BubuFont.caption).foregroundStyle(BubuTheme.Text.tertiary) } }
    }
}

struct FilterTag: View {
    let text: String; let color: Color; let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) { Text(text).font(BubuFont.titleSM); Button(action: onRemove) { Image(systemName: "xmark").font(.system(size:8,weight:.bold)) } }.foregroundStyle(BubuTheme.Text.onPrimary).padding(.horizontal,10).padding(.vertical,6).background(color.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: BubuRadius.full))
    }
}
