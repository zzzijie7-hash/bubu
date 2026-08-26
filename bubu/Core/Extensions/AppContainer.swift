import Foundation
import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    static let shared = AppContainer()

    let mapService: MapServiceProtocol
    let importService: ImportCoordinatorProtocol
    let apiClient: APIClientProtocol
    let persistence: PersistenceManager
    let placeRepository: PlaceRepository
    let locationManager: LocationManager

    private init() {
        self.mapService = AMapService(apiKey: "92cf389ba2140609c84bc8e84bee9ae1")
        self.importService = SmartImportService()
        self.apiClient = MockAPIClient()
        self.persistence = PersistenceManager()
        self.placeRepository = PlaceRepository(persistence: self.persistence)
        self.locationManager = LocationManager()
    }
}
