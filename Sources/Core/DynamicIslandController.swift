import SwiftUI
import Combine

/// Central coordinator managing island presentation state, active activity stream, animations, and system hooks.
public final class DynamicIslandController: ObservableObject {
    public static let shared = DynamicIslandController()
    
    // MARK: - Published State
    @Published public var state: IslandPresentationState = .idle
    @Published public var isHovered: Bool = false
    @Published public var currentGeometry: IslandGeometry = IslandGeometry()
    @Published public var activeActivity: (any DynamicIslandActivity)?
    @Published public var isEnabled: Bool = true
    
    // MARK: - Sub-Managers & Engines
    public let activityManager = ActivityManager()
    public let animationEngine = AnimationEngine.shared
    public let displayManager = DisplayManager.shared
    
    // MARK: - Settings Properties
    @Published public var autoCollapseDelay: Double = 6.0
    @Published public var isClipboardEnabled: Bool = true
    @Published public var isMusicEnabled: Bool = true
    @Published public var isTimerEnabled: Bool = true
    @Published public var isHUDEnabled: Bool = true
    @Published public var isVolumeHUDEnabled: Bool = true
    @Published public var isBrightnessHUDEnabled: Bool = true
    @Published public var isBatteryHUDEnabled: Bool = true
    @Published public var isFocusModeHUDEnabled: Bool = true
    @Published public var isCapsLockHUDEnabled: Bool = true
    @Published public var isLockHUDEnabled: Bool = true
    @Published public var isCaffeineHUDEnabled: Bool = true
    @Published public var isWeatherEnabled: Bool = true
    @Published public var isSportsEnabled: Bool = true
    @Published public var isNativeHUDSuppressionEnabled: Bool = true
    
