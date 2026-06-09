import SwiftUI
import CoreLocation
import MapKit

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
    @State private var addressSearchHistory: [String] = []
    @State private var currentZoomLevel: Double = 1000
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            Map(position: $camera, interactionModes: .all, selection: $selectedAnnotationID) {
                // 当前位置（头像风格浮标）
                if let loc = container.locationManager.currentLocation {
                    Annotation("", coordinate: loc.coordinate) {
                        ZStack {
                            Circle().fill(BubuTheme.Primary.green.opacity(0.2)).frame(width: 40, height: 40)
                            Circle().fill(BubuTheme.Primary.green.opacity(0.1)).frame(width: 56, height: 56)
                            ZStack {
                                Circle()
                                    .fill(BubuTheme.Primary.green)
                                    .frame(width: 30, height: 30)
                                    .shadow(color: BubuTheme.Primary.green.opacity(0.3), radius: 6, y: 2)
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(BubuTheme.Text.onPrimary)
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
                        UserPlaceMarker(status: status, color: BubuTheme.mapMarkerColor(for: status), name: p?.name ?? "")
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
                    withAnimation(.easeInOut(duration: 0.4)) { zoomTo(center: c, meters: 500) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { selectedUserPlace = up }
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
                        .background(.ultraThinMaterial).clipShape(Capsule())
                    }

                    Button { goToMyLocation() } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 14)).foregroundStyle(BubuTheme.Text.ink)
                            .frame(width: 38, height: 38).background(.ultraThinMaterial).clipShape(Circle())
                    }

                    Spacer()

                    VStack(spacing: 1) {
                        Button { zoomIn() } label: {
                            Image(systemName: "plus").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BubuTheme.Text.ink).frame(width: 34, height: 34)
                                .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Divider().frame(width: 22)
                        Button { zoomOut() } label: {
                            Image(systemName: "minus").font(.system(size: 14, weight: .medium))
                                .foregroundStyle(BubuTheme.Text.ink).frame(width: 34, height: 34)
                                .background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Button { showingFilter.toggle() } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(filter.isEmpty ? BubuTheme.Text.ink : BubuTheme.Primary.green)
                            .frame(width: 38, height: 38)
                            .background(filter.isEmpty ? .ultraThinMaterial : Material.regular).clipShape(Circle())
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
        }
        .onChange(of: container.locationManager.currentLocation) { _, newLoc in
            guard let loc = newLoc else { return }
            zoomTo(center: loc.coordinate, meters: 1000)
            reverseGeocodeCurrent()
        }
        .sheet(isPresented: $showingFilter) { FilterPanelView(filter: $filter) }
        .sheet(item: $selectedUserPlace) { up in UserPlaceDetailSheet(userPlace: up) }
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
        let center = container.locationManager.currentLocation?.coordinate
            ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
        withAnimation(.easeInOut(duration: 0.3)) {
            camera = .region(MKCoordinateRegion(center: center, latitudinalMeters: currentZoomLevel, longitudinalMeters: currentZoomLevel))
        }
    }

    private func zoomTo(center: CLLocationCoordinate2D, meters: Double) {
        currentZoomLevel = meters
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
}

// MARK: - 用户地点标记

struct UserPlaceMarker: View {
    let status: PlaceStatus
    let color: Color
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(color.opacity(0.25)).frame(width: 32, height: 32)
                Image(systemName: statusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(name)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private var statusIcon: String {
        switch status {
        case .wantToGo: return "bookmark.fill"
        case .visitedGood: return "hand.thumbsup.fill"
        case .visitedBad: return "hand.thumbsdown.fill"
        case .visitedNeutral: return "checkmark.circle.fill"
        }
    }
}

// MARK: - 用户地点详情 Sheet

struct UserPlaceDetailSheet: View {
    let userPlace: CDUserPlace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let status = PlaceStatus(rawValue: userPlace.statusValue) ?? .wantToGo
        let place = userPlace.place
        let checkIns = (userPlace.checkIns?.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } ?? [])

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: {
                            switch status {
                            case .wantToGo: return "bookmark.fill"
                            case .visitedGood: return "hand.thumbsup.fill"
                            case .visitedBad: return "hand.thumbsdown.fill"
                            case .visitedNeutral: return "checkmark.circle.fill"
                            }
                        }())
                            .foregroundStyle(BubuTheme.colorForStatus(status))
                        Text(status.displayName)
                            .font(BubuFont.titleSM).foregroundStyle(BubuTheme.colorForStatus(status))
                        Spacer()
                    }
                    .padding(12).background(BubuTheme.colorForStatus(status).opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))

                    Text(place?.name ?? "未知地点").font(BubuFont.titleXL).foregroundStyle(BubuTheme.Text.ink)
                    if let addr = place?.address {
                        Label(addr, systemImage: "location.fill").font(BubuFont.body).foregroundStyle(BubuTheme.Text.secondary)
                    }

                    Divider().background(BubuTheme.Text.tertiary)

                    if !checkIns.isEmpty {
                        Text("打卡记录").font(BubuFont.titleLG).foregroundStyle(BubuTheme.Text.ink)
                        ForEach(checkIns, id: \.id) { checkIn in
                            CheckInRowView(checkIn: checkIn)
                        }
                    }
                    if userPlace.rating > 0 {
                        HStack {
                            Text("评分").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                            ForEach(1...5, id: \.self) { i in
                                Image(systemName: i <= userPlace.rating ? "star.fill" : "star")
                                    .font(.caption).foregroundStyle(i <= userPlace.rating ? BubuTheme.Semantic.visitedNeutral : BubuTheme.Text.tertiary)
                            }
                        }
                    }
                    if let review = userPlace.reviewText, !review.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("笔记").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                            Text(review).font(BubuFont.body).foregroundStyle(BubuTheme.Text.ink)
                        }
                    }
                    if let visitDate = userPlace.visitDate {
                        HStack {
                            Text("到访").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                            Text(visitDate.formatted(date: .long, time: .omitted)).font(BubuFont.body).foregroundStyle(BubuTheme.Text.ink)
                        }
                    }
                    Spacer()
                }.padding(20)
            }
            .background(BubuTheme.Surface.space).navigationTitle("地点详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

struct CheckInRowView: View {
    let checkIn: CDCheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let mood = checkIn.mood {
                    Text(
                        MoodTag.allCases.first(where: { $0.rawValue == mood })?.emoji ?? "📝"
                    ).font(.title3)
                }
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= checkIn.ratingAtTime ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(i <= checkIn.ratingAtTime ? BubuTheme.Semantic.visitedNeutral : BubuTheme.Text.tertiary)
                    }
                }
                Spacer()
                if let ts = checkIn.timestamp {
                    Text(ts.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(BubuTheme.Text.tertiary)
                }
            }
            if let note = checkIn.note, !note.isEmpty {
                Text(note).font(BubuFont.caption).foregroundStyle(BubuTheme.Text.secondary).lineLimit(3)
            }
        }
        .padding(14).background(BubuTheme.Surface.surface1).clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
    }
}

