import SwiftUI
import CoreLocation
import MapKit

// MARK: - 探索地图页（全屏地图 + 顶部浮层）

struct ExploreMapView: View {
    @EnvironmentObject var container: AppContainer
    @EnvironmentObject var appState: AppState
    @State private var camera: MapCameraPosition = .automatic
    @State private var showingFilter = false
    @State private var showingSearchResults = false
    @State private var filter = PlaceFilter()
    @State private var searchResults: [MapPlace] = []
    @State private var selectedPlace: MapPlace?
    @State private var nearbyPlaces: [MapPlace] = []
    @State private var userPlaces: [CDUserPlace] = []
    @State private var selectedAnnotationID: String?
    @State private var currentAddress = "SOHO复兴广场"
    @State private var showingAddressPicker = false
    @State private var savedAddresses = SavedAddress.load()
    @State private var addressSearchHistory: [String] = []
    @State private var pendingPlace: MapPlace?

    var body: some View {
        ZStack {
            // 全屏地图
            Map(position: $camera, interactionModes: .all, selection: $selectedAnnotationID) {
                if let loc = container.locationManager.currentLocation {
                    Annotation("", coordinate: loc.coordinate) {
                        ZStack {
                            Circle().fill(BubuTheme.Primary.green.opacity(0.2)).frame(width: 24, height: 24)
                            Circle().fill(BubuTheme.Primary.green).frame(width: 10, height: 10)
                            Circle().stroke(.white, lineWidth: 2).frame(width: 10, height: 10)
                        }
                    }
                }

                ForEach(userPlaces, id: \.id) { up in
                    let p = up.place
                    let coord = CLLocationCoordinate2D(latitude: p?.latitude ?? 0, longitude: p?.longitude ?? 0)
                    let status = PlaceStatus(rawValue: up.statusValue) ?? .wantToGo
                    Marker(p?.name ?? "地点", systemImage: status == .wantToGo ? "bookmark.fill" : "mappin.circle.fill", coordinate: coord)
                        .tint(BubuTheme.mapMarkerColor(for: status))
                        .tag("user_\(p?.id?.uuidString ?? "")")
                }

                ForEach(nearbyPlaces) { place in
                    Marker(place.name, systemImage: categoryMarkerIcon(for: place.category), coordinate: place.coordinate)
                        .tint(BubuTheme.Primary.green.opacity(0.5))
                        .tag("nearby_\(place.id)")
                }

                ForEach(searchResults) { place in
                    Marker(place.name, systemImage: categoryMarkerIcon(for: place.category), coordinate: place.coordinate)
                        .tint(BubuTheme.Primary.green)
                        .tag("search_\(place.id)")
                }
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .all))
            .mapControls { MapCompass() }
            .onChange(of: selectedAnnotationID) { _, tagID in
                guard let tagID, !tagID.isEmpty else { return }
                let (coord, place) = lookupAnnotation(tagID)
                guard let coord, let place else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    camera = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 500, longitudinalMeters: 500))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { selectedPlace = place }
            }

            // 顶部浮层：地址胶囊 + 筛选
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    // 地址胶囊（点击切换位置）
                    Button { showingAddressPicker = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.caption2)
                                .foregroundStyle(BubuTheme.Primary.green)
                            Text(currentAddress)
                                .font(BubuFont.titleSM)
                                .foregroundStyle(BubuTheme.Text.ink)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(BubuTheme.Text.tertiary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                    }

                    // 定位按钮
                    Button { goToMyLocation() } label: {
                        Image(systemName: "location.north.line.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(BubuTheme.Text.ink)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Spacer()

                    // 筛选按钮
                    Button { showingFilter.toggle() } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(filter.isEmpty ? BubuTheme.Text.ink : BubuTheme.Primary.green)
                            .frame(width: 38, height: 38)
                            .background(filter.isEmpty ? .ultraThinMaterial : Material.regular)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)  // 避开灵动岛 + 状态栏

                // 筛选标签条
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
            loadNearby()
            reverseGeocodeCurrent()
            goToMyLocation()
        }
        .onChange(of: container.locationManager.currentLocation) { _, newLoc in
            guard let loc = newLoc else { return }
            withAnimation { camera = .region(MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)) }
            reverseGeocodeCurrent()
        }
        .onChange(of: appState.pendingSearchPlace) { _, place in
            guard let place else { return }
            pendingPlace = place
            appState.pendingSearchPlace = nil
        }
        .onChange(of: pendingPlace) { _, place in
            guard let place else { return }
            searchResults = [place]
            withAnimation { camera = .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                selectedPlace = place
            }
        }
        .sheet(isPresented: $showingFilter) { FilterPanelView(filter: $filter) }
        .sheet(item: $selectedPlace) { place in PlaceDetailSheet(place: place) }
        .sheet(isPresented: $showingSearchResults) {
            SearchResultsSheet(results: $searchResults) { place in
                showingSearchResults = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { selectedPlace = place }
            }
        }
        .sheet(isPresented: $showingAddressPicker) {
            AddressSearchView(
                currentAddress: $currentAddress, savedAddresses: $savedAddresses,
                searchHistory: $addressSearchHistory,
                onSelect: { addr in
                    showingAddressPicker = false; currentAddress = addr.name
                    if !addressSearchHistory.contains(addr.name) {
                        addressSearchHistory.insert(addr.name, at: 0)
                        if addressSearchHistory.count > 10 { addressSearchHistory.removeLast() }
                    }
                    withAnimation { camera = .region(MKCoordinateRegion(center: addr.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)) }
                    nearbyPlaces = []; searchAtLocation(addr.coordinate)
                }
            )
        }
    }

    private func goToMyLocation() {
        if let loc = container.locationManager.currentLocation {
            withAnimation { camera = .region(MKCoordinateRegion(center: loc.coordinate, latitudinalMeters: 1000, longitudinalMeters: 1000)) }
            reverseGeocodeCurrent()
        }
    }

    private func reverseGeocodeCurrent() {
        guard let loc = container.locationManager.currentLocation else { return }
        Task {
            do { currentAddress = try await container.mapService.reverseGeocode(coordinate: loc.coordinate) }
            catch { currentAddress = "SOHO复兴广场" }
        }
    }

    private func reloadUserPlaces() { userPlaces = container.placeRepository.fetchUserPlaces() }

    private func categoryMarkerIcon(for category: String?) -> String {
        guard let cat = category else { return "mappin" }
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
        if cat.contains("甜品") || cat.contains("糕点") { return "birthday.cake" }
        return "mappin"
    }

    private func loadNearby() {
        if let loc = container.locationManager.currentLocation { searchAtLocation(loc.coordinate) }
    }

    private func searchAtLocation(_ coord: CLLocationCoordinate2D) {
        Task {
            async let food = container.mapService.searchNearby(coordinate: coord, radius: 1500, category: .restaurant)
            async let cafe = container.mapService.searchNearby(coordinate: coord, radius: 1500, category: .cafe)
            async let bar = container.mapService.searchNearby(coordinate: coord, radius: 1500, category: .bar)
            var all: [MapPlace] = []
            for items in [try? await food, try? await cafe, try? await bar] {
                all.append(contentsOf: items?.prefix(5) ?? [])
            }
            var seen = Set<String>()
            nearbyPlaces = all.filter { seen.insert($0.id).inserted }
        }
    }

    private func lookupAnnotation(_ tagID: String) -> (CLLocationCoordinate2D?, MapPlace?) {
        if tagID.hasPrefix("search_") {
            let id = String(tagID.dropFirst(7))
            if let p = searchResults.first(where: { $0.id == id }) { return (p.coordinate, p) }
        }
        if tagID.hasPrefix("nearby_") {
            let id = String(tagID.dropFirst(7))
            if let p = nearbyPlaces.first(where: { $0.id == id }) { return (p.coordinate, p) }
        }
        if tagID.hasPrefix("user_") {
            let id = String(tagID.dropFirst(5))
            if let up = userPlaces.first(where: { $0.place?.id?.uuidString == id }), let p = up.place {
                let c = CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
                return (c, MapPlace(id: p.id?.uuidString ?? "", name: p.name ?? "", address: p.address, coordinate: c, poiID: p.poiID, category: p.categoryName, phone: p.phone, coverImageURL: p.coverImageURL, rating: nil, distance: nil))
            }
        }
        return (nil, nil)
    }
}

