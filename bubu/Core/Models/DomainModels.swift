import Foundation
import CoreLocation

// MARK: - 地点状态

enum PlaceStatus: Int16, CaseIterable, Codable {
    case wantToGo = 0
    case visitedGood = 1
    case visitedBad = 2
    case visitedNeutral = 3

    var displayName: String {
        switch self {
        case .wantToGo: return "想去"
        case .visitedGood: return "去过·推荐"
        case .visitedBad: return "去过·踩雷"
        case .visitedNeutral: return "去过·一般"
        }
    }

    var iconName: String {
        switch self {
        case .wantToGo: return "bookmark"
        case .visitedGood: return "hand.thumbsup.fill"
        case .visitedBad: return "hand.thumbsdown.fill"
        case .visitedNeutral: return "checkmark.circle"
        }
    }
}

// MARK: - 来源类型

enum PlaceSourceType: Int16, CaseIterable, Codable {
    case manual = 0
    case redbook = 1
    case friendRecommend = 2
    case amapFavorite = 3
    case curated = 4
    case other = 5

    var displayName: String {
        switch self {
        case .manual: return "手动添加"
        case .redbook: return "小红书"
        case .friendRecommend: return "朋友推荐"
        case .amapFavorite: return "高德收藏"
        case .curated: return "步步精选"
        case .other: return "其他"
        }
    }
}

// MARK: - 心情标签

enum MoodTag: String, CaseIterable, Codable {
    case happy = "开心"
    case excited = "惊喜"
    case calm = "惬意"
    case disappointed = "失望"
    case nostalgic = "怀念"
    case romantic = "浪漫"
    case energetic = "充满活力"
    case peaceful = "宁静"

    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .excited: return "🤩"
        case .calm: return "😌"
        case .disappointed: return "😞"
        case .nostalgic: return "🥲"
        case .romantic: return "💕"
        case .energetic: return "⚡"
        case .peaceful: return "🧘"
        }
    }
}

// MARK: - 媒体类型

enum MediaType: Int16, CaseIterable, Codable {
    case photo = 0
    case voiceNote = 1
    case video = 2
}

// MARK: - 领域模型 (纯 Swift Struct，不依赖 Core Data)

struct MapPlace: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D
    let poiID: String?
    let category: String?
    let phone: String?
    let coverImageURL: URL?
    let rating: Double?
    let distance: Double?  // 米

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MapPlace, rhs: MapPlace) -> Bool {
        lhs.id == rhs.id
    }
}

struct ImportablePlace: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String?
    let coordinate: CLLocationCoordinate2D?
    let category: String?
    let imageURL: URL?
    let sourceURL: URL?
    let sourceType: PlaceSourceType
    let note: String?

    static func == (lhs: ImportablePlace, rhs: ImportablePlace) -> Bool {
        lhs.name == rhs.name &&
        lhs.address == rhs.address &&
        lhs.sourceURL == rhs.sourceURL &&
        lhs.sourceType == rhs.sourceType
    }
}

struct ImportCollectionPayload: Equatable {
    let title: String
    let sourceType: PlaceSourceType
    let sourceURL: URL?
    let items: [ImportablePlace]
    let summary: String?
}

struct MapAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String?
    let status: PlaceStatus
    let categoryColor: String?
}

struct MapRegion {
    let center: CLLocationCoordinate2D
    let radius: Double
}

struct MapPlaceDetail {
    let place: MapPlace
    let rating: Double?
    let openingHours: String?
    let priceRange: String?
    let photos: [URL]
    let description: String?
}

struct MapRoute {
    let distance: Double
    let duration: TimeInterval
    let polyline: [CLLocationCoordinate2D]
}

struct MapStyleConfig {
    let isDarkMode: Bool
    let accentColor: String
    let showTraffic: Bool
    let showBuildings: Bool
}

// MARK: - 导入预览模型

enum ImportPreviewKind: Equatable {
    case singlePlace
    case collection
}

struct ImportCollectionContext: Equatable {
    let provider: PlaceSourceType
    let collectionID: String
    let pathID: Int?
    let isCreatorShare: Bool
}

struct ImportPreview: Identifiable, Equatable {
    let id = UUID()
    let kind: ImportPreviewKind
    let sourceType: PlaceSourceType
    let sourceURL: URL?
    let rawText: String
    let title: String
    let subtitle: String?
    let suggestedQuery: String
    let searchQueries: [String]
    let candidateAddress: String?
    let coordinate: CLLocationCoordinate2D?
    let collectionContext: ImportCollectionContext?

    static func == (lhs: ImportPreview, rhs: ImportPreview) -> Bool {
        lhs.id == rhs.id
    }
}

extension ImportSourceType {
    var placeSourceType: PlaceSourceType {
        switch self {
        case .redbook:
            return .redbook
        case .amapFavorite:
            return .amapFavorite
        case .url, .screenshot:
            return .other
        }
    }
}
