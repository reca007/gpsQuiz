import Combine
import CoreLocation
import Foundation

enum LocationPermissionState: Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

enum GPSQuality: String {
    case unavailable = "Ingen GPS-position"
    case poor = "Svag GPS-signal"
    case fair = "Okej GPS-signal"
    case good = "Bra GPS-signal"
}

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var permissionState: LocationPermissionState = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var gpsQuality: GPSQuality = .unavailable
    @Published private(set) var lastErrorMessage: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        updatePermissionState(manager.authorizationStatus)
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        updatePermissionState(manager.authorizationStatus)
        guard permissionState == .authorized else { return }
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
    }

    func distance(from checkpoint: Checkpoint) -> CLLocationDistance? {
        guard let currentLocation else { return nil }
        let target = CLLocation(latitude: checkpoint.latitude, longitude: checkpoint.longitude)
        return currentLocation.distance(from: target)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updatePermissionState(manager.authorizationStatus)
        if permissionState == .authorized {
            startTracking()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
        lastErrorMessage = nil
        gpsQuality = quality(for: latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        gpsQuality = .unavailable
        lastErrorMessage = error.localizedDescription
    }

    private func updatePermissionState(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            permissionState = .notDetermined
        case .restricted:
            permissionState = .restricted
        case .denied:
            permissionState = .denied
        case .authorizedAlways, .authorizedWhenInUse:
            permissionState = .authorized
        @unknown default:
            permissionState = .restricted
        }
    }

    private func quality(for location: CLLocation) -> GPSQuality {
        guard location.horizontalAccuracy >= 0 else { return .unavailable }
        if location.horizontalAccuracy <= 20 { return .good }
        if location.horizontalAccuracy <= 60 { return .fair }
        return .poor
    }
}
