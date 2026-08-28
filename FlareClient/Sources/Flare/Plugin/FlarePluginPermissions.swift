import UIKit
import AVFoundation
import Photos
import CoreLocation

/// Generic, multi-permission manager providing identical functionality to Android's FlarePluginPermissions.
public final class FlarePluginPermissions: NSObject, CLLocationManagerDelegate {
    public enum PermissionType {
        case camera
        case photoLibrary
        case location
        case microphone
    }

    private static let shared = FlarePluginPermissions()
    private var locationCompletion: ((Bool) -> Void)?
    private lazy var locationManager: CLLocationManager = {
        let lm = CLLocationManager()
        lm.delegate = self
        return lm
    }()

    private override init() { super.init() }

    public static func request(_ type: PermissionType, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            switch type {
            case .camera:
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: completion(true)
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async { completion(granted) }
                    }
                default: completion(false)
                }

            case .photoLibrary:
                let status = PHPhotoLibrary.authorizationStatus()
                if status == .authorized || status == .limited {
                    completion(true)
                } else if status == .notDetermined {
                    PHPhotoLibrary.requestAuthorization { newStatus in
                        DispatchQueue.main.async { completion(newStatus == .authorized || newStatus == .limited) }
                    }
                } else {
                    completion(false)
                }

            case .microphone:
                switch AVAudioSession.sharedInstance().recordPermission {
                case .granted: completion(true)
                case .undetermined:
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        DispatchQueue.main.async { completion(granted) }
                    }
                default: completion(false)
                }

            case .location:
                let status = shared.locationManager.authorizationStatus
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    completion(true)
                } else if status == .notDetermined {
                    shared.locationCompletion = completion
                    shared.locationManager.requestWhenInUseAuthorization()
                } else {
                    completion(false)
                }
            }
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            locationCompletion?(status == .authorizedWhenInUse || status == .authorizedAlways)
            locationCompletion = nil
        }
    }
}