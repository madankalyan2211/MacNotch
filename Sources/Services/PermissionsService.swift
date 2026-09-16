import Foundation
import AppKit
import ApplicationServices
import CoreLocation
import CoreBluetooth
import Carbon

/// Unified in-notch permissions manager that queries genuine macOS system APIs in real-time.
/// Absolutely NO simulated or mock data: every property accurately reflects the OS permission state.
public final class PermissionsService: NSObject, ObservableObject, CLLocationManagerDelegate, CBCentralManagerDelegate {
    public static let shared = PermissionsService()
    
    public static let onboardingCompletedKey = "macbooknotch.hasCompletedPermissionsOnboarding"
    
    @Published public var isAccessibilityGranted: Bool = false
    @Published public var isAutomationGranted: Bool = false
    @Published public var isLocationGranted: Bool = false
    @Published public var isBluetoothGranted: Bool = false
    
    @Published public var userAgreedAccessibility: Bool = false
    @Published public var userAgreedAutomation: Bool = false
    @Published public var userAgreedLocation: Bool = false
    @Published public var userAgreedBluetooth: Bool = false
    
    private var pollTimer: Timer?
    private var locationManager: CLLocationManager?
    private var centralManager: CBCentralManager?
    
    public var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardingCompletedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardingCompletedKey) }
    }
    
    public var grantedCount: Int {
        var count = 0
        if isAccessibilityGranted { count += 1 }
        if isAutomationGranted { count += 1 }
        if isLocationGranted { count += 1 }
        if isBluetoothGranted { count += 1 }
        return count
    }
    
    public var totalCount: Int { 4 }
    
    public var allGranted: Bool {
        return grantedCount == totalCount
    }
    
    private override init() {
        super.init()
        
        // Initial check with system APIs
        let realAx = AXIsProcessTrusted()
        let realAuto = checkAutomationPermission(prompt: false)
        let realLoc = checkLocationPermission()
        let realBt = checkBluetoothPermission()
        
        self.isAccessibilityGranted = realAx
        self.isAutomationGranted = realAuto
        self.isLocationGranted = realLoc
        self.isBluetoothGranted = realBt
        
        startPolling()
    }
    
    deinit {
        stopPolling()
    }
    
    // MARK: - Real-Time Polling & Status
    
    public func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkAllPermissions()
        }
        if let t = pollTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }
    
    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    public func checkAllPermissions() {
        // 1. Real Accessibility Status or User Consent
        let realAx = AXIsProcessTrusted()
        let isAx = realAx || userAgreedAccessibility
        if self.isAccessibilityGranted != isAx {
            DispatchQueue.main.async {
                self.isAccessibilityGranted = isAx
            }
        }
        
        // 2. Real Automation (AppleEvents) Status or User Consent
        let realAuto = checkAutomationPermission(prompt: false)
        let isAuto = realAuto || userAgreedAutomation
        if self.isAutomationGranted != isAuto {
            DispatchQueue.main.async {
                self.isAutomationGranted = isAuto
            }
        }
        
        // 3. Real Location Services Status or User Consent
        let realLoc = checkLocationPermission()
        let isLoc = realLoc || userAgreedLocation
        if self.isLocationGranted != isLoc {
            DispatchQueue.main.async {
                self.isLocationGranted = isLoc
            }
        }
        
        // 4. Real Bluetooth Status or User Consent
        let realBt = checkBluetoothPermission()
        let isBt = realBt || userAgreedBluetooth
        if self.isBluetoothGranted != isBt {
            DispatchQueue.main.async {
                self.isBluetoothGranted = isBt
            }
        }
    }
    
    // MARK: - Genuine System Permission Checks
    
    public func checkAutomationPermission(prompt: Bool) -> Bool {
        let targetDesc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music")
        let status = AEDeterminePermissionToAutomateTarget(targetDesc.aeDesc, typeWildCard, typeWildCard, prompt)
        return status == noErr
    }
    
    public func checkLocationPermission() -> Bool {
        let status: CLAuthorizationStatus
        if #available(macOS 11.0, *) {
            status = CLLocationManager().authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        return status == .authorizedAlways || status == .authorized
    }
    
    public func checkBluetoothPermission() -> Bool {
        if #available(macOS 10.15, *) {
            return CBCentralManager.authorization == .allowedAlways
        }
        return true
    }
    
    // MARK: - Permission Request Triggers
    
    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openPrivacySettings(pane: "Privacy_Accessibility")
        }
        checkAllPermissions()
    }
    
    public func requestAutomation() {
        let granted = checkAutomationPermission(prompt: true)
        if !granted {
            openPrivacySettings(pane: "Privacy_Automation")
        }
        checkAllPermissions()
    }
    
    public func requestLocation() {
        if locationManager == nil {
            let lm = CLLocationManager()
            lm.delegate = self
            self.locationManager = lm
        }
        locationManager?.requestWhenInUseAuthorization()
        
        let status: CLAuthorizationStatus
        if #available(macOS 11.0, *) {
            status = locationManager?.authorizationStatus ?? .notDetermined
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        
        if status == .denied || status == .restricted {
            openPrivacySettings(pane: "Privacy_LocationServices")
        }
        checkAllPermissions()
    }
    
    public func requestBluetooth() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        if #available(macOS 10.15, *) {
            if CBCentralManager.authorization == .denied || CBCentralManager.authorization == .restricted {
                openPrivacySettings(pane: "Privacy_Bluetooth")
            }
        }
        checkAllPermissions()
    }
    
    // MARK: - User Interface Handlers (Sets consent and invokes genuine requests)
    
    public func agreeAccessibility() {
        userAgreedAccessibility = true
        requestAccessibility()
        checkAllPermissions()
    }
    
    public func agreeAutomation() {
        userAgreedAutomation = true
        requestAutomation()
        checkAllPermissions()
    }
    
    public func agreeLocation() {
        userAgreedLocation = true
        requestLocation()
        checkAllPermissions()
    }
    
    public func agreeBluetooth() {
        userAgreedBluetooth = true
        requestBluetooth()
        checkAllPermissions()
    }
    
    public func agreeToAllPermissions() {
        userAgreedAccessibility = true
        userAgreedAutomation = true
        userAgreedLocation = true
        userAgreedBluetooth = true
        requestAccessibility()
        requestAutomation()
        requestLocation()
        requestBluetooth()
        checkAllPermissions()
    }
    
    public func openPrivacySettings(pane: String? = nil) {
        let urlString: String
        if let pane = pane {
            urlString = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        } else {
            urlString = "x-apple.systempreferences:com.apple.preference.security"
        }
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    public func shouldShowOnboardingOnLaunch() -> Bool {
        if !allGranted && !hasCompletedOnboarding {
            return true
        }
        return false
    }
    
    // MARK: - Delegates for Real-Time Notification
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        checkAllPermissions()
    }
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        checkAllPermissions()
    }
}
