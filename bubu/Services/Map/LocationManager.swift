import CoreLocation
import SwiftUI

// MARK: - 定位管理器

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    @Published var currentAddress: String = "SOHO复兴广场"
    @Published var error: String?

    // 模拟器默认定位：上海 SOHO 复兴广场
    static let defaultLocation = CLLocation(latitude: 31.215070, longitude: 121.474434)

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // 模拟器无真实 GPS，直接设置兜底位置
        #if targetEnvironment(simulator)
        currentLocation = Self.defaultLocation
        authorizationStatus = .authorizedWhenInUse
        #endif
    }

    func requestPermission() {
        authorizationStatus = manager.authorizationStatus
        #if targetEnvironment(simulator)
        authorizationStatus = .authorizedWhenInUse
        currentLocation = Self.defaultLocation
        #else
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
        #endif
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            currentLocation = locations.last
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.error = error.localizedDescription
        }
    }
}