// MARK: - 地点详情 Sheet（含打卡表单）

struct PlaceDetailSheet: View {
    let place: MapPlace
    @EnvironmentObject var container: AppContainer; @Environment(\.dismiss) private var dismiss
    @State private var address: String?
    @State private var selectedStatus: PlaceStatus = .wantToGo
    @State private var showCheckInForm = false
    @State private var savedUserPlace: CDUserPlace?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(place.name).font(BubuFont.titleXL).foregroundStyle(BubuTheme.Text.ink)
                    if let a = address { Label(a, systemImage: "location.fill").font(BubuFont.body).foregroundStyle(BubuTheme.Text.secondary) }
                    if let c = place.category { Label(c, systemImage: "tag.fill").font(BubuFont.caption).foregroundStyle(BubuTheme.Primary.green).padding(.horizontal,10).padding(.vertical,6).background(BubuTheme.Primary.green.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: BubuRadius.sm)) }
                    Divider().background(BubuTheme.Text.tertiary)

                    Text("标记状态").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.ink)
                    HStack(spacing: 12) {
                        ForEach(PlaceStatus.allCases, id: \.rawValue) { s in
                            Button { selectedStatus = s } label: {
                                VStack(spacing: 6) { Image(systemName: s.iconName).font(.title3); Text(s.displayName).font(BubuFont.caption) }
                                    .foregroundStyle(selectedStatus == s ? .white : BubuTheme.Text.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical,12)
                                    .background(RoundedRectangle(cornerRadius: BubuRadius.md).fill(selectedStatus == s ? BubuTheme.colorForStatus(s) : BubuTheme.Surface.surface1))
                            }
                        }
                    }

                    if showCheckInForm, let up = savedUserPlace {
                        Divider().background(BubuTheme.Text.tertiary)
                        CheckInFormView(userPlace: up) { dismiss() }
                    }

                    if !showCheckInForm {
                        Button("保存到收藏") { savePlace() }
                            .frame(maxWidth: .infinity).buttonStyle(BubuButtonModifier(variant: .primary))
                    }
                }.padding(20)
            }
            .background(BubuTheme.Surface.space).navigationTitle("地点详情").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task { do { address = try await container.mapService.reverseGeocode(coordinate: place.coordinate) } catch { address = place.address } }
        .interactiveDismissDisabled(showCheckInForm)
    }

    private func savePlace() {
        let f = container.placeRepository.fetchFolders().first
        let up = container.placeRepository.addPlace(name: place.name, address: address, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude, status: selectedStatus, folder: f, sourceType: .manual, sourceURL: nil)
        if selectedStatus == .wantToGo {
            dismiss()
        } else {
            savedUserPlace = up
            withAnimation { showCheckInForm = true }
        }
    }
}

