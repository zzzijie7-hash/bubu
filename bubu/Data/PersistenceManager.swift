import CoreData

final class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()

    private(set) var container: NSPersistentContainer
    private(set) var cloudSyncEnabled: Bool

    var viewContext: NSManagedObjectContext { container.viewContext }
    var storageRootURL: URL { Self.storageRootURL() }

    init(inMemory: Bool = false) {
        cloudSyncEnabled = Self.shouldEnableCloudSync(inMemory: inMemory)
        try? Self.prepareStorageDirectory(inMemory: inMemory)
        try? Self.migrateLegacyStoreIfNeeded(inMemory: inMemory)

        if cloudSyncEnabled {
            let cloudContainer = NSPersistentCloudKitContainer(name: "Bubu")
            Self.configureCloudContainer(cloudContainer, inMemory: inMemory)
            container = cloudContainer
        } else {
            let localContainer = NSPersistentContainer(name: "Bubu")
            Self.configureLocalContainer(localContainer, inMemory: inMemory)
            container = localContainer
        }

        do {
            try Self.loadStores(for: container)
        } catch {
            if cloudSyncEnabled {
                cloudSyncEnabled = false
                let localContainer = NSPersistentContainer(name: "Bubu")
                Self.configureLocalContainer(localContainer, inMemory: inMemory)
                container = localContainer
                do {
                    try Self.loadStores(for: localContainer)
                } catch {
                    fatalError("Core Data 加载失败: \(error)")
                }
            } else {
                fatalError("Core Data 加载失败: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        seedDataIfNeeded()
    }

    func save() {
        guard viewContext.hasChanges else { return }
        try? viewContext.save()
    }

    private func seedDataIfNeeded() {
        let request = CDCategory.fetchRequest()
        request.fetchLimit = 1
        let count = (try? viewContext.count(for: request)) ?? 0
        guard count == 0 else { return }

        for (i, type) in PlaceCategoryType.allCases.enumerated() {
            let cat = CDCategory(context: viewContext)
            cat.id = UUID()
            cat.name = type.rawValue
            cat.icon = type.iconName
            cat.sortOrder = Int16(i)
            cat.isSystem = true
            cat.colorHex = nil
        }

        let folder = CDFolder(context: viewContext)
        folder.id = UUID()
        folder.name = "我的收藏"
        folder.icon = "folder.fill"
        folder.isDefault = true
        folder.sortOrder = 0
        folder.createdAt = Date()

        save()
    }

    private static func configureCloudContainer(_ container: NSPersistentCloudKitContainer, inMemory: Bool) {
        guard let storeDescription = container.persistentStoreDescriptions.first else { return }

        if inMemory {
            storeDescription.url = URL(fileURLWithPath: "/dev/null")
        } else {
            configurePersistentStoreDescription(storeDescription)
            storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.bubu.app"
            )
        }
    }

    private static func configureLocalContainer(_ container: NSPersistentContainer, inMemory: Bool) {
        guard let storeDescription = container.persistentStoreDescriptions.first else { return }

        if inMemory {
            storeDescription.url = URL(fileURLWithPath: "/dev/null")
        } else {
            configurePersistentStoreDescription(storeDescription)
        }
    }

    private static func shouldEnableCloudSync(inMemory: Bool) -> Bool {
        guard !inMemory else { return false }

        #if DEBUG
        return ProcessInfo.processInfo.environment["BUBU_ENABLE_CLOUDKIT"] != "0"
        #else
        return true
        #endif
    }

    private static func configurePersistentStoreDescription(_ storeDescription: NSPersistentStoreDescription) {
        storeDescription.url = storeURL()
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    private static func loadStores(for container: NSPersistentContainer) throws {
        guard container.persistentStoreDescriptions.first != nil else {
            throw NSError(domain: "PersistenceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到持久化存储描述"])
        }

        var loadError: NSError?
        container.loadPersistentStores { _, error in
            loadError = error as NSError?
        }

        if let loadError {
            throw loadError
        }
    }

    private static func prepareStorageDirectory(inMemory: Bool) throws {
        guard !inMemory else { return }
        try FileManager.default.createDirectory(at: storageRootURL(), withIntermediateDirectories: true)
    }

    private static func storageRootURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("BubuStorage", isDirectory: true)
    }

    private static func storeURL() -> URL {
        storageRootURL().appendingPathComponent("Bubu.sqlite")
    }

    private static func legacyStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Bubu.sqlite")
    }

    private static func migrateLegacyStoreIfNeeded(inMemory: Bool) throws {
        guard !inMemory else { return }

        let fileManager = FileManager.default
        let currentURL = storeURL()
        let legacyURL = legacyStoreURL()

        guard currentURL.path != legacyURL.path else { return }
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        let currentExists = fileManager.fileExists(atPath: currentURL.path)
        if currentExists,
           let attributes = try? fileManager.attributesOfItem(atPath: currentURL.path),
           let size = attributes[.size] as? NSNumber,
           size.intValue > 0 {
            return
        }

        let relatedExtensions = ["", "-wal", "-shm"]
        for ext in relatedExtensions {
            let fromURL = URL(fileURLWithPath: legacyURL.path + ext)
            let toURL = URL(fileURLWithPath: currentURL.path + ext)

            guard fileManager.fileExists(atPath: fromURL.path) else { continue }

            if fileManager.fileExists(atPath: toURL.path) {
                try fileManager.removeItem(at: toURL)
            }
            try fileManager.copyItem(at: fromURL, to: toURL)
        }
    }
}
