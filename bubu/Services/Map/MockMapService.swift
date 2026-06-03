import Foundation
import CoreLocation

// MARK: - Mock 地图服务 (Simulator / Preview)

final class MockMapService: MapServiceProtocol {
    func searchPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace] {
        // 模拟网络延迟
        try await Task.sleep(nanoseconds: 500_000_000)

        return [
            MapPlace(
                id: "mock_1",
                name: "\(query) - 搜索结果1",
                address: "模拟地址 123号",
                coordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
                poiID: "B000A1",
                category: "餐饮",
                phone: "010-12345678",
                coverImageURL: nil,
                rating: 4.3,
                distance: 350
            ),
            MapPlace(
                id: "mock_2",
                name: "\(query) - 搜索结果2",
                address: "模拟地址 456号",
                coordinate: CLLocationCoordinate2D(latitude: 39.9142, longitude: 116.4174),
                poiID: "B000A2",
                category: "咖啡",
                phone: nil,
                coverImageURL: nil,
                rating: 4.7,
                distance: 1200
            )
        ]
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        try await Task.sleep(nanoseconds: 200_000_000)
        return "模拟地址·北京市朝阳区"
    }

    func fetchPlaceDetail(poiID: String) async throws -> MapPlaceDetail {
        try await Task.sleep(nanoseconds: 300_000_000)
        return MapPlaceDetail(
            place: MapPlace(
                id: poiID,
                name: "模拟地点",
                address: "模拟地址",
                coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
                poiID: poiID,
                category: "餐饮",
                phone: nil,
                coverImageURL: nil,
                rating: 4.5,
                distance: nil
            ),
            rating: 4.5,
            openingHours: "10:00-22:00",
            priceRange: "¥100-200",
            photos: [],
            description: "这是一个模拟的地点描述"
        )
    }

    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MapRoute {
        MapRoute(
            distance: 3500,
            duration: 1800,
            polyline: [from, to]
        )
    }

    func searchNearby(coordinate: CLLocationCoordinate2D, radius: Double, category: PlaceCategoryType?) async throws -> [MapPlace] {
        try await Task.sleep(nanoseconds: 400_000_000)
        return []
    }
}

// MARK: - Mock API Client (v1.0 空实现)

final class MockAPIClient: APIClientProtocol {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        throw APIError.unavailable
    }

    func upload(_ data: Data, to endpoint: APIEndpoint) async throws -> UploadResponse {
        throw APIError.unavailable
    }
}