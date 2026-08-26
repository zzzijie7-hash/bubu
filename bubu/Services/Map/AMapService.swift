import Foundation
import CoreLocation

// MARK: - 高德地图 REST API 封装

final class AMapService: MapServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://restapi.amap.com/v3"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - 地点搜索

    func searchPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }

        async let nearbyTask = searchNearbyPlaces(query: trimmedQuery, region: region, filters: filters)
        async let globalTask = searchGlobalPlaces(query: trimmedQuery, region: region, filters: filters)

        let nearbyPlaces = (try? await nearbyTask) ?? []
        let globalPlaces = (try? await globalTask) ?? []
        let merged = mergePlaces(nearby: nearbyPlaces, global: globalPlaces, center: region.center)
        return filterPlacesByRelevance(merged, query: trimmedQuery)
    }

    private func searchNearbyPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace] {
        let location = "\(region.center.longitude),\(region.center.latitude)"
        var components = URLComponents(string: "\(baseURL)/place/around")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "location", value: location),
            URLQueryItem(name: "radius", value: "\(Int(region.radius))"),
            URLQueryItem(name: "offset", value: "25"),
            URLQueryItem(name: "sortrule", value: "distance"),
            URLQueryItem(name: "extensions", value: "all")
        ]
        if let code = filters?.first?.amapPOICode {
            components.queryItems?.append(URLQueryItem(name: "types", value: code))
        }

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pois = (obj["pois"] as? [[String: Any]]) ?? []
        return pois.compactMap(parsePOI)
    }

    private func searchGlobalPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace] {
        var components = URLComponents(string: "\(baseURL)/place/text")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "offset", value: "20"),
            URLQueryItem(name: "extensions", value: "all"),
            URLQueryItem(name: "citylimit", value: "false"),
            URLQueryItem(name: "location", value: "\(region.center.longitude),\(region.center.latitude)")
        ]
        if let code = filters?.first?.amapPOICode {
            components.queryItems?.append(URLQueryItem(name: "types", value: code))
        }

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pois = (obj["pois"] as? [[String: Any]]) ?? []
        return pois.compactMap(parsePOI)
    }

    private func mergePlaces(nearby: [MapPlace], global: [MapPlace], center: CLLocationCoordinate2D) -> [MapPlace] {
        var merged: [MapPlace] = []
        var seen = Set<String>()

        func normalizedKey(for place: MapPlace) -> String {
            if let poiID = place.poiID, !poiID.isEmpty {
                return poiID
            }
            let address = place.address ?? ""
            return "\(place.name.lowercased())|\(address.lowercased())"
        }

        for place in nearby + global {
            let key = normalizedKey(for: place)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(enrichedDistance(for: place, center: center))
        }

        return merged.sorted { lhs, rhs in
            let leftDistance = lhs.distance ?? .greatestFiniteMagnitude
            let rightDistance = rhs.distance ?? .greatestFiniteMagnitude
            if leftDistance != rightDistance {
                return leftDistance < rightDistance
            }

            let leftRating = lhs.rating ?? 0
            let rightRating = rhs.rating ?? 0
            if leftRating != rightRating {
                return leftRating > rightRating
            }

            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    private func filterPlacesByRelevance(_ places: [MapPlace], query: String) -> [MapPlace] {
        let normalizedQuery = normalizeSearchText(query)
        guard !normalizedQuery.isEmpty else { return places }

        let queryTokens = normalizedQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }

        let scored: [(place: MapPlace, score: Int)] = places.compactMap { place in
            let haystack = normalizeSearchText([
                place.name,
                place.address ?? "",
                place.category ?? ""
            ].joined(separator: " "))

            guard !haystack.isEmpty else { return nil }

            var score = 0

            if haystack.contains(normalizedQuery) {
                score += 100
            }

            if normalizeSearchText(place.name).contains(normalizedQuery) {
                score += 80
            }

            for token in queryTokens {
                if haystack.contains(token) {
                    score += 20
                }
                if normalizeSearchText(place.name).contains(token) {
                    score += 16
                }
                if let address = place.address, normalizeSearchText(address).contains(token) {
                    score += 8
                }
            }

            return score > 0 ? (place, score) : nil
        }

        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }

                let leftDistance = lhs.place.distance ?? .greatestFiniteMagnitude
                let rightDistance = rhs.place.distance ?? .greatestFiniteMagnitude
                if leftDistance != rightDistance { return leftDistance < rightDistance }

                return lhs.place.name.localizedCompare(rhs.place.name) == .orderedAscending
            }
            .map(\.place)
    }

    private func normalizeSearchText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "·", with: " ")
            .replacingOccurrences(of: "（", with: " ")
            .replacingOccurrences(of: "）", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
    }

    private func enrichedDistance(for place: MapPlace, center: CLLocationCoordinate2D) -> MapPlace {
        if place.distance != nil {
            return place
        }

        let from = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let to = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        let computedDistance = from.distance(from: to)

        return MapPlace(
            id: place.id,
            name: place.name,
            address: place.address,
            coordinate: place.coordinate,
            poiID: place.poiID,
            category: place.category,
            phone: place.phone,
            coverImageURL: place.coverImageURL,
            rating: place.rating,
            distance: computedDistance
        )
    }

    // MARK: - 周边搜索

    func searchNearby(coordinate: CLLocationCoordinate2D, radius: Double, category: PlaceCategoryType?) async throws -> [MapPlace] {
        var components = URLComponents(string: "\(baseURL)/place/around")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location", value: "\(coordinate.longitude),\(coordinate.latitude)"),
            URLQueryItem(name: "radius", value: "\(Int(radius))"),
            URLQueryItem(name: "offset", value: "25"),
            URLQueryItem(name: "extensions", value: "all")
        ]
        if let code = category?.amapPOICode {
            components.queryItems?.append(URLQueryItem(name: "types", value: code))
        }

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let pois = (obj["pois"] as? [[String: Any]]) ?? []
        return pois.compactMap(parsePOI)
    }

    // MARK: - 逆地理编码

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        var components = URLComponents(string: "\(baseURL)/geocode/regeo")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location", value: "\(coordinate.longitude),\(coordinate.latitude)"),
            URLQueryItem(name: "extensions", value: "all"),
            URLQueryItem(name: "radius", value: "300"),
            URLQueryItem(name: "poitype", value: "餐饮服务|购物服务|风景名胜|科教文化服务|交通设施服务|公司企业|金融保险服务|生活服务|体育休闲服务|医疗保健服务|住宿服务|公共设施")
        ]

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let regeocode = obj["regeocode"] as? [String: Any] ?? [:]

        // 优先取最近的商业/地标类 POI（过滤掉住宅小区）
        if let pois = regeocode["pois"] as? [[String: Any]] {
            // 商业类 POI type 前缀：05餐饮 06购物 07旅游 08娱乐 10住宿 11风景 14科教 15交通 17公司 16金融
            let goodPrefixes = ["05", "06", "07", "08", "10", "11", "14", "15", "16", "17"]
            for poi in pois {
                guard let name = poi["name"] as? String, !name.isEmpty else { continue }
                let typecode = poi["typecode"] as? String ?? ""
                let prefix = String(typecode.prefix(2))
                if goodPrefixes.contains(prefix) { return name }
            }
        }
        // 其次取 AOI（区域面，如商圈/园区）
        if let aois = regeocode["aois"] as? [[String: Any]], let name = aois.first?["name"] as? String, !name.isEmpty {
            return name
        }
        // 兜底：街道地址，裁剪城市前缀
        let addr = regeocode["formatted_address"] as? String ?? "未知位置"
        return addr
            .replacingOccurrences(of: "上海市", with: "")
            .replacingOccurrences(of: "北京市", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - POI 详情

    func fetchPlaceDetail(poiID: String) async throws -> MapPlaceDetail {
        var components = URLComponents(string: "\(baseURL)/place/detail")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "id", value: poiID)
        ]

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let pois = obj["pois"] as? [[String: Any]], let poi = pois.first,
              let place = parsePOI(poi) else { throw AMapError.poiNotFound }

        var rating: Double?
        if let bizExt = poi["biz_ext"] as? [String: Any], let r = bizExt["rating"] as? String {
            rating = Double(r)
        } else if let r = poi["rating"] as? String {
            rating = Double(r)
        }

        let openingHours = (poi["biz_ext"] as? [String: Any])?["opentime2"] as? String
        let cost = (poi["biz_ext"] as? [String: Any])?["cost"] as? String
        let photoDicts = poi["photos"] as? [[String: Any]] ?? []
        let photoURLs = photoDicts.compactMap { ($0["url"] as? String).flatMap(URL.init) }

        return MapPlaceDetail(
            place: place,
            rating: rating,
            openingHours: openingHours,
            priceRange: cost,
            photos: photoURLs,
            description: nil
        )
    }

    // MARK: - 路线规划

    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MapRoute {
        var components = URLComponents(string: "\(baseURL)/direction/walking")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "origin", value: "\(from.longitude),\(from.latitude)"),
            URLQueryItem(name: "destination", value: "\(to.longitude),\(to.latitude)")
        ]

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let route = obj["route"] as? [String: Any],
              let paths = route["paths"] as? [[String: Any]],
              let path = paths.first else { throw AMapError.routeNotFound }

        return MapRoute(
            distance: Double(path["distance"] as? String ?? "0") ?? 0,
            duration: Double(path["duration"] as? String ?? "0") ?? 0,
            polyline: []
        )
    }

    // MARK: - 单条 POI 解析（安全：坏记录跳过）

    private func parsePOI(_ poi: [String: Any]) -> MapPlace? {
        guard let id = poi["id"] as? String,
              let name = poi["name"] as? String,
              let location = poi["location"] as? String else { return nil }

        let coords = location.split(separator: ",")
        let lon = Double(coords.first ?? "") ?? 0
        let lat = Double(coords.last ?? "") ?? 0

        let address = poi["address"] as? String
        let tel = poi["tel"] as? String
        let typecode = poi["typecode"] as? String
        let category = mapTypeCode(typecode)

        // distance: around API 返回字符串 "1141"，text API 返回 []
        let distString = poi["distance"] as? String
        let distance = distString.flatMap(Double.init)

        // rating: biz_ext.rating 作为字符串
        let bizExt = poi["biz_ext"] as? [String: Any]
        let ratingStr = bizExt?["rating"] as? String ?? poi["rating"] as? String
        let rating = ratingStr.flatMap(Double.init)

        // 封面图
        let photos = poi["photos"] as? [[String: Any]]
        let coverImageURL = photos?.first?["url"] as? String

        return MapPlace(
            id: id,
            name: name,
            address: (address?.isEmpty == false) ? address : nil,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            poiID: id,
            category: category,
            phone: (tel?.isEmpty == false) ? tel : nil,
            coverImageURL: coverImageURL.flatMap(URL.init),
            rating: rating,
            distance: distance
        )
    }

    private func mapTypeCode(_ code: String?) -> String? {
        guard let code = code else { return nil }
        switch code.prefix(2) {
        case "05": return "餐饮"
        case "07": return "旅游景点"
        case "11": return "风景名胜"
        case "06": return "购物"
        case "10": return "住宿"
        case "14": return "科教文化"
        case "08": return "娱乐"
        case "19": return "地标"
        default: return nil
        }
    }
}

enum AMapError: Error {
    case invalidURL
    case poiNotFound
    case routeNotFound
    case networkError(Error)
}

// MARK: - Category → 高德 POI type code

extension PlaceCategoryType {
    var amapPOICode: String? {
        switch self {
        case .restaurant: return "050000"
        case .cafe: return "050300"
        case .bar: return "050200"
        case .dessert: return "050300"
        case .scenic: return "110000"
        case .park: return "110101"
        case .museum: return "140000"
        case .shopping: return "060000"
        case .entertainment: return "080000"
        case .sports: return "080200"
        case .hotel: return "100000"
        case .landmark: return "190000"
        case .other: return nil
        }
    }
}
