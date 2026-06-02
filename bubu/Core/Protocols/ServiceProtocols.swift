import Foundation
import CoreLocation
import SwiftUI

// MARK: - 地图服务协议

protocol MapServiceProtocol {
    func searchPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace]
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String
    func fetchPlaceDetail(poiID: String) async throws -> MapPlaceDetail
    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MapRoute
    func searchNearby(coordinate: CLLocationCoordinate2D, radius: Double, category: PlaceCategoryType?) async throws -> [MapPlace]
}

// MARK: - 地图 View 提供者协议

enum MapViewType {
    case explore
    case picker
}

protocol MapViewProvider {
    associatedtype ContentView: View
    func makeMapView(
        annotations: [MapAnnotation],
        region: Binding<MapRegion?>,
        style: MapStyleConfig,
        onAnnotationTap: @escaping (MapAnnotation) -> Void,
        onMapLongPress: @escaping (CLLocationCoordinate2D) -> Void
    ) -> ContentView

    func makePlaceSearchView(onSelect: @escaping (MapPlace) -> Void) -> AnyView
}

// MARK: - 导入服务协议

enum ImportSourceType: String, CaseIterable {
    case redbook = "小红书"
    case amapFavorite = "高德收藏"
    case url = "链接"
    case screenshot = "截屏"
}

protocol ImportServiceProtocol {
    var sourceType: ImportSourceType { get }
    var supportedHosts: [String] { get }
    func canHandle(url: URL) -> Bool
    func parse(url: URL) async throws -> [ImportablePlace]
    func parseSharedText(_ text: String) async throws -> [ImportablePlace]
}

// MARK: - API 客户端协议

protocol APIClientProtocol {
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T
    func upload(_ data: Data, to endpoint: APIEndpoint) async throws -> UploadResponse
}

struct APIEndpoint {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]?
    let body: Data?

    init(path: String, method: HTTPMethod = .get, queryItems: [URLQueryItem]? = nil, body: Data? = nil) {
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.body = body
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

struct UploadResponse {
    let url: URL
    let key: String
}

enum APIError: Error {
    case unavailable
    case unauthorized
    case serverError(statusCode: Int)
    case decodingError(Error)
    case networkError(Error)
}