// MARK: - 地址/筛选等

struct SavedAddress: Identifiable, Codable {
    var id = UUID(); let name: String; let lat: Double; let lon: Double; let label: String?
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    static func load() -> [SavedAddress] {
        [SavedAddress(name: "SOHO复兴广场", lat: 31.215070, lon: 121.474434, label: "办公室"),
         SavedAddress(name: "新天地", lat: 31.219568, lon: 121.475262, label: "附近"),
         SavedAddress(name: "外滩", lat: 31.239666, lon: 121.490012, label: "景点"),
         SavedAddress(name: "陆家嘴", lat: 31.235929, lon: 121.499740, label: "商圈")]
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
    @Environment(\.dismiss) private var dismiss; @EnvironmentObject var container: AppContainer
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
        let center = container.locationManager.currentLocation?.coordinate
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
        Button(action: action) { HStack(spacing: 6) { Image(systemName: icon); Text(label) }.font(BubuFont.titleSM).foregroundStyle(isOn ? .white : BubuTheme.Text.secondary).padding(.horizontal,12).padding(.vertical,8).frame(maxWidth: .infinity).background(RoundedRectangle(cornerRadius: 8).fill(isOn ? color : BubuTheme.Surface.surface1).overlay(RoundedRectangle(cornerRadius: 8).stroke(isOn ? Color.clear : BubuTheme.Text.tertiary, lineWidth:1))) }
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
        HStack(spacing: 4) { Text(text).font(BubuFont.titleSM); Button(action: onRemove) { Image(systemName: "xmark").font(.system(size:8,weight:.bold)) } }.foregroundStyle(.white).padding(.horizontal,10).padding(.vertical,6).background(color.opacity(0.8)).clipShape(RoundedRectangle(cornerRadius: BubuRadius.full))
    }
}