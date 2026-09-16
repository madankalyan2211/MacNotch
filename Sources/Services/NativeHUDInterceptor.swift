import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

/// Service that actively intercepts hardware media keys to suppress stock macOS Volume, Brightness, and Mute HUD overlays.
public final class NativeHUDInterceptor: ObservableObject {
    public static let shared = NativeHUDInterceptor()
    
    @Published public private(set) var isSuppressionEnabled: Bool = true
    @Published public private(set) var hasAccessibilityPermission: Bool = false
    
    public var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionPollTimer: Timer?
    
    private init() {
        checkAccessibilityPermission(prompt: false)
        start()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkAccessibilityPermission(prompt: false)
        }
    }
    
    deinit {
        stopPermissionPolling()
        stop()
    }
    
    public func start() {
        applyOSDPrefs(suppress: isSuppressionEnabled)
        if isSuppressionEnabled {
            setupEventTap()
        }
    }
    
    public func setEnabled(_ enabled: Bool) {
        self.isSuppressionEnabled = enabled
        applyOSDPrefs(suppress: enabled)
        
        if enabled {
            setupEventTap()
        } else {
            stopEventTap()
        }
    }
    
    public func stop() {
        applyOSDPrefs(suppress: false)
        stopEventTap()
        resetMapping()
    }
    
    public func requestAccessibilityPermission() {
        let trusted = checkAccessibilityPermission(prompt: true)
        if trusted {
            setupEventTap()
        } else {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            startPermissionPolling()
        }
    }
    
    public func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if self.checkAccessibilityPermission(prompt: false) {
                self.stopPermissionPolling()
            }
        }
    }
    
    public func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }
    
    @discardableResult
    public func checkAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        
        DispatchQueue.main.async {
            if self.hasAccessibilityPermission != trusted {
                self.hasAccessibilityPermission = trusted
            }
            if trusted && self.isSuppressionEnabled && self.eventTap == nil {
                self.setupEventTap()
            }
        }
        return trusted
    }
    
    private func setupEventTap() {
        stopEventTap()
        guard isSuppressionEnabled else { return }
        
        // Check permission without prompting repeatedly
        _ = checkAccessibilityPermission(prompt: false)
        
        // 14 = NX_SYSDEFINED (media keys, volume, brightness)
        let mask = CGEventMask(1 << 14)
        
        let tapCallback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = NativeHUDInterceptor.shared.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return nil
            }
            
            if type.rawValue == 14 { // NX_SYSDEFINED
                if let nsEvent = NSEvent(cgEvent: event), nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 {
                    let data1 = nsEvent.data1
                    let keyCode = Int((data1 & 0xFFFF0000) >> 16)
                    let keyFlags = (data1 & 0x0000FFFF)
                    let keyState = (keyFlags & 0xFF00) >> 8
                    let isKeyDown = (keyState == 0xA || keyState == 0x1)
                    
                    if NativeHUDInterceptor.shared.isSuppressionEnabled {
                        switch keyCode {
                        case 0: // Sound Up
                            if isKeyDown {
                                NativeHUDInterceptor.shared.handleSoundUp(flags: nsEvent.modifierFlags)
                            }
                            return nil // CONSUME: Suppresses macOS stock Volume HUD
                        case 1: // Sound Down
                            if isKeyDown {
                                NativeHUDInterceptor.shared.handleSoundDown(flags: nsEvent.modifierFlags)
                            }
                            return nil // CONSUME: Suppresses macOS stock Volume HUD
                        case 7: // Mute
                            if isKeyDown {
                                NativeHUDInterceptor.shared.handleMute()
                            }
                            return nil // CONSUME: Suppresses macOS stock Mute HUD
                        case 2: // Brightness Up
                            if isKeyDown {
                                NativeHUDInterceptor.shared.handleBrightnessUp(flags: nsEvent.modifierFlags)
                            }
                            return nil // CONSUME: Suppresses macOS stock Brightness HUD
                        case 3: // Brightness Down
                            if isKeyDown {
                                NativeHUDInterceptor.shared.handleBrightnessDown(flags: nsEvent.modifierFlags)
                            }
                            return nil // CONSUME: Suppresses macOS stock Brightness HUD
                        default:
                            break
                        }
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) ?? CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) else {
            return
        }
        
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    
    private func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let src = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            }
            self.eventTap = nil
            self.runLoopSource = nil
        }
    }
    
    // MARK: - Direct Hardware Level Adjustments
    
    public func handleSoundUp(flags: NSEvent.ModifierFlags) {
        let isFine = flags.contains(.shift) && flags.contains(.option)
        let step: Float = isFine ? (1.0 / 64.0) : (1.0 / 16.0)
        let current = SystemHUDService.shared.getCurrentVolume()
        let newVol = min(1.0, current + step)
        SystemHUDService.shared.setVolume(level: newVol)
    }
    
    public func handleSoundDown(flags: NSEvent.ModifierFlags) {
        let isFine = flags.contains(.shift) && flags.contains(.option)
        let step: Float = isFine ? (1.0 / 64.0) : (1.0 / 16.0)
        let current = SystemHUDService.shared.getCurrentVolume()
        let newVol = max(0.0, current - step)
        SystemHUDService.shared.setVolume(level: newVol)
    }
    
    public func handleMute() {
        SystemHUDService.shared.toggleMute()
    }
    
    public func handleBrightnessUp(flags: NSEvent.ModifierFlags) {
        let isFine = flags.contains(.shift) && flags.contains(.option)
        let step: Float = isFine ? (1.0 / 64.0) : (1.0 / 16.0)
        let current = SystemHUDService.shared.getCurrentBrightness()
        let newBri = min(1.0, current + step)
        SystemHUDService.shared.setBrightness(level: newBri)
    }
    
    public func handleBrightnessDown(flags: NSEvent.ModifierFlags) {
        let isFine = flags.contains(.shift) && flags.contains(.option)
        let step: Float = isFine ? (1.0 / 64.0) : (1.0 / 16.0)
        let current = SystemHUDService.shared.getCurrentBrightness()
        let newBri = max(0.0, current - step)
        SystemHUDService.shared.setBrightness(level: newBri)
    }
    
    private func applyOSDPrefs(suppress: Bool) {
        let p1 = Process()
        p1.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        if suppress {
            p1.arguments = ["write", "com.apple.OSDUIHelper", "hideOSD", "-bool", "true"]
        } else {
            p1.arguments = ["delete", "com.apple.OSDUIHelper", "hideOSD"]
        }
        try? p1.run()
        
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p2.arguments = ["OSDUIHelper"]
        try? p2.run()
    }
    
    private func resetMapping() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", "{\"UserKeyMapping\":[]}"]
        try? process.run()
    }
}