// MARK: - 打卡表单

struct CheckInFormView: View {
    let userPlace: CDUserPlace
    let onDone: () -> Void
    @EnvironmentObject var container: AppContainer

    @State private var selectedMood: MoodTag?
    @State private var rating: Int = 0
    @State private var note: String = ""
    @State private var visitDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("打卡记录").font(BubuFont.titleLG).foregroundStyle(BubuTheme.Text.ink)

            VStack(alignment: .leading, spacing: 10) {
                Text("心情").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 8) {
                    ForEach(MoodTag.allCases, id: \.self) { mood in
                        Button {
                            selectedMood = selectedMood == mood ? nil : mood
                        } label: {
                            VStack(spacing: 4) {
                                Text(mood.emoji).font(.title2)
                                Text(mood.rawValue).font(.system(size: 10))
                            }
                            .foregroundStyle(selectedMood == mood ? .white : BubuTheme.Text.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: BubuRadius.sm)
                                .fill(selectedMood == mood ? BubuTheme.Primary.green : BubuTheme.Surface.surface1))
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("评分").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(star <= rating ? BubuTheme.Semantic.visitedNeutral : BubuTheme.Text.tertiary)
                            .onTapGesture { rating = star }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("到访日期").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                DatePicker("", selection: $visitDate, displayedComponents: .date)
                    .datePickerStyle(.compact).labelsHidden()
                    .colorScheme(.dark)
                    .padding(10).background(BubuTheme.Surface.surface1).clipShape(RoundedRectangle(cornerRadius: BubuRadius.sm))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("笔记").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                TextField("写写感受...", text: $note, axis: .vertical)
                    .font(BubuFont.body).foregroundStyle(BubuTheme.Text.ink)
                    .padding(12).background(BubuTheme.Surface.surface1).clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
                    .frame(minHeight: 80)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("照片").font(BubuFont.titleSM).foregroundStyle(BubuTheme.Text.secondary)
                Button {
                    // TODO: 照片选择
                } label: {
                    HStack {
                        Image(systemName: "camera.fill").font(.title3)
                        Text("添加照片").font(BubuFont.titleSM)
                    }
                    .foregroundStyle(BubuTheme.Text.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(RoundedRectangle(cornerRadius: BubuRadius.md).stroke(BubuTheme.Text.tertiary, style: StrokeStyle(lineWidth: 1, dash: [6])))
                }
            }

            Button { saveCheckIn() } label: {
                Text("完成打卡").frame(maxWidth: .infinity)
            }
            .buttonStyle(BubuButtonModifier(variant: .primary))
            .disabled(rating == 0)
        }
    }

    private func saveCheckIn() {
        container.placeRepository.checkIn(
            userPlace: userPlace,
            mood: selectedMood,
            rating: Int16(rating),
            note: note.isEmpty ? nil : note,
            visitDate: visitDate
        )
        onDone()
    }
}

// MARK: - 搜索结果列表

