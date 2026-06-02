import Foundation
import SwiftUI
import CoreLocation

// MARK: - 地点类别类型

enum PlaceCategoryType: String, CaseIterable, Codable {
    case restaurant = "餐饮"
    case cafe = "咖啡/茶馆"
    case bar = "酒吧"
    case dessert = "甜品"
    case scenic = "景点"
    case park = "公园"
    case museum = "博物馆/展览"
    case shopping = "购物"
    case entertainment = "娱乐"
    case sports = "运动"
    case hotel = "住宿"
    case landmark = "地标"
    case other = "其他"

    var iconName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .bar: return "wineglass.fill"
        case .dessert: return "birthday.cake"
        case .scenic: return "mountain.2.fill"
        case .park: return "leaf.fill"
        case .museum: return "building.columns.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "sparkles"
        case .sports: return "figure.run"
        case .hotel: return "bed.double.fill"
        case .landmark: return "mappin.and.ellipse"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .restaurant: return .orange
        case .cafe: return .brown
        case .bar: return .purple
        case .dessert: return .pink
        case .scenic: return .green
        case .park: return .mint
        case .museum: return .indigo
        case .shopping: return .blue
        case .entertainment: return .yellow
        case .sports: return .cyan
        case .hotel: return .teal
        case .landmark: return .red
        case .other: return .gray
        }
    }
}

// MARK: - 筛选配置

struct PlaceFilter: Equatable {
    var statuses: Set<PlaceStatus> = []
    var categories: Set<PlaceCategoryType> = []
    var hideDisliked: Bool = false
    var onlyWithNotes: Bool = false
    var tagIDs: Set<UUID> = []

    var isEmpty: Bool {
        statuses.isEmpty && categories.isEmpty && !hideDisliked && !onlyWithNotes && tagIDs.isEmpty
    }
}

// MARK: - 预置推荐地点（Tutorial 用）

struct CuratedPlace: Identifiable, Decodable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let category: PlaceCategoryType
    let description: String
    let imageURL: URL?
    let tag: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct CuratedCity: Identifiable, Decodable {
    let id: UUID
    let name: String
    let province: String
    let latitude: Double
    let longitude: Double
    let places: [CuratedPlace]
}