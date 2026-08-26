import CoreData
import CoreLocation
import UIKit

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

    func hasUserPlace(name: String, address: String?) -> Bool {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return fetchUserPlaces().contains { userPlace in
            let placeName = userPlace.place?.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            let placeAddress = userPlace.place?.address?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return placeName == normalizedName && placeAddress == normalizedAddress
        }
    }

    func importPlaces(
        _ places: [ImportablePlace],
        status: PlaceStatus = .wantToGo,
        folder: CDFolder?
    ) -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        var seenInBatch = Set<String>()

        for place in places {
            let dedupeKey = "\(place.name.lowercased())|\((place.address ?? "").lowercased())"
            guard !seenInBatch.contains(dedupeKey) else {
                skipped += 1
                continue
            }
            seenInBatch.insert(dedupeKey)

            if hasUserPlace(name: place.name, address: place.address) {
                skipped += 1
                continue
            }

            let coordinate = place.coordinate ?? CLLocationCoordinate2D(latitude: 31.215070, longitude: 121.474434)
            _ = addPlace(
                name: place.name,
                address: place.address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                status: status,
                folder: folder,
                sourceType: place.sourceType,
                sourceURL: place.sourceURL
            )
            imported += 1
        }

        return (imported, skipped)
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

    func attachPhotos(_ images: [UIImage], to checkIn: CDCheckIn, userPlace: CDUserPlace) {
        guard !images.isEmpty else { return }

        let directory = persistenceDirectory().appendingPathComponent("CheckInMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, image) in images.enumerated() {
            guard let jpegData = image.jpegData(compressionQuality: 0.82) else { continue }
            let media = CDMedia(context: persistence.viewContext)
            media.id = UUID()
            media.typeValue = MediaType.photo.rawValue
            media.createdAt = Date()
            media.sortOrder = Int16(index)
            media.userPlace = userPlace
            media.checkIn = checkIn

            let fileURL = directory.appendingPathComponent("\(media.id?.uuidString ?? UUID().uuidString).jpg")
            do {
                try jpegData.write(to: fileURL, options: .atomic)
                media.localFileURL = fileURL
                media.thumbnailData = image.preparingThumbnail(of: CGSize(width: 220, height: 220))?.jpegData(compressionQuality: 0.7)
            } catch {
                persistence.viewContext.delete(media)
            }
        }

        persistence.save()
    }

    func attachPhotos(_ images: [UIImage], to userPlace: CDUserPlace) {
        guard !images.isEmpty else { return }

        let directory = persistenceDirectory().appendingPathComponent("CheckInMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (index, image) in images.enumerated() {
            guard let jpegData = image.jpegData(compressionQuality: 0.82) else { continue }
            let media = CDMedia(context: persistence.viewContext)
            media.id = UUID()
            media.typeValue = MediaType.photo.rawValue
            media.createdAt = Date()
            media.sortOrder = Int16(index)
            media.userPlace = userPlace

            let fileURL = directory.appendingPathComponent("\(media.id?.uuidString ?? UUID().uuidString).jpg")
            do {
                try jpegData.write(to: fileURL, options: .atomic)
                media.localFileURL = fileURL
                media.thumbnailData = image.preparingThumbnail(of: CGSize(width: 220, height: 220))?.jpegData(compressionQuality: 0.7)
            } catch {
                persistence.viewContext.delete(media)
            }
        }

        persistence.save()
    }

    func attachVoiceMemo(_ fileURL: URL, to checkIn: CDCheckIn?, userPlace: CDUserPlace) {
        let directory = persistenceDirectory().appendingPathComponent("CheckInMedia", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let media = CDMedia(context: persistence.viewContext)
        media.id = UUID()
        media.typeValue = MediaType.voiceNote.rawValue
        media.createdAt = Date()
        media.sortOrder = 0
        media.userPlace = userPlace
        media.checkIn = checkIn

        let destinationURL = directory.appendingPathComponent("\(media.id?.uuidString ?? UUID().uuidString).m4a")
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: fileURL, to: destinationURL)
            media.localFileURL = destinationURL
        } catch {
            persistence.viewContext.delete(media)
        }

        persistence.save()
    }

    func updateMark(
        userPlace: CDUserPlace,
        status: PlaceStatus,
        mood: MoodTag?,
        note: String?,
        visitDate: Date,
        images: [UIImage],
        voiceMemoURL: URL?
    ) {
        userPlace.statusValue = status.rawValue
        userPlace.updatedAt = Date()

        if status == .wantToGo {
            userPlace.reviewText = note
            userPlace.visitDate = nil
            userPlace.mood = nil
            userPlace.rating = 0
            attachPhotos(images, to: userPlace)
            if let voiceMemoURL {
                attachVoiceMemo(voiceMemoURL, to: nil, userPlace: userPlace)
            }
            persistence.save()
            return
        }

        let checkIn = checkIn(
            userPlace: userPlace,
            mood: mood,
            rating: 0,
            note: note,
            visitDate: visitDate
        )
        attachPhotos(images, to: checkIn, userPlace: userPlace)
        if let voiceMemoURL {
            attachVoiceMemo(voiceMemoURL, to: checkIn, userPlace: userPlace)
        }
    }

    func updateCheckIn(
        _ checkIn: CDCheckIn,
        mood: MoodTag?,
        note: String?,
        visitDate: Date,
        images: [UIImage],
        voiceMemoURL: URL?
    ) {
        checkIn.mood = mood?.rawValue
        checkIn.note = note
        checkIn.visitDate = visitDate

        if let userPlace = checkIn.userPlace {
            userPlace.mood = mood?.rawValue
            userPlace.reviewText = note
            userPlace.visitDate = visitDate
            userPlace.updatedAt = Date()
        }

        deleteMedia(for: checkIn)
        if let userPlace = checkIn.userPlace {
            attachPhotos(images, to: checkIn, userPlace: userPlace)
        }
        if let voiceMemoURL, let userPlace = checkIn.userPlace {
            attachVoiceMemo(voiceMemoURL, to: checkIn, userPlace: userPlace)
        }
        persistence.save()
    }

    func deleteCheckIn(_ checkIn: CDCheckIn) {
        let userPlace = checkIn.userPlace
        deleteMedia(for: checkIn)
        persistence.viewContext.delete(checkIn)

        if let userPlace,
           let latest = (userPlace.checkIns?.sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) } ?? []).first {
            userPlace.mood = latest.mood
            userPlace.reviewText = latest.note
            userPlace.visitDate = latest.visitDate
        } else if let userPlace {
            userPlace.mood = nil
            userPlace.reviewText = nil
            userPlace.visitDate = nil
            userPlace.statusValue = PlaceStatus.wantToGo.rawValue
        }

        persistence.save()
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

    private func persistenceDirectory() -> URL {
        persistence.storageRootURL
    }

    private func deleteMedia(for checkIn: CDCheckIn) {
        let mediaItems = checkIn.media ?? []
        for media in mediaItems {
            if let url = media.localFileURL {
                try? FileManager.default.removeItem(at: url)
            }
            persistence.viewContext.delete(media)
        }
    }
}