struct SearchResultsSheet: View {
    @Binding var results: [MapPlace]
    var onClose: (MapPlace) -> Void
    @EnvironmentObject var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @State private var expandedPlace: MapPlace? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(results) { place in
                        VStack(spacing: 0) {
                            Button {
                                expandedPlace = expandedPlace?.id == place.id ? nil : place
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(place.name).font(BubuFont.titleMD).foregroundStyle(BubuTheme.Text.ink)
                                            if let addr = place.address {
                                                Text(addr).font(BubuFont.caption).foregroundStyle(BubuTheme.Text.tertiary).lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: expandedPlace?.id == place.id ? "chevron.down" : "chevron.right")
                                            .font(.caption).foregroundStyle(BubuTheme.Text.tertiary)
                                    }
                                    if let cat = place.category {
                                        Text(cat).font(.system(size: 10))
                                            .foregroundStyle(BubuTheme.Primary.green)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(BubuTheme.Primary.green.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .padding(14)
                                .background(BubuTheme.Surface.surface1)
                                .clipShape(RoundedRectangle(cornerRadius: BubuRadius.md))
                            }
                            .buttonStyle(.plain)

                            if expandedPlace?.id == place.id {
                                HStack(spacing: 12) {
                                    Button {
                                        savePlace(place, status: .wantToGo)
                                        expandedPlace = nil
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "bookmark.fill")
                                            Text("想去")
                                        }
                                        .font(BubuFont.titleSM)
                                        .foregroundStyle(BubuTheme.Text.secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(BubuTheme.Surface.surface2)
                                        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.sm))
                                    }
                                    Button {
                                        savePlace(place, status: .visitedGood)
                                        expandedPlace = nil
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "hand.thumbsup.fill")
                                            Text("去过·推荐")
                                        }
                                        .font(BubuFont.titleSM)
                                        .foregroundStyle(BubuTheme.Text.onPrimary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(BubuTheme.Primary.green)
                                        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.sm))
                                    }
                                    Button {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onClose(place) }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "info.circle.fill")
                                            Text("详情")
                                        }
                                        .font(BubuFont.titleSM)
                                        .foregroundStyle(BubuTheme.Text.secondary)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(BubuTheme.Surface.surface2)
                                        .clipShape(RoundedRectangle(cornerRadius: BubuRadius.sm))
                                    }
                                }
                                .padding(.horizontal, 14).padding(.top, 8)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(BubuTheme.Surface.space)
            .navigationTitle("搜索结果 (\(results.count))").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.font(BubuFont.titleSM).foregroundStyle(BubuTheme.Primary.green) } }
        }
    }

    private func savePlace(_ mapPlace: MapPlace, status: PlaceStatus) {
        let folder = container.placeRepository.fetchFolders().first
        _ = container.placeRepository.addPlace(name: mapPlace.name, address: mapPlace.address, latitude: mapPlace.coordinate.latitude, longitude: mapPlace.coordinate.longitude, status: status, folder: folder, sourceType: .manual, sourceURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            var copy = results
            copy.removeAll { $0.id == mapPlace.id }
            results = copy
        }
    }
}

// MARK: - 地址选择 / 搜索

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(BubuTheme.Text.tertiary); TextField("搜索地址...", text: $query).font(BubuFont.body).foregroundStyle(BubuTheme.Text.ink).onSubmit { searchAddress() } }
                    .padding(12).background(BubuTheme.Surface.surface1).clipShape(RoundedRectangle(cornerRadius: BubuRadius.md)).padding(16)
                if isSearching { Spacer(); ProgressView().tint(BubuTheme.Primary.green); Spacer() }
                else if !searchResults.isEmpty {
                    List(searchResults) { p in Button { let a = SavedAddress(name: p.name, lat: p.coordinate.latitude, lon: p.coordinate.longitude, label: nil); if !savedAddresses.contains(where: { $0.name == p.name }) { savedAddresses.append(a) }; onSelect(a) } label: { SearchResultRow(place: p) }.listRowBackground(BubuTheme.Surface.surface1) }.listStyle(.plain)
                } else {
                    List {
                        Section("常用地址") { ForEach(savedAddresses) { a in Button { onSelect(a) } label: { AddressRow(addr: a) }.listRowBackground(BubuTheme.Surface.surface1) } }
                        if !searchHistory.isEmpty {
                            Section("搜索历史") { ForEach(searchHistory, id: \.self) { h in Button { query = h; searchAddress() } label: { HStack { Image(systemName: "clock").font(.caption).foregroundStyle(BubuTheme.Text.tertiary); Text(h).font(BubuFont.body).foregroundStyle(BubuTheme.Text.secondary) } }.listRowBackground(BubuTheme.Surface.surface1) } }
                        }
                    }.scrollContentBackground(.hidden)
                }
            }.background(BubuTheme.Surface.space).navigationTitle("探索位置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func searchAddress() {
        guard !query.isEmpty else { return }
        isSearching = true
        Task { do { searchResults = try await container.mapService.searchPlaces(query: query, region: MapRegion(center: CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434), radius: 100000), filters: nil) } catch { searchResults = [] }; isSearching = false }
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