import Foundation
import Cocoa
import CoreAudio
import CoreMediaIO
import Combine
import SQLite3

public enum CallState: String, Sendable {
    case ringing = "Ringing..."
    case connecting = "Connecting..."
    case active = "Active"
    case ended = "Ended"
}

public struct CallInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public var callerName: String
    public var appName: String
    public var isVideo: Bool
    public var state: CallState
    public var durationSeconds: Int
    public var isMuted: Bool
    
    public var formattedDuration: String {
        switch state {
        case .ringing, .connecting:
            return state.rawValue
        case .active:
            let mins = durationSeconds / 60
            let secs = durationSeconds % 60
            return String(format: "%02d:%02d", mins, secs)
        case .ended:
            return "Call Ended"
        }
    }
}

/// Service that monitors live microphone activity and call applications (FaceTime, WhatsApp, Zoom, Teams, Slack).
public final class CallMonitorService: ObservableObject {
    public static let shared = CallMonitorService()
    
    @Published public private(set) var activeCall: CallInfo?
    public var onCallStarted: ((CallInfo) -> Void)?
    public var onCallUpdated: ((CallInfo) -> Void)?
    public var onCallEnded: (() -> Void)?
    
    private var pollTimer: Timer?
    private var durationTimer: Timer?
    private var isMicActive: Bool = false
    private var callStartTime: Date?
    private var isSimulated: Bool = false
    private var pendingRingTicks: Int = 0
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        pollTimer?.invalidate()
        durationTimer?.invalidate()
    }
    
    public func startMonitoring() {
        pollTimer?.invalidate()
        
        // Fast 0.6s microphone & window activity poller
        let timer = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            self?.checkMicrophoneAndCallState()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer
    }
    
    public func checkMicrophoneAndCallState() {
        guard !isSimulated else { return }
        
        let micActive = queryMicrophoneRunningState()
        
        if micActive && !isMicActive {
            // Check if this is an actual calling application before triggering Call HUD
            let detected = detectActiveCallingApp()
            guard detected.isKnownCallApp else { return }
            
            isMicActive = true
            callStartTime = nil
            pendingRingTicks = 2
            
            let info = CallInfo(
                id: UUID().uuidString,
                callerName: detected.callerName,
                appName: detected.appName,
                isVideo: detected.isVideo,
                state: .ringing,
                durationSeconds: 0,
                isMuted: isSystemMicrophoneMuted()
            )
            
            self.activeCall = info
            startDurationTracker()
            
            DispatchQueue.main.async { [weak self] in
                self?.onCallStarted?(info)
            }
        } else if !micActive && isMicActive {
            // Call ended
            isMicActive = false
            callStartTime = nil
            pendingRingTicks = 0
            stopDurationTracker()
            self.activeCall = nil
            
            DispatchQueue.main.async { [weak self] in
                self?.onCallEnded?()
            }
        } else if micActive && isMicActive {
            // Update caller name and camera if updated during active call
            if var call = activeCall {
                let detected = detectActiveCallingApp()
                if detected.isKnownCallApp && detected.callerName != "Audio Call" && detected.callerName != "Video Call" {
                    if call.callerName != detected.callerName {
                        // FIX: Don't change WhatsApp caller name mid-call if it's already set to a real name
                        // because getLastWhatsAppPartnerName() returns the sender of the most recent text message.
                        let isWhatsApp = detected.appName.contains("WhatsApp")
                        let isGenericName = call.callerName == "WhatsApp Contact" || call.callerName == "Audio Call"
                        
                        if !isWhatsApp || isGenericName {
                            call.callerName = detected.callerName
                            self.activeCall = call
                            DispatchQueue.main.async { [weak self] in
                                self?.onCallUpdated?(call)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func queryCameraRunningState() -> Bool {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        
        var dataSize: UInt32 = 0
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr, dataSize > 0 else { return false }
        
        let deviceCount = Int(dataSize) / MemoryLayout<CMIODeviceID>.size
        var devices = [CMIODeviceID](repeating: 0, count: deviceCount)
        
        let getStatus = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &dataUsed,
            &devices
        )
        
        guard getStatus == noErr else { return false }
        
        for device in devices {
            var isRunning: UInt32 = 0
            let isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            
            var runDataUsed: UInt32 = 0
            let runStatus = CMIOObjectGetPropertyData(
                device,
                &runningAddress,
                0,
                nil,
                isRunningSize,
                &runDataUsed,
                &isRunning
            )
            
            if runStatus == noErr && isRunning != 0 {
                return true
            }
        }
        
        return false
    }
    
    private func queryMicrophoneRunningState() -> Bool {
        var defaultInputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &defaultInputDeviceID
        )
        guard status == noErr, defaultInputDeviceID != 0 else { return false }
        
        var isRunning: UInt32 = 0
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
        var isRunningAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        if AudioObjectGetPropertyData(defaultInputDeviceID, &isRunningAddr, 0, nil, &isRunningSize, &isRunning) == noErr {
            return isRunning != 0
        }
        return false
    }
    
    private func isSystemMicrophoneMuted() -> Bool {
        var defaultInputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &defaultInputDeviceID) == noErr, defaultInputDeviceID != 0 else {
            return false
        }
        
        var isMuted: UInt32 = 0
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(defaultInputDeviceID, &muteAddr, 0, nil, &muteSize, &isMuted) == noErr {
            return isMuted != 0
        }
        return false
    }
    
    public func setSystemMicrophoneMute(isMuted: Bool) {
        var defaultInputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &defaultInputDeviceID) == noErr, defaultInputDeviceID != 0 else {
            return
        }
        
        var muteVal: UInt32 = isMuted ? 1 : 0
        let muteSize = UInt32(MemoryLayout<UInt32>.size)
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var canMute: DarwinBoolean = false
        if AudioObjectHasProperty(defaultInputDeviceID, &muteAddr) {
            AudioObjectIsPropertySettable(defaultInputDeviceID, &muteAddr, &canMute)
            if canMute.boolValue {
                AudioObjectSetPropertyData(defaultInputDeviceID, &muteAddr, 0, nil, muteSize, &muteVal)
            }
        }
        
        // Input Volume fallback scalar: 0.0 when muted, 1.0 when unmuted
        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(defaultInputDeviceID, &volAddr) {
            var vol: Float32 = isMuted ? 0.0 : 1.0
            let volSize = UInt32(MemoryLayout<Float32>.size)
            AudioObjectSetPropertyData(defaultInputDeviceID, &volAddr, 0, nil, volSize, &vol)
        }
    }
    
    private func isSiriActive() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for win in windowList {
            let ownerName = ((win[kCGWindowOwnerName as String] as? String) ?? "").lowercased()
            let winTitle = ((win[kCGWindowName as String] as? String) ?? "").lowercased()
            if ownerName == "siri" || ownerName == "sirinc" || ownerName == "assistantd" || ownerName.contains("siri") || winTitle == "siri" {
                return true
            }
        }
        return false
    }

    private func detectActiveCallingApp() -> (callerName: String, appName: String, isVideo: Bool, isKnownCallApp: Bool) {
        // 1. Explicitly ignore system Siri / Dictation microphone activations
        if isSiriActive() {
            return ("Audio Call", "Audio Call", false, false)
        }
        
        let isVideo = queryCameraRunningState()
        
        // 2. Inspect on-screen window titles for genuine calling applications
        if let winInfo = getActiveCallWindowTitle(isVideo: isVideo) {
            return (winInfo.callerName, winInfo.appName, winInfo.isVideo, true)
        }
        
        return ("Audio Call", "Audio Call", isVideo, false)
    }
    
    private func getActiveCallWindowTitle(isVideo: Bool) -> (callerName: String, appName: String, isVideo: Bool)? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for win in windowList {
            let ownerName = (win[kCGWindowOwnerName as String] as? String) ?? ""
            let winTitle = (win[kCGWindowName as String] as? String) ?? ""
            let ownerLower = ownerName.lowercased()
            let titleLower = winTitle.lowercased()
            
            // Ignore system assistant windows
            if ownerLower.contains("siri") || ownerLower.contains("assistantd") || titleLower == "siri" {
                continue
            }
            
            // WhatsApp Call detection
            // A genuine WhatsApp call window contains "call" or "calling" in the window title
            if ownerLower.contains("whatsapp") {
                let isCallWindow = titleLower.contains("call") || titleLower.contains("calling") || titleLower.contains("video call") || titleLower.contains("audio call")
                if isCallWindow {
                    var caller = winTitle.replacingOccurrences(of: "WhatsApp Video Call with ", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "WhatsApp Call with ", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "WhatsApp Video Call", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "WhatsApp Call", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "WhatsApp - ", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "WhatsApp", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "Call with ", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if caller.isEmpty { caller = getLastWhatsAppPartnerName() ?? "WhatsApp Contact" }
                    return (caller, isVideo ? "WhatsApp Video" : "WhatsApp Call", isVideo)
                }
            }
            
            // FaceTime Call detection
            if ownerLower.contains("facetime") {
                let isCallWindow = titleLower.contains("with") || titleLower.contains("call") || titleLower.contains("audio") || titleLower.contains("video") || titleLower.contains("connecting") || titleLower.contains("ringing") || isVideo
                if isCallWindow {
                    var caller = winTitle.replacingOccurrences(of: "FaceTime with ", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "FaceTime - ", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "FaceTime Call", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "FaceTime", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if caller.isEmpty { caller = "FaceTime Call" }
                    return (caller, isVideo ? "FaceTime Video" : "FaceTime Audio", isVideo)
                }
            }
            
            // Zoom Meeting detection
            if ownerLower.contains("zoom") {
                let isMeetingWindow = titleLower.contains("meeting") || titleLower.contains("webinar") || titleLower.contains("call")
                if isMeetingWindow {
                    var caller = winTitle.replacingOccurrences(of: "Zoom Meeting - ", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "Zoom Meeting", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "Zoom", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if caller.isEmpty { caller = "Zoom Meeting" }
                    return (caller, isVideo ? "Zoom Video" : "Zoom Audio", isVideo)
                }
            }
            
            // Microsoft Teams detection
            if ownerLower.contains("teams") {
                let isCallWindow = titleLower.contains("meeting") || titleLower.contains("call") || titleLower.contains("huddle")
                if isCallWindow {
                    var caller = winTitle.replacingOccurrences(of: "Microsoft Teams - ", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "Microsoft Teams", with: "", options: .caseInsensitive)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if caller.isEmpty { caller = "Microsoft Teams" }
                    return (caller, isVideo ? "Teams Video" : "Teams Call", isVideo)
                }
            }
            
            // Slack Huddle detection
            if ownerLower.contains("slack") && (titleLower.contains("huddle") || titleLower.contains("call")) {
                return (winTitle.isEmpty ? "Slack Huddle" : winTitle, isVideo ? "Slack Video" : "Slack Huddle", isVideo)
            }
            
            // Google Meet detection
            if (ownerLower.contains("chrome") || ownerLower.contains("safari") || ownerLower.contains("edge") || ownerLower.contains("brave") || ownerLower.contains("arc")) && (titleLower.contains("meet.google.com") || titleLower.contains("meet - ") || titleLower.contains("google meet")) {
                let caller = winTitle.replacingOccurrences(of: " - Google Chrome", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " - Google Meet", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " - Safari", with: "", options: .caseInsensitive)
                    .replacingOccurrences(of: " - Arc", with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (caller.isEmpty ? "Google Meet" : caller, isVideo ? "Meet Video" : "Google Meet", isVideo)
            }
            
            // Cisco Webex detection
            if ownerLower.contains("webex") && (titleLower.contains("meeting") || titleLower.contains("call")) {
                return ("Webex Meeting", isVideo ? "Webex Video" : "Webex Audio", isVideo)
            }
            
            // Discord Voice detection
            if ownerLower.contains("discord") && (titleLower.contains("voice connected") || titleLower.contains("call") || isVideo) {
                return ("Discord Voice", isVideo ? "Discord Video" : "Discord Voice", isVideo)
            }
        }
        return nil
    }
    
    private func getLastWhatsAppPartnerName() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(home)/Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite"
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        
        let query = """
        SELECT COALESCE(NULLIF(s.ZPARTNERNAME, ''), p.ZPUSHNAME, s.ZCONTACTJID)
        FROM ZWAMESSAGE m
        LEFT JOIN ZWACHATSESSION s ON m.ZCHATSESSION = s.Z_PK
        LEFT JOIN ZWAPROFILEPUSHNAME p ON (m.ZFROMJID = p.ZJID OR s.ZCONTACTJID = p.ZJID)
        WHERE m.ZISFROMME = 0
        ORDER BY m.Z_PK DESC LIMIT 1;
        """
        var stmt: OpaquePointer?
        var result: String?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let str = sqlite3_column_text(stmt, 0) {
                    result = String(cString: str)
                }
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    private func startDurationTracker() {
        durationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, var call = self.activeCall else { return }
            
            if self.pendingRingTicks > 0 {
                self.pendingRingTicks -= 1
                if self.pendingRingTicks == 0 {
                    // Call is now answered and active
                    call.state = .active
                    call.durationSeconds = 0
                    self.callStartTime = Date()
                }
            } else {
                call.state = .active
                call.durationSeconds += 1
            }
            
            if !self.isSimulated {
                call.isVideo = self.queryCameraRunningState()
                call.isMuted = self.isSystemMicrophoneMuted()
            }
            self.activeCall = call
            DispatchQueue.main.async {
                self.onCallUpdated?(call)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.durationTimer = timer
    }
    
    private func stopDurationTracker() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
    
    /// Simulates / Toggles a live call for testing & demonstrations
    public func toggleSimulatedCall() {
        if isSimulated {
            // End simulated call
            isSimulated = false
            stopDurationTracker()
            self.activeCall = nil
            self.onCallEnded?()
        } else {
            // Start simulated call
            isSimulated = true
            pendingRingTicks = 2
            let info = CallInfo(
                id: "simulated.call",
                callerName: "Vishnusai Sai",
                appName: "WhatsApp Call",
                isVideo: false,
                state: .ringing,
                durationSeconds: 0,
                isMuted: false
            )
            self.activeCall = info
            startDurationTracker()
            self.onCallStarted?(info)
        }
    }
    
    public func toggleMute() {
        guard var call = activeCall else { return }
        call.isMuted.toggle()
        setSystemMicrophoneMute(isMuted: call.isMuted)
        self.activeCall = call
        DispatchQueue.main.async { [weak self] in
            self?.onCallUpdated?(call)
        }
    }
    
    public func endCall() {
        isSimulated = false
        isMicActive = false
        pendingRingTicks = 0
        setSystemMicrophoneMute(isMuted: false)
        stopDurationTracker()
        self.activeCall = nil
        self.onCallEnded?()
    }
}
