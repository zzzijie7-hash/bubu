import CoreData

@objc(CDPlace)
public class CDPlace: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var address: String?
    @NSManaged public var latitude: Double
    @NSManaged public var longitude: Double
    @NSManaged public var poiID: String?
    @NSManaged public var categoryName: String?
    @NSManaged public var phone: String?
    @NSManaged public var coverImageURL: URL?
    @NSManaged public var sourceName: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var userPlaces: Set<CDUserPlace>?
}

@objc(CDUserPlace)
public class CDUserPlace: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var statusValue: Int16
    @NSManaged public var rating: Int16
    @NSManaged public var mood: String?
    @NSManaged public var reviewText: String?
    @NSManaged public var visitDate: Date?
    @NSManaged public var isHidden: Bool
    @NSManaged public var sourceTypeValue: Int16
    @NSManaged public var sourceURL: URL?
    @NSManaged public var collectionOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var place: CDPlace?
    @NSManaged public var checkIns: Set<CDCheckIn>?
    @NSManaged public var tags: Set<CDTag>?
    @NSManaged public var media: Set<CDMedia>?
    @NSManaged public var folder: CDFolder?
}

@objc(CDCheckIn)
public class CDCheckIn: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var mood: String?
    @NSManaged public var note: String?
    @NSManaged public var ratingAtTime: Int16
    @NSManaged public var weather: String?
    @NSManaged public var companions: String?
    @NSManaged public var visitDate: Date?
    @NSManaged public var userPlace: CDUserPlace?
    @NSManaged public var media: Set<CDMedia>?
}

@objc(CDMedia)
public class CDMedia: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var typeValue: Int16
    @NSManaged public var localFileURL: URL?
    @NSManaged public var cloudAssetToken: String?
    @NSManaged public var thumbnailData: Data?
    @NSManaged public var caption: String?
    @NSManaged public var sortOrder: Int16
    @NSManaged public var createdAt: Date?
    @NSManaged public var userPlace: CDUserPlace?
    @NSManaged public var checkIn: CDCheckIn?
}

@objc(CDCategory)
public class CDCategory: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var icon: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var sortOrder: Int16
    @NSManaged public var isSystem: Bool
}

@objc(CDTag)
public class CDTag: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var colorHex: String?
    @NSManaged public var emoji: String?
    @NSManaged public var userPlaces: Set<CDUserPlace>?
}

@objc(CDFolder)
public class CDFolder: NSManagedObject {
    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var icon: String?
    @NSManaged public var isDefault: Bool
    @NSManaged public var sortOrder: Int16
    @NSManaged public var createdAt: Date?
    @NSManaged public var places: Set<CDUserPlace>?
}

// MARK: - Fetch Requests

extension CDPlace {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDPlace> {
        NSFetchRequest<CDPlace>(entityName: "CDPlace")
    }
}

extension CDUserPlace {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDUserPlace> {
        NSFetchRequest<CDUserPlace>(entityName: "CDUserPlace")
    }
}

extension CDCheckIn {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDCheckIn> {
        NSFetchRequest<CDCheckIn>(entityName: "CDCheckIn")
    }
}

extension CDMedia {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDMedia> {
        NSFetchRequest<CDMedia>(entityName: "CDMedia")
    }
}

extension CDCategory {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDCategory> {
        NSFetchRequest<CDCategory>(entityName: "CDCategory")
    }
}

extension CDTag {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDTag> {
        NSFetchRequest<CDTag>(entityName: "CDTag")
    }
}

extension CDFolder {
    @nonobjc class func fetchRequest() -> NSFetchRequest<CDFolder> {
        NSFetchRequest<CDFolder>(entityName: "CDFolder")
    }
}