    private var autoCollapseTimer: Timer?
    private var idleWeatherTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        setupBindings()
        setupServicesIntegration()
        updateGeometry(animated: false)
    }
    
    private func setupBindings() {
        // Observe display/notch changes
        displayManager.$currentNotchInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateGeometry(animated: true)
            }
            .store(in: &cancellables)
        
        // Observe activity changes from manager
        activityManager.onActivityChanged = { [weak self] oldAct, newAct in
            guard let self = self else { return }
            self.activeActivity = newAct
            if let newAct = newAct {
                if newAct.type != .weather {
                    self.idleWeatherTimer?.invalidate()
                    self.idleWeatherTimer = nil
                }
                if (newAct is PermissionsActivity || newAct is HelloSignatureActivity) {
                    self.transition(to: .expanded)
                } else if (self.state == .idle || self.state == .peek) {
                    self.transition(to: .compact)
                } else if (oldAct is HelloSignatureActivity || oldAct is ClipboardActivity) && (self.state == .expanded) {
                    self.transition(to: .compact)
                } else {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            } else {
                if self.state != .idle {
                    self.transition(to: .idle)
                }
                // Wait 3 minutes (180.0s) of sustained idle time before showing ambient weather
                self.scheduleAmbientWeatherPresentation(delay: 180.0)
            }
        }
        
        activityManager.$activeActivity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newActivity in
                guard let self = self else { return }
                self.activeActivity = newActivity
                if let newActivity = newActivity {
                    if (newActivity is PermissionsActivity || newActivity is HelloSignatureActivity) {
                        self.transition(to: .expanded)
                    } else if (self.state == .idle || self.state == .peek) {
                        self.transition(to: .compact)
                    } else {
                        withAnimation(self.animationEngine.morphSpring) {
                            self.updateGeometry(animated: true)
                        }
                    }
                } else {
                    if self.state != .idle {
                        self.transition(to: .idle)
                    }
                }
            }
            .store(in: &cancellables)
        
        // Synchronize native HUD suppression preference
        $isNativeHUDSuppressionEnabled
            .receive(on: DispatchQueue.main)
            .sink { enabled in
                NativeHUDInterceptor.shared.setEnabled(enabled)
            }
            .store(in: &cancellables)
    }
    
    private func setupServicesIntegration() {
        // 1. Media service integration (Track updates & Playback state)
        MediaService.shared.$currentTrack
            .combineLatest(MediaService.shared.$isPlaybackActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (track, isPlaying) in
                guard let self = self, self.isMusicEnabled else { return }
                
                // Only show dynamic pill if the media tab is NOT directly visible on the current screen
                let isBrowserMedia = ["YouTube", "Netflix", "JioHotstar", "JioCinema", "Hotstar"].contains(track.sourceApp)
                let shouldSuppressBecauseVisible = isBrowserMedia && track.isTabVisibleOnScreen
                
                if shouldSuppressBecauseVisible {
                    if self.state != .expanded, self.activityManager.getActivity(id: "activity.music") != nil {
                        self.activityManager.removeActivity(id: "activity.music")
                    }
                    return
                }
                
                if let existing = self.activityManager.getActivity(id: "activity.music") as? MusicActivity {
                    let titleChanged = (existing.title != track.title)
                    existing.title = track.title
                    existing.artist = track.artist
                    existing.album = track.album
                    existing.isPlaying = isPlaying
                    existing.duration = track.duration
                    if titleChanged {
                        existing.elapsedTime = track.elapsedTime
                    } else if track.elapsedTime > 0 && abs(existing.elapsedTime - track.elapsedTime) > 2.0 {
                        existing.elapsedTime = track.elapsedTime
                    }
                    existing.sourceApp = track.sourceApp
                    existing.artwork = track.artwork
                    
                    if isPlaying {
                        if self.activityManager.activeActivity?.id != existing.id {
                            self.activityManager.presentActivity(existing)
                        } else if self.state == .idle || self.state == .peek {
                            self.transition(to: .compact)
                        }
                    } else {
                        let isBrowserMedia = ["YouTube", "Netflix", "JioHotstar", "JioCinema", "Hotstar"].contains(track.sourceApp)
                        let delay: Double = isBrowserMedia ? 2.0 : 4.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self = self else { return }
                            if !MediaService.shared.isPlaybackActive {
                                self.activityManager.removeActivity(id: "activity.music")
                            }
                        }
                    }
                } else if isPlaying {
                    let musicAct = MusicActivity(
                        id: "activity.music",
                        title: track.title,
                        artist: track.artist,
                        album: track.album,
                        isPlaying: true,
                        duration: track.duration,
                        elapsedTime: track.elapsedTime,
                        sourceApp: track.sourceApp,
                        artwork: track.artwork
                    )
                    self.activityManager.presentActivity(musicAct)
                    if self.state == .idle || self.state == .peek {
                        self.transition(to: .compact)
                    }
                }
            }
            .store(in: &cancellables)
        
        // 2. Clipboard service integration
        ClipboardService.shared.onNewClipboardItem = { [weak self] item in
            guard let self = self, self.isClipboardEnabled else { return }
            let clipAct = ClipboardActivity(
                title: "Copied",
                subtitle: item.previewText,
                itemType: item.type,
                rawContent: item.previewText
            )
            self.activityManager.presentActivity(clipAct)
            self.transition(to: .expanded)
        }
        
        // 3. Timer service integration
        TimerService.shared.onTimerTick = { [weak self] timer in
            guard let self = self, self.isTimerEnabled else { return }
            if let existing = self.activityManager.getActivity(id: timer.id) as? TimerActivity {
                let wasHours = existing.remainingTime >= 3600
                existing.remainingTime = timer.remainingTime
                existing.totalDuration = timer.totalDuration
                existing.isRunning = timer.isRunning
                existing.isFinished = timer.isFinished
                let isHours = timer.remainingTime >= 3600
                if wasHours != isHours && self.activeActivity?.id == existing.id {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            } else {
                let timerAct = TimerActivity(
                    id: timer.id,
                    title: timer.label,
                    totalDuration: timer.totalDuration,
                    remainingTime: timer.remainingTime,
                    isRunning: timer.isRunning,
                    isFinished: timer.isFinished
                )
                if self.activityManager.getActivity(id: "activity.music") != nil {
                    self.activityManager.highlightPersistentActivity(activity: timerAct, duration: 2.5, returnToId: "activity.music")
                } else {
                    self.activityManager.presentActivity(timerAct)
                }
            }
        }
        
        TimerService.shared.onTimerFinished = { [weak self] timer in
            guard let self = self, self.isTimerEnabled else { return }
            
            let finishedAct = TimerActivity(
                id: timer.id,
                title: "Timer Done!",
                totalDuration: timer.totalDuration,
                remainingTime: 0,
                isRunning: false,
                isFinished: true,
                priority: .critical
            )
            finishedAct.timeoutDuration = 3.5
            self.activityManager.presentActivity(finishedAct)
        }
        
        TimerService.shared.onTimerStopped = { [weak self] in
            guard let self = self else { return }
            self.activityManager.removeActivity(id: "activity.timer")
            withAnimation(self.animationEngine.collapseSpring) {
                self.updateGeometry(animated: true)
            }
        }
        
        // 3b. macOS Native Clock App Timer Integration
        SystemClockMonitorService.shared.onTimerUpdated = { [weak self] macTimer in
            guard let self = self, self.isTimerEnabled else { return }
            if let existing = self.activityManager.getActivity(id: macTimer.id) as? TimerActivity {
                let wasHours = existing.remainingTime >= 3600
                existing.remainingTime = macTimer.remainingTime
                existing.totalDuration = macTimer.totalDuration
                existing.isRunning = macTimer.isRunning
                existing.isFinished = (macTimer.remainingTime <= 0)
                let isHours = macTimer.remainingTime >= 3600
                if wasHours != isHours && self.activeActivity?.id == existing.id {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            } else {
                let timerAct = TimerActivity(
                    id: macTimer.id,
                    title: macTimer.title,
                    totalDuration: macTimer.totalDuration,
                    remainingTime: macTimer.remainingTime,
                    isRunning: macTimer.isRunning,
                    isFinished: (macTimer.remainingTime <= 0)
                )
                if self.activityManager.getActivity(id: "activity.music") != nil {
                    self.activityManager.highlightPersistentActivity(activity: timerAct, duration: 2.5, returnToId: "activity.music")
                } else {
                    self.activityManager.presentActivity(timerAct)
                }
            }
        }
        
        SystemClockMonitorService.shared.onTimerEnded = { [weak self] in
            guard let self = self else { return }
            for act in self.activityManager.activityStack where act.id.starts(with: "clock.timer.") {
                self.activityManager.removeActivity(id: act.id)
            }
        }
        
        // 4. System HUDs integration
        SystemHUDService.shared.onHUDTriggered = { [weak self] event in
            guard let self = self, self.isHUDEnabled, !(self.activeActivity is PermissionsActivity) else { return }
            switch event.type {
            case .volume(let level, let isMuted):
                guard self.isVolumeHUDEnabled else { return }
                let volAct = (self.activityManager.getActivity(id: "hud.volume") as? VolumeActivity) ?? VolumeActivity(level: level, isMuted: isMuted)
                volAct.level = level
                volAct.isMuted = isMuted
                volAct.title = isMuted || level <= 0.001 ? "Silent" : "Volume"
                volAct.subtitle = "\(Int(level * 100))%"
                if self.activityManager.getActivity(id: "activity.music") != nil {
                    self.activityManager.promoteTemporarily(activity: volAct, duration: 2.0, fallbackId: "activity.music")
                } else {
                    self.activityManager.presentActivity(volAct)
                }
                if self.state == .idle || self.state == .peek {
                    self.transition(to: .compact)
                } else {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            case .brightness(let level):
                guard self.isBrightnessHUDEnabled else { return }
                let briAct = (self.activityManager.getActivity(id: "hud.brightness") as? BrightnessActivity) ?? BrightnessActivity(level: level)
                briAct.level = level
                briAct.title = "Brightness"
                briAct.subtitle = "\(Int(level * 100))%"
                if self.activityManager.getActivity(id: "activity.music") != nil {
                    self.activityManager.promoteTemporarily(activity: briAct, duration: 2.0, fallbackId: "activity.music")
                } else {
                    self.activityManager.presentActivity(briAct)
                }
                if self.state == .idle || self.state == .peek {
                    self.transition(to: .compact)
                } else {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            case .airPodsConnected(let name, let battery):
                let airAct = AirPodsActivity(title: name, batteryPercentage: battery)
                if self.activityManager.getActivity(id: "activity.music") != nil {
                    self.activityManager.promoteTemporarily(activity: airAct, duration: 4.0, fallbackId: "activity.music")
                } else {
                    self.activityManager.presentActivity(airAct)
                }
                if self.state == .idle || self.state == .peek {
                    self.transition(to: .compact)
                } else {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            case .downloadProgress(let filename, let progress):
                let downAct = DownloadActivity(filename: filename, progress: progress)
                if self.activityManager.getActivity(id: "activity.music") != nil {
                    self.activityManager.promoteTemporarily(activity: downAct, duration: 3.5, fallbackId: "activity.music")
                } else {
                    self.activityManager.presentActivity(downAct)
                }
                if self.state == .idle || self.state == .peek {
                    self.transition(to: .compact)
                } else {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            }
        }
        
        // 5. Battery service integration (Charging & Low Battery Warning)
        BatteryService.shared.onPowerSourceChanged = { [weak self] battery in
            guard let self = self, self.isHUDEnabled, self.isBatteryHUDEnabled else { return }
            let batAct = BatteryActivity(
                percentage: battery.percentage,
                isCharging: battery.isPluggedIn || battery.isCharging
            )
            if self.activityManager.getActivity(id: "activity.music") != nil {
                self.activityManager.promoteTemporarily(activity: batAct, duration: 3.5, fallbackId: "activity.music")
            } else {
                self.activityManager.presentActivity(batAct)
            }
            if self.state == .idle || self.state == .peek {
                self.transition(to: .compact)
            } else {
                withAnimation(self.animationEngine.morphSpring) {
                    self.updateGeometry(animated: true)
                }
            }
        }
        
        BatteryService.shared.onLowBatteryWarning = { [weak self] battery in
            guard let self = self, self.isHUDEnabled, self.isBatteryHUDEnabled else { return }
            let batAct = BatteryActivity(
                percentage: battery.percentage,
                isCharging: false
            )
            if self.activityManager.getActivity(id: "activity.music") != nil {
                self.activityManager.promoteTemporarily(activity: batAct, duration: 3.5, fallbackId: "activity.music")
            } else {
                self.activityManager.presentActivity(batAct)
            }
            if self.state == .idle || self.state == .peek {
                self.transition(to: .compact)
            } else {
                withAnimation(self.animationEngine.morphSpring) {
                    self.updateGeometry(animated: true)
                }
            }
        }
        
        // 6. Focus Mode / Do Not Disturb integration
        FocusModeService.shared.onFocusModeTriggered = { [weak self] event in
            guard let self = self, self.isHUDEnabled, self.isFocusModeHUDEnabled else { return }
            let focusAct = FocusActivity(
                name: event.name,
                iconName: event.iconName,
                tintColor: event.tintColor,
                isEnabled: event.isEnabled
            )
            if self.activityManager.getActivity(id: "activity.music") != nil {
                self.activityManager.promoteTemporarily(activity: focusAct, duration: 3.0, fallbackId: "activity.music")
            } else {
                self.activityManager.presentActivity(focusAct)
            }
            if self.state == .idle || self.state == .peek {
                self.transition(to: .compact)
            } else {
                withAnimation(self.animationEngine.morphSpring) {
                    self.updateGeometry(animated: true)
                }
            }
        }
        
        // 7. Bluetooth & AirPods service integration
        BluetoothService.shared.onDeviceConnected = { [weak self] device in
            guard let self = self, self.isHUDEnabled else { return }
            let airpodsAct = AirPodsActivity(device: device)
            if self.activityManager.getActivity(id: "activity.music") != nil {
                self.activityManager.promoteTemporarily(activity: airpodsAct, duration: 4.0, fallbackId: "activity.music")
            } else {
                self.activityManager.presentActivity(airpodsAct)
            }
            if self.state == .idle || self.state == .peek {
                self.transition(to: .compact)
            } else {
                withAnimation(self.animationEngine.morphSpring) {
                    self.updateGeometry(animated: true)
                }
            }
        }
        
        // 8. Live Voice & Video Calls integration
        CallMonitorService.shared.onCallStarted = { [weak self] call in
            guard let self = self else { return }
            let callAct = CallActivity(callInfo: call)
            self.activityManager.presentActivity(callAct)
        }
        
        CallMonitorService.shared.onCallUpdated = { [weak self] call in
            guard let self = self else { return }
            for act in self.activityManager.activityStack {
                if let callAct = act as? CallActivity {
                    callAct.updateCallInfo(call)
                }
            }
        }
        
        CallMonitorService.shared.onCallEnded = { [weak self] in
            guard let self = self else { return }
            for act in self.activityManager.activityStack where act.type == .call {
                self.activityManager.removeActivity(id: act.id)
            }
        }
        
        // 9. Voice Memos integration
        VoiceMemoService.shared.onRecordingStarted = { [weak self] memo in
            guard let self = self else { return }
            let memoAct = VoiceMemoActivity(memoInfo: memo)
            self.activityManager.presentActivity(memoAct)
        }
        
        VoiceMemoService.shared.onRecordingUpdated = { [weak self] memo in
            guard let self = self else { return }
            for act in self.activityManager.activityStack {
                if let memoAct = act as? VoiceMemoActivity {
                    memoAct.memoInfo = memo
                }
            }
        }
        
        VoiceMemoService.shared.onRecordingEnded = { [weak self] in
            guard let self = self else { return }
            for act in self.activityManager.activityStack where act.type == .voiceMemo {
                self.activityManager.removeActivity(id: act.id)
            }
        }
        
        // 10. Caps Lock HUD integration
        CapsLockService.shared.onCapsLockToggled = { [weak self] isOn in
            guard let self = self, self.isCapsLockHUDEnabled else { return }
            let capsAct = (self.activityManager.getActivity(id: "hud.capslock") as? CapsLockActivity) ?? CapsLockActivity(isOn: isOn)
            capsAct.isOn = isOn
            if self.activityManager.getActivity(id: "activity.music") != nil {
                self.activityManager.promoteTemporarily(activity: capsAct, duration: 2.0, fallbackId: "activity.music")
            } else {
                self.activityManager.presentActivity(capsAct)
            }
            if self.state == .idle || self.state == .peek {
                self.transition(to: .compact)
            } else {
                withAnimation(self.animationEngine.morphSpring) {
                    self.updateGeometry(animated: true)
                }
            }
        }
        
        // 11. Lock & Screen State integration (Only display on unlock)
        LockStateService.shared.onLockStateChanged = { [weak self] isLocked in
            guard let self = self, self.isLockHUDEnabled else { return }
            if isLocked {
                // Cleanly remove any lock HUD while locked
                self.activityManager.removeActivity(id: "hud.lock")
            } else {
                // When unlocked, present the Unlocked symbol indicator and auto-dismiss after 2.5s
                let unlockAct = LockActivity(isLocked: false, timeout: 2.5)
                if self.activityManager.getActivity(id: "activity.music") != nil {
                    self.activityManager.promoteTemporarily(activity: unlockAct, duration: 2.5, fallbackId: "activity.music")
                } else {
                    self.activityManager.presentActivity(unlockAct)
                }
                if self.state == .idle || self.state == .peek {
                    self.transition(to: .compact)
                } else {
                    withAnimation(self.animationEngine.morphSpring) {
                        self.updateGeometry(animated: true)
                    }
                }
            }
        }
        
        // 12. Caffeine (Keep Awake) integration
        CaffeineService.shared.onStateChanged = { [weak self] state in
            guard let self = self, self.isCaffeineHUDEnabled else { return }
            let caffAct = CaffeineActivity(
                id: "activity.caffeine",
                isActive: state.isActive,
                remainingSeconds: state.remainingSeconds,
                labelText: state.label,
                timeout: 4.0
            )
            if self.activityManager.getActivity(id: "activity.music") != nil {
                self.activityManager.promoteTemporarily(activity: caffAct, duration: 4.0, fallbackId: "activity.music")
            } else {
                self.activityManager.presentActivity(caffAct)
            }
            if self.state == .idle || self.state == .peek {
                self.transition(to: .compact)
            } else {
                withAnimation(self.animationEngine.morphSpring) {
                    self.updateGeometry(animated: true)
                }
            }
        }
        
        // 13. Ambient Live Weather & Air Quality integration
        WeatherService.shared.onWeatherUpdated = { [weak self] weather in
            guard let self = self, self.isWeatherEnabled else { return }
            if let existing = self.activityManager.getActivity(id: "activity.weather") as? WeatherActivity {
                existing.weather = weather
            }
        }
        
        // 14. Notch Drop Shelf & AirDrop Radar integration
        FileShelfService.shared.onFilesUpdated = { [weak self] files in
            guard let self = self else { return }
            if files.isEmpty {
                self.activityManager.removeActivity(id: "activity.shelf")
            } else {
                if self.activityManager.getActivity(id: "activity.shelf") == nil {
                    let shelfAct = FileShelfActivity()
                    self.activityManager.presentActivity(shelfAct)
                }
            }
        }
        
        // 15. Live Sports Ticker integration
        SportsService.shared.onMatchUpdated = { [weak self] match in
            guard let self = self, self.isSportsEnabled else { return }
            if let match = match {
                if let existing = self.activityManager.getActivity(id: "activity.sports.\(match.id)") as? SportsActivity {
                    existing.match = match
                }
            }
        }
        // WhatsAppNotificationService.shared.onMessageDismissed = { [weak self] in
        // Initial presentation of ambient weather with 3 minutes idle delay
        if isWeatherEnabled {
            scheduleAmbientWeatherPresentation(delay: 180.0)
        }
    }
    
    /// Schedules ambient weather presentation after a sustained idle period (3 minutes / 180s)
    public func scheduleAmbientWeatherPresentation(delay: TimeInterval = 180.0) {
        idleWeatherTimer?.invalidate()
        idleWeatherTimer = nil
        
        guard isWeatherEnabled else { return }
        guard !activityManager.activityStack.contains(where: { $0.type != .weather }) else { return }
        
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, self.isWeatherEnabled else { return }
            // Double check that we are still genuinely idle
            guard !self.activityManager.activityStack.contains(where: { $0.type != .weather }) else { return }
            
            let weatherAct: WeatherActivity
            if let existing = self.activityManager.getActivity(id: "activity.weather") as? WeatherActivity {
                weatherAct = existing
            } else {
                weatherAct = WeatherActivity(weather: WeatherService.shared.currentWeather)
            }
            self.activityManager.presentActivity(weatherAct)
            if self.state == .idle || self.state == .peek {
                self.transition(to: .compact)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.idleWeatherTimer = timer
    }
    
    // MARK: - State Transitions
    
    public func transition(to newState: IslandPresentationState) {
        guard state != newState else { return }
        
        // Prevent collapsing if Hello Signature or incomplete Permissions onboarding is active!
        if (newState == .compact || newState == .idle || newState == .peek) {
            if activeActivity is HelloSignatureActivity {
                return
            }
            if activeActivity is PermissionsActivity && !PermissionsService.shared.allGranted {
                return
            }
        }
        
        autoCollapseTimer?.invalidate()
        autoCollapseTimer = nil
        
        let isCollapsing = (newState == .compact || newState == .idle) && (state == .expanded)
        let spring = isCollapsing ? animationEngine.collapseSpring : animationEngine.morphSpring
        
        withAnimation(spring) {
            self.state = newState
            self.updateGeometry(animated: false)
        }
        
        // If expanded, set up auto-collapse countdown (except for interactive WhatsApp input, Permissions onboarding, or Hello Signature)
        if newState == .expanded && !(activeActivity is WhatsAppNotificationActivity) && !(activeActivity is PermissionsActivity) && !(activeActivity is HelloSignatureActivity) {
            let timer = Timer(timeInterval: autoCollapseDelay, repeats: false) { [weak self] _ in
                guard let self = self, self.state == .expanded else { return }
                if self.activeActivity != nil {
                    self.transition(to: .compact)
                } else {
                    self.transition(to: .idle)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            autoCollapseTimer = timer
        }
    }
    
    public func handleHover(isHovering: Bool) {
        self.isHovered = isHovering
        
        if activeActivity is HelloSignatureActivity { return }
        if activeActivity is PermissionsActivity && !PermissionsService.shared.allGranted { return }
        
        if state == .idle && isHovering {
            transition(to: .peek)
        } else if state == .peek && !isHovering {
            transition(to: .idle)
        }
    }
    
    public func handleIslandTap() {
        switch state {
        case .idle, .peek:
            if activeActivity != nil {
                transition(to: .expanded)
            } else {
                MediaService.shared.checkActiveMediaOnLaunch()
                if activeActivity != nil {
                    transition(to: .expanded)
                } else {
                    transition(to: .peek)
                }
            }
        case .compact:
            transition(to: .expanded)
        case .expanded:
            if activeActivity is PermissionsActivity && !PermissionsService.shared.allGranted {
                // Keep expanded until user agrees to all permissions
                return
            }
            if activeActivity is HelloSignatureActivity {
                // Keep expanded until user clicks the Continue/Enjoy button
                return
            }
            if activeActivity != nil {
                transition(to: .compact)
            } else {
                transition(to: .idle)
            }
        }
    }
    
    public func switchToSecondary() {
        if let secondary = activityManager.secondaryActivity {
            withAnimation(animationEngine.morphSpring) {
                activityManager.setActiveActivity(id: secondary.id)
                self.activeActivity = secondary
                updateGeometry(animated: true)
            }
        }
    }
    
    public func handleSwipeLeft() {
        withAnimation(animationEngine.morphSpring) {
            activityManager.cycleNext()
            if let newActive = activityManager.activeActivity {
                self.activeActivity = newActive
            }
            updateGeometry(animated: true)
        }
    }
    
    public func handleSwipeRight() {
        withAnimation(animationEngine.morphSpring) {
            activityManager.cyclePrevious()
            if let newActive = activityManager.activeActivity {
                self.activeActivity = newActive
            }
            updateGeometry(animated: true)
        }
    }
    
    public func updateGeometry(animated: Bool = true) {
        let notchSize = displayManager.currentNotchInfo.notchSize
        let target = animationEngine.targetGeometry(
            for: state,
            notchSize: notchSize,
            activity: activeActivity,
            isHovered: isHovered
        )
        
        if animated {
            let isCollapsing = (state == .compact || state == .idle)
            let spring = isCollapsing ? animationEngine.collapseSpring : animationEngine.morphSpring
            withAnimation(spring) {
                self.currentGeometry = target
            }
        } else {
            self.currentGeometry = target
        }
    }
    
    public func triggerHelloSignature(style: HelloAnimationStyle? = nil) {
        let selectedStyle = style ?? HelloSignatureActivity.currentStyle
        let helloAct = HelloSignatureActivity(style: selectedStyle)
        self.activityManager.presentActivity(helloAct)
        self.transition(to: .expanded)
    }
    
    public func triggerPermissionsOnboarding() {
        let permAct = PermissionsActivity()
        self.activityManager.presentActivity(permAct)
        self.transition(to: .expanded)
        DispatchQueue.main.async {
            self.transition(to: .expanded)
        }
    }
}
