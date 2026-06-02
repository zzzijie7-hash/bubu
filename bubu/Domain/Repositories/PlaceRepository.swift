import CoreData

// MARK: - 地点仓库

@MainActor
final class PlaceRepository: ObservableObject {
    private let persistence: PersistenceManager

    init(persistence: PersistenceManager = .shared) {
        self.persistence = persistence
    }

    // MARK: - 收藏夹

    func fetchFolders() -> [CDFolder] {
        let request = CDFolder.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return (try? persistence.viewContext.fetch(request)) ?? []
    }

    func createFolder(name: String, icon: String) -> CDFolder {
        let folder = CDFolder(context: persistence.viewContext)
        folder.id = UUID()
        folder.name = name
        folder.icon = icon
        folder.isDefault = false
        folder.sortOrder = Int16(fetchFolders().count)
        folder.createdAt = Date()
        persistence.save()
        return folder
    }

    func deleteFolder(_ folder: CDFolder) {
        persistence.viewContext.delete(folder)
        persistence.save()
    }

    // MARK: - 用户地点

    func fetchUserPlaces(in folder: CDFolder? = nil) -> [CDUserPlace] {
        let request = CDUserPlace.fetchRequest()
        if let folder {
            request.predicate = NSPredicate(format: "folder == %@", folder)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return (try? persistence.viewContext.fetch(request)) ?? []
    }

    func addPlace(
        name: String,
        address: String?,
        latitude: Double,
        longitude: Double,
        status: PlaceStatus,
        folder: CDFolder?,
        sourceType: PlaceSourceType,
        sourceURL: URL?
    ) -> CDUserPlace {
        // 创建 Place
        let place = CDPlace(context: persistence.viewContext)
        place.id = UUID()
        place.name = name
        place.address = address
        place.latitude = latitude
        place.longitude = longitude
        place.createdAt = Date()
        place.updatedAt = Date()

        // 创建 UserPlace
        let userPlace = CDUserPlace(context: persistence.viewContext)
        userPlace.id = UUID()
        userPlace.place = place
        userPlace.statusValue = status.rawValue
        userPlace.sourceTypeValue = sourceType.rawValue
        userPlace.sourceURL = sourceURL
        userPlace.folder = folder
        userPlace.createdAt = Date()
        userPlace.updatedAt = Date()

        persistence.save()
        return userPlace
    }

    func toggleHidden(_ userPlace: CDUserPlace) {
        userPlace.isHidden.toggle()
        persistence.save()
    }

    func deleteUserPlace(_ userPlace: CDUserPlace) {
        persistence.viewContext.delete(userPlace)
        persistence.save()
    }

    // MARK: - 打卡

    @discardableResult
    func checkIn(userPlace: CDUserPlace, mood: MoodTag?, rating: Int16, note: String?, visitDate: Date) -> CDCheckIn {
        let checkIn = CDCheckIn(context: persistence.viewContext)
        checkIn.id = UUID()
        checkIn.userPlace = userPlace
        checkIn.timestamp = Date()
        checkIn.mood = mood?.rawValue
        checkIn.note = note
        checkIn.ratingAtTime = rating
        checkIn.visitDate = visitDate
        checkIn.weather = nil
        checkIn.companions = nil

        userPlace.mood = mood?.rawValue
        userPlace.rating = rating
        userPlace.reviewText = note
        userPlace.visitDate = visitDate

        persistence.save()
        return checkIn
    }

    // MARK: - 统计数据

    func countVisited() -> Int {
        let request = CDUserPlace.fetchRequest()
        request.predicate = NSPredicate(format: "statusValue != %d", PlaceStatus.wantToGo.rawValue)
        return (try? persistence.viewContext.count(for: request)) ?? 0
    }

    func countWanted() -> Int {
        let request = CDUserPlace.fetchRequest()
        request.predicate = NSPredicate(format: "statusValue == %d", PlaceStatus.wantToGo.rawValue)
        return (try? persistence.viewContext.count(for: request)) ?? 0
    }

    func countFolders() -> Int {
        let request = CDFolder.fetchRequest()
        return (try? persistence.viewContext.count(for: request)) ?? 0
    }

    func countPlaces() -> Int {
        let request = CDUserPlace.fetchRequest()
        return (try? persistence.viewContext.count(for: request)) ?? 0
    }
}