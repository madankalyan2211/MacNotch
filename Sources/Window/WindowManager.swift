import AppKit
import SwiftUI
import Combine

@MainActor
public final class WindowManager: ObservableObject {
    public static let shared = WindowManager()
    
    private var window: DynamicIslandWindow?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    
    private let controller = DynamicIslandController.shared
    
    private init() {
        setupStatusItem()
        setupWindow()
        setupObservers()
        setupMouseTracking()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "capsule.portrait.fill", accessibilityDescription: "Dynamic Island")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        // Keep Awake (Caffeine) Submenu with customizable duration limits
        let caffeineMenu = NSMenu()
        
        let indefiniteItem = NSMenuItem(title: "Keep Awake Indefinitely", action: #selector(caffeineIndefiniteAction), keyEquivalent: "")
        indefiniteItem.target = self
        caffeineMenu.addItem(indefiniteItem)
        
        let m15Item = NSMenuItem(title: "For 15 Minutes", action: #selector(caffeine15mAction), keyEquivalent: "")
        m15Item.target = self
        caffeineMenu.addItem(m15Item)
        
        let m30Item = NSMenuItem(title: "For 30 Minutes", action: #selector(caffeine30mAction), keyEquivalent: "")
        m30Item.target = self
        caffeineMenu.addItem(m30Item)
        
        let h1Item = NSMenuItem(title: "For 1 Hour", action: #selector(caffeine1hAction), keyEquivalent: "")
        h1Item.target = self
        caffeineMenu.addItem(h1Item)
        
        let h2Item = NSMenuItem(title: "For 2 Hours", action: #selector(caffeine2hAction), keyEquivalent: "")
        h2Item.target = self
        caffeineMenu.addItem(h2Item)
        
        let h5Item = NSMenuItem(title: "For 5 Hours", action: #selector(caffeine5hAction), keyEquivalent: "")
        h5Item.target = self
        caffeineMenu.addItem(h5Item)
        
        caffeineMenu.addItem(NSMenuItem.separator())
        
        let offItem = NSMenuItem(title: "Turn Off (Allow Sleep)", action: #selector(caffeineOffAction), keyEquivalent: "")
        offItem.target = self
        caffeineMenu.addItem(offItem)
        
        let caffeineParentItem = NSMenuItem(title: "☕️ Keep Awake (Caffeine)", action: nil, keyEquivalent: "")
        caffeineParentItem.submenu = caffeineMenu
        menu.addItem(caffeineParentItem)
        
        let weatherItem = NSMenuItem(title: "🌤️ Show Ambient Weather (Idle)", action: #selector(toggleWeatherAction), keyEquivalent: "")
        weatherItem.target = self
        weatherItem.state = controller.isWeatherEnabled ? .on : .off
        menu.addItem(weatherItem)
        
        let fileCount = FileShelfService.shared.files.count
        let shelfTitle = fileCount > 0 ? "📁 Notch Shelf (\(fileCount) \(fileCount == 1 ? "File" : "Files"))" : "📁 Notch Shelf"
        let shelfItem = NSMenuItem(title: shelfTitle, action: #selector(openShelfAction), keyEquivalent: "s")
        shelfItem.keyEquivalentModifierMask = [.option]
        shelfItem.target = self
        menu.addItem(shelfItem)
        
        // WhatsApp messaging disabled
        // let waItem = NSMenuItem(title: "💬 Test WhatsApp Message", action: #selector(simulateWhatsAppAction), keyEquivalent: "w")
        // waItem.keyEquivalentModifierMask = [.option]
        // waItem.target = self
        // menu.addItem(waItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitAppAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        
        // Global hotkey monitor: Option+S (S=1), Option+W (W=13), Option+D (D=2), Option+A (A=0), Option+C (C=8), Option+R (R=15), Option+H (H=4)
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.option) {
                if event.keyCode == 1 { // Option+S
                    DispatchQueue.main.async {
                        self?.openShelfAction()
                    }
                } else if event.keyCode == 13 { // Option+W (WhatsApp disabled)
                    // DispatchQueue.main.async { self?.simulateWhatsAppAction() }
                } else if event.keyCode == 4 { // Option+H
                    DispatchQueue.main.async {
                        self?.playHelloAction()
                    }
                } else if event.keyCode == 2 { // Option+D
                    DispatchQueue.main.async {
                        FocusModeService.shared.toggleFocusMode()
                    }
                } else if event.keyCode == 0 { // Option+A
                    DispatchQueue.main.async {
                        self?.connectAirPodsAction()
                    }
                } else if event.keyCode == 8 { // Option+C
                    DispatchQueue.main.async {
                        self?.toggleCallAction()
                    }
                } else if event.keyCode == 15 { // Option+R
                    DispatchQueue.main.async {
                        self?.toggleVoiceMemoAction()
                    }
                } else if event.keyCode == 126 { // Up Arrow
                    DispatchQueue.main.async {
                        if event.modifierFlags.contains(.shift) {
                            let curr = SystemHUDService.shared.getCurrentBrightness()
                            SystemHUDService.shared.setBrightness(level: min(1.0, curr + 0.0625))
                        } else {
                            let curr = SystemHUDService.shared.getCurrentVolume()
                            SystemHUDService.shared.setVolume(level: min(1.0, curr + 0.0625))
                        }
                    }
                } else if event.keyCode == 125 { // Down Arrow
                    DispatchQueue.main.async {
                        if event.modifierFlags.contains(.shift) {
                            let curr = SystemHUDService.shared.getCurrentBrightness()
                            SystemHUDService.shared.setBrightness(level: max(0.0, curr - 0.0625))
                        } else {
                            let curr = SystemHUDService.shared.getCurrentVolume()
                            SystemHUDService.shared.setVolume(level: max(0.0, curr - 0.0625))
                        }
                    }
                }
            }
        }
        
        // Global click-outside monitor (dismisses expanded island when clicking outside)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let mouseLoc = NSEvent.mouseLocation
            
            if self.controller.state == .expanded {
                // NEVER dismiss when displaying signature hello or pending permissions onboarding
                if self.controller.activeActivity is HelloSignatureActivity {
                    return
                }
                if self.controller.activeActivity is PermissionsActivity && !PermissionsService.shared.allGranted {
                    return
                }
                
                let winFrame = self.window?.frame ?? .zero
                let geometry = self.controller.currentGeometry
                let mainWidth = max(geometry.width, 160)
                let islandHeight = max(geometry.height, 30.5)
                let islandX = winFrame.midX - (mainWidth / 2.0)
                let islandY = winFrame.maxY - islandHeight
                let expandedRect = NSRect(x: islandX - 6, y: islandY - 6, width: mainWidth + 12, height: islandHeight + 12)
                
                if !expandedRect.contains(mouseLoc) {
                    DispatchQueue.main.async {
                        self.controller.handleIslandTap()
                    }
                }
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape key
                if let controller = self?.controller, controller.state == .expanded {
                    // Do not close with Escape when viewing signature hello or pending permissions
                    if controller.activeActivity is HelloSignatureActivity {
                        return event
                    }
                    if controller.activeActivity is PermissionsActivity && !PermissionsService.shared.allGranted {
                        return event
                    }
                    DispatchQueue.main.async {
                        controller.handleIslandTap()
                    }
                    return nil
                }
            }
            if event.modifierFlags.contains(.option) {
                if event.keyCode == 4 { // Option+H
                    DispatchQueue.main.async {
                        self?.playHelloAction()
                    }
                    return nil
                } else if event.keyCode == 2 { // Option+D
                    DispatchQueue.main.async {
                        FocusModeService.shared.toggleFocusMode()
                    }
                    return nil
                } else if event.keyCode == 0 { // Option+A
                    DispatchQueue.main.async {
                        self?.connectAirPodsAction()
                    }
                    return nil
                } else if event.keyCode == 46 { // Option+M
                    DispatchQueue.main.async {
                        self?.connectMouseAction()
                    }
                    return nil
                } else if event.keyCode == 8 { // Option+C
                    DispatchQueue.main.async {
                        self?.toggleCallAction()
                    }
                    return nil
                } else if event.keyCode == 15 { // Option+R
                    DispatchQueue.main.async {
                        self?.toggleVoiceMemoAction()
                    }
                    return nil
                } else if event.keyCode == 126 { // Up Arrow
                    DispatchQueue.main.async {
                        if event.modifierFlags.contains(.shift) {
                            let curr = SystemHUDService.shared.getCurrentBrightness()
                            SystemHUDService.shared.setBrightness(level: min(1.0, curr + 0.0625))
                        } else {
                            let curr = SystemHUDService.shared.getCurrentVolume()
                            SystemHUDService.shared.setVolume(level: min(1.0, curr + 0.0625))
                        }
                    }
                    return nil
                } else if event.keyCode == 125 { // Down Arrow
                    DispatchQueue.main.async {
                        if event.modifierFlags.contains(.shift) {
                            let curr = SystemHUDService.shared.getCurrentBrightness()
                            SystemHUDService.shared.setBrightness(level: max(0.0, curr - 0.0625))
                        } else {
                            let curr = SystemHUDService.shared.getCurrentVolume()
                            SystemHUDService.shared.setVolume(level: max(0.0, curr - 0.0625))
                        }
                    }
                    return nil
                }
            }
            return event
        }
    }
    
    @objc private func playHelloAction() {
        controller.triggerHelloSignature()
    }
    
    @objc private func openShelfAction() {
        let shelfAct = FileShelfActivity()
        controller.activityManager.presentActivity(shelfAct)
        controller.transition(to: .compact)
    }
    
    @objc private func simulateWhatsAppAction() {
        // WhatsApp messaging disabled
        // WhatsAppNotificationService.shared.simulateIncomingMessage()
    }
    
    @objc private func toggleVoiceMemoAction() {
        VoiceMemoService.shared.toggleRecording()
    }
    
    @objc private func toggleCallAction() {
        CallMonitorService.shared.toggleSimulatedCall()
    }
    
    @objc private func connectAirPodsAction() {
        BluetoothService.shared.simulateAirPodsConnection()
    }
    
    @objc private func connectMouseAction() {
        BluetoothService.shared.simulateMouseConnection()
    }
    
    @objc private func toggleIslandAction() {
        controller.handleIslandTap()
    }
    
    @objc private func toggleDNDAction() {
        FocusModeService.shared.toggleFocusMode()
    }
    
    @objc private func toggleCapsLockAction() {
        CapsLockService.shared.simulateToggle()
    }
    
    @objc private func toggleLockAction() {
        LockStateService.shared.triggerManualState(isLocked: false)
    }
    
    @objc private func toggleCaffeineAction() {
        CaffeineService.shared.toggle()
    }
    
    @objc private func caffeineIndefiniteAction() {
        CaffeineService.shared.activate(duration: nil)
    }
    
    @objc private func caffeine15mAction() {
        CaffeineService.shared.activate(duration: 15 * 60)
    }
    
    @objc private func caffeine30mAction() {
        CaffeineService.shared.activate(duration: 30 * 60)
    }
    
    @objc private func caffeine1hAction() {
        CaffeineService.shared.activate(duration: 60 * 60)
    }
    
    @objc private func caffeine2hAction() {
        CaffeineService.shared.activate(duration: 120 * 60)
    }
    
    @objc private func caffeine5hAction() {
        CaffeineService.shared.activate(duration: 300 * 60)
    }
    
    @objc private func caffeineOffAction() {
        CaffeineService.shared.deactivate()
    }
    
    @objc private func toggleWeatherAction() {
        controller.isWeatherEnabled.toggle()
        if !controller.isWeatherEnabled {
            controller.activityManager.removeActivity(id: "activity.weather")
            if controller.state != .idle {
                controller.transition(to: .idle)
            }
        } else {
            controller.scheduleAmbientWeatherPresentation(delay: 180.0)
        }
        setupStatusItem()
    }
    
    @objc private func testLowBatteryAction() {
        BatteryService.shared.simulateBattery(percentage: 15, isCharging: false)
    }
    
    @objc private func start5mTimerAction() {
        TimerService.shared.startTimer(duration: 300, label: "Tea Timer")
    }
    
    @objc private func start1mTimerAction() {
        TimerService.shared.startTimer(duration: 60, label: "Quick Timer")
    }
    
    @objc private func quitAppAction() {
        NSApplication.shared.terminate(nil)
    }
    
    private func setupWindow() {
        let notchInfo = controller.displayManager.currentNotchInfo
        let screenFrame = notchInfo.screenFrame
        
        let windowWidth: CGFloat = 680
        let windowHeight: CGFloat = 380
        let windowX = screenFrame.midX - (windowWidth / 2.0)
        let windowY = screenFrame.maxY - windowHeight
        
        let contentRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        let islandWindow = DynamicIslandWindow(contentRect: contentRect)
        
        let islandView = IslandView(controller: controller)
        let hostingView = DynamicIslandHostingView(rootView: islandView)
        
        islandWindow.contentView = hostingView
        islandWindow.orderFrontRegardless()
        
        self.window = islandWindow
    }
    
    private func setupMouseTracking() {
        // Global mouse movement monitor
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.updateMouseInteraction()
        }
        
        // Local mouse movement monitor
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.updateMouseInteraction()
            return event
        }
        
        updateMouseInteraction()
    }
    
    public func updateMouseInteraction(at mouseLocation: NSPoint? = nil) {
        guard let window = window else { return }
        let mouseLoc = mouseLocation ?? NSEvent.mouseLocation
        
        let geometry = controller.currentGeometry
        let winFrame = window.frame
        
        let mainWidth = max(geometry.width, 160)
        let hasSecondary = (controller.state == .compact && controller.activityManager.secondaryActivity != nil)
        let bubbleRightExtent: CGFloat = hasSecondary ? (geometry.height + 24.0) : 0
        let islandHeight = max(geometry.height, 30.5)
        
        let islandMinX = winFrame.midX - (mainWidth / 2.0)
        let islandMaxX = winFrame.midX + (mainWidth / 2.0) + bubbleRightExtent
        let islandY = winFrame.maxY - islandHeight
        
        let isIdle = (controller.state == .idle)
        let cushion: CGFloat = isIdle ? 0.0 : 2.0
        let activeRect = NSRect(
            x: islandMinX - cushion,
            y: islandY - cushion,
            width: (islandMaxX - islandMinX) + (cushion * 2),
            height: islandHeight + (cushion * 2)
        )
        
        let isInside = activeRect.contains(mouseLoc)
        
        if isInside {
            if window.ignoresMouseEvents {
                window.ignoresMouseEvents = false
            }
            if !controller.isHovered && controller.state == .idle {
                controller.handleHover(isHovering: true)
            }
        } else {
            if !window.ignoresMouseEvents {
                window.ignoresMouseEvents = true
            }
            if controller.isHovered && controller.state == .peek {
                controller.handleHover(isHovering: false)
            }
        }
    }
    
    private func setupObservers() {
        // Observe display changes to re-center window canvas if screen resolution/monitor changes
        controller.displayManager.$currentNotchInfo
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.repositionWindow()
                self?.updateMouseInteraction()
            }
            .store(in: &cancellables)
            
        // Observe geometry & state updates to dynamically adjust mouse interaction bounds
        controller.$currentGeometry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMouseInteraction()
            }
            .store(in: &cancellables)
    }
    
    public func repositionWindow() {
        guard let window = window else { return }
        let notchInfo = controller.displayManager.currentNotchInfo
        let screenFrame = notchInfo.screenFrame
        
        let windowWidth: CGFloat = 680
        let windowHeight: CGFloat = 380
        let notchCenterX = notchInfo.hasPhysicalNotch ? (notchInfo.notchOrigin.x + (notchInfo.notchSize.width / 2.0)) : screenFrame.midX
        let windowX = notchCenterX - (windowWidth / 2.0)
        let windowY = screenFrame.maxY - windowHeight
        
        let targetFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true, animate: false)
        }
    }
    
    @objc public func openSettingsAction() {
        if settingsWindow == nil {
            let settingsView = SettingsView(controller: controller)
            let hosting = NSHostingView(rootView: settingsView)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 630, height: 570),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "Dynamic Island Settings"
            win.contentView = hosting
            win.isReleasedWhenClosed = false
            self.settingsWindow = win
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
