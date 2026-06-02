import Foundation
import CoreLocation

// MARK: - 高德地图 REST API 封装

final class AMapService: MapServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://restapi.amap.com/v3"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - 地点搜索（关键词）

    func searchPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace] {
        var components = URLComponents(string: "\(baseURL)/place/text")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "keywords", value: query),
            URLQueryItem(name: "city", value: "上海"),
            URLQueryItem(name: "citylimit", value: "true"),
            URLQueryItem(name: "offset", value: "25"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "extensions", value: "all")
        ]
        if let code = filters?.first?.amapPOICode {
            components.queryItems?.append(URLQueryItem(name: "types", value: code))
        }

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AMapSearchResponse.self, from: data)
        return response.pois.map { $0.toDomain() }
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
        let response = try JSONDecoder().decode(AMapSearchResponse.self, from: data)
        return response.pois.map { $0.toDomain() }
    }

    // MARK: - 逆地理编码

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        var components = URLComponents(string: "\(baseURL)/geocode/regeo")!
        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "location", value: "\(coordinate.longitude),\(coordinate.latitude)"),
            URLQueryItem(name: "extensions", value: "base")
        ]

        guard let url = components.url else { throw AMapError.invalidURL }
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AMapRegeoResponse.self, from: data)
        return response.regeocode.formattedAddress
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
        let response = try JSONDecoder().decode(AMapDetailResponse.self, from: data)

        guard let detail = response.pois.first else { throw AMapError.poiNotFound }

        return MapPlaceDetail(
            place: detail.toDomain(),
            rating: detail.ratingValue,
            openingHours: detail.openingHours,
            priceRange: detail.priceRange,
            photos: (detail.photos ?? []).compactMap { URL(string: $0.url) },
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
        let response = try JSONDecoder().decode(AMapRouteResponse.self, from: data)
        guard let path = response.route.paths.first else { throw AMapError.routeNotFound }

        return MapRoute(
            distance: Double(path.distance) ?? 0,
            duration: Double(path.duration) ?? 0,
            polyline: decodePolyline(path.polyline)
        )
    }

    private func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        // 高德 polyline 编码算法
        var result: [CLLocationCoordinate2D] = []
        // 简化实现 — 后续补全
        return result
    }
}

// MARK: - 高德 API 响应模型

private struct AMapSearchResponse: Decodable {
    let pois: [AMapPOI]
    let count: String
}

private struct AMapRegeoResponse: Decodable {
    let regeocode: AMapRegeoCode

    struct AMapRegeoCode: Decodable {
        let formattedAddress: String
        enum CodingKeys: String, CodingKey {
            case formattedAddress = "formatted_address"
        }
    }
}

private struct AMapDetailResponse: Decodable {
    let pois: [AMapPOI]
}

private struct AMapPOI: Decodable {
    let id: String
    let name: String
    let address: String
    let location: String
    let pname: String?
    let cityname: String?
    let adname: String?
    let type: String?
    let typecode: String?
    let tel: String?
    let photos: [AMapPhoto]?
    let bizExt: AMapBizExt?
    let deepInfo: AMapDeepInfo?
    let rating: String?

    struct AMapPhoto: Decodable {
        let url: String
    }

    struct AMapBizExt: Decodable {
        let rating: String?
        let cost: CostValue?
        let opentime2: String?

        enum CostValue: Decodable {
            case string(String)
            case array([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let str = try? container.decode(String.self) { self = .string(str) }
                else if let arr = try? container.decode([String].self) { self = .array(arr) }
                else { self = .string("") }
            }

            var value: String? {
                switch self {
                case .string(let s): return s.isEmpty ? nil : s
                case .array(let a): return a.first
                }
            }
        }
    }

    struct AMapDeepInfo: Decodable {
        let opentime: String?
    }

    var ratingValue: Double? {
        bizExt?.rating.flatMap(Double.init) ?? rating.flatMap(Double.init)
    }

    var openingHours: String? { bizExt?.opentime2 }
    var priceRange: String? { bizExt?.cost?.value }

    func toDomain() -> MapPlace {
        let coords = location.split(separator: ",")
        let lon = Double(coords.first ?? "") ?? 0
        let lat = Double(coords.last ?? "") ?? 0
        let category = mapTypeCode(typecode)

        return MapPlace(
            id: id,
            name: name,
            address: address.isEmpty ? nil : address,
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            poiID: id,
            category: category,
            phone: tel?.isEmpty == false ? tel : nil,
            coverImageURL: photos?.first.flatMap { URL(string: $0.url) }
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

private struct AMapRouteResponse: Decodable {
    let route: AMapRoute

    struct AMapRoute: Decodable {
        let paths: [AMapPath]
    }

    struct AMapPath: Decodable {
        let distance: String
        let duration: String
        let polyline: String
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