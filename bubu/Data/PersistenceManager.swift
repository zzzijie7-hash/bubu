import CoreData

final class PersistenceManager: ObservableObject {
    static let shared = PersistenceManager()

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Bubu")

        guard let storeDescription = container.persistentStoreDescriptions.first else {
            fatalError("未找到持久化存储描述")
        }

        if inMemory {
            storeDescription.url = URL(fileURLWithPath: "/dev/null")
        } else {
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            storeDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            storeDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.com.bubu.app"
            )
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Core Data + CloudKit 加载失败: \(error)")
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
}