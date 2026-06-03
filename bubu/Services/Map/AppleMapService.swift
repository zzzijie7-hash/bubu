import Foundation
import CoreLocation
import MapKit

// 兜底：Apple 原生搜索（高德 key 不可用时）
final class AppleMapService: MapServiceProtocol {
    func searchPlaces(query: String, region: MapRegion, filters: [PlaceCategoryType]?) async throws -> [MapPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: region.center,
            latitudinalMeters: region.radius * 2,
            longitudinalMeters: region.radius * 2
        )
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            MapPlace(
                id: UUID().uuidString,
                name: item.name ?? "未知地点",
                address: item.placemark.formattedAddress,
                coordinate: item.placemark.coordinate,
                poiID: nil,
                category: item.pointOfInterestCategory.flatMap { catType($0) },
                phone: item.phoneNumber,
                coverImageURL: nil,
                rating: nil,
                distance: nil
            )
        }
    }

    func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> String {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(loc)
        return placemarks.first?.formattedAddress ?? "\(coordinate.latitude), \(coordinate.longitude)"
    }

    func fetchPlaceDetail(poiID: String) async throws -> MapPlaceDetail {
        throw AppleMapError.notSupported
    }

    func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MapRoute {
        MapRoute(distance: 0, duration: 0, polyline: [])
    }

    func searchNearby(coordinate: CLLocationCoordinate2D, radius: Double, category: PlaceCategoryType?) async throws -> [MapPlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = category?.rawValue
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.map { item in
            MapPlace(
                id: UUID().uuidString,
                name: item.name ?? "未知地点",
                address: item.placemark.formattedAddress,
                coordinate: item.placemark.coordinate,
                poiID: nil,
                category: item.pointOfInterestCategory.flatMap { catType($0) },
                phone: item.phoneNumber,
                coverImageURL: nil,
                rating: nil,
                distance: nil
            )
        }
    }

    private func catType(_ cat: MKPointOfInterestCategory) -> String? {
        let raw = cat.rawValue
        if raw.contains("Restaurant") || raw.contains("Food") { return "餐饮" }
        if raw.contains("Cafe") || raw.contains("Bakery") || raw.contains("Brewery") { return "咖啡" }
        if raw.contains("Nightlife") { return "酒吧" }
        if raw.contains("Park") { return "公园" }
        if raw.contains("Museum") { return "博物馆" }
        if raw.contains("Hotel") { return "住宿" }
        if raw.contains("Store") { return "购物" }
        return nil
    }
}

enum AppleMapError: Error { case notSupported }

extension CLPlacemark {
    var formattedAddress: String {
        [locality, subLocality, thoroughfare].compactMap(\.self).joined(separator: " ")
    }
}