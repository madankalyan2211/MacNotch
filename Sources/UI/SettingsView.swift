import SwiftUI
import AppKit

// MARK: - Main Settings View

public struct SettingsView: View {
    @ObservedObject public var controller: DynamicIslandController
    @State private var selectedTab: SettingsTab = .general
    
    public enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case activities = "Activities"
        case privacy = "Privacy"
        case simulator = "Simulator"
        
        public var id: String { rawValue }
        
        public var icon: String {
            switch self {
            case .general: return "gearshape.fill"
            case .activities: return "sparkles.rectangle.stack.fill"
            case .privacy: return "hand.raised.fill"
            case .simulator: return "play.circle.fill"
            }
        }
    }
    
    public init(controller: DynamicIslandController = .shared) {
        self.controller = controller
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header with Segmented Navigation
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let img = NSImage(named: "AppIcon") ?? (Bundle.main.url(forResource: "AppIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .shadow(color: Color.blue.opacity(0.35), radius: 4, y: 1)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.accentColor, Color.purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "macbook")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MacBook Notch")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Dynamic Island Preferences & System Configuration")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                
                // Segmented Tab Picker
                HStack(spacing: 6) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedTab = tab
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                                Text(tab.rawValue)
                                    .font(.system(size: 12.5, weight: selectedTab == tab ? .semibold : .medium))
                            }
                            .foregroundColor(selectedTab == tab ? .white : .primary.opacity(0.75))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                ZStack {
                                    if selectedTab == tab {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.accentColor)
                                            .matchedGeometryEffect(id: "active_settings_tab", in: tabNamespace)
                                            .shadow(color: Color.accentColor.opacity(0.3), radius: 3, x: 0, y: 1)
                                    } else {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.primary.opacity(0.04))
                                    }
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Tab Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsTab(controller: controller)
                    case .activities:
                        ActivitiesSettingsTab(controller: controller)
                    case .privacy:
                        PrivacySettingsTab(controller: controller)
                    case .simulator:
                        DebugSimulatorTab(controller: controller)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 630, height: 570)
        .background(Color(NSColor.underPageBackgroundColor).opacity(0.6))
    }
    
    @Namespace private var tabNamespace
}

// MARK: - Reusable UI Components

public struct SettingsCard<Content: View>: View {
    public let icon: String
    public let iconGradient: [Color]
    public let title: String
    public let subtitle: String?
    public let content: Content
    
    public init(
        icon: String,
        iconGradient: [Color] = [Color.blue, Color.purple],
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.iconGradient = iconGradient
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: iconGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold))
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            
            Divider()
                .opacity(0.6)
            
            // Content
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}

public struct SettingsRow<Trailing: View>: View {
    public let icon: String?
    public let iconColor: Color?
    public let title: String
    public let subtitle: String?
    public let trailing: Trailing
    
    public init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let icon = icon {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill((iconColor ?? Color.accentColor).opacity(0.14))
                        .frame(width: 26, height: 26)
                    
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(iconColor ?? Color.accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Spacer(minLength: 12)
            
            trailing
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tab 1: General Settings

public struct GeneralSettingsTab: View {
    @ObservedObject public var controller: DynamicIslandController
    
    public var body: some View {
        VStack(spacing: 16) {
            // Status & Master Switch
            SettingsCard(
                icon: "bolt.horizontal.fill",
                iconGradient: [Color.blue, Color.cyan],
                title: "Status & Island Control",
                subtitle: "Core Dynamic Island state and auto-collapse timing"
            ) {
                VStack(spacing: 14) {
                    SettingsRow(
                        icon: "power.circle.fill",
                        iconColor: controller.isEnabled ? .green : .gray,
                        title: "Enable Dynamic Island",
                        subtitle: "Activates top notch capsule interactions, live activities and HUDs"
                    ) {
                        Toggle("", isOn: $controller.isEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                    }
                    
                    Divider().opacity(0.5)
                    
                    // Auto-collapse delay slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.orange.opacity(0.14))
                                    .frame(width: 26, height: 26)
                                Image(systemName: "timer")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Collapse Delay")
                                    .font(.system(size: 12.5, weight: .medium))
                                Text("How long expanded cards stay open before smoothly collapsing back")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("\(String(format: "%.1f", controller.autoCollapseDelay))s")
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        
                        HStack(spacing: 12) {
                            Slider(
                                value: $controller.autoCollapseDelay,
                                in: 2.0...15.0,
                                step: 0.5
                            )
                            
                            HStack(spacing: 4) {
                                ForEach([3.0, 6.0, 10.0], id: \.self) { val in
                                    Button("\(Int(val))s") {
                                        controller.autoCollapseDelay = val
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .controlSize(.mini)
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    
                    Divider().opacity(0.5)
                    
                    // Trigger Hello Signature greeting
                    SettingsRow(
                        icon: "sparkles",
                        iconColor: .purple,
                        title: "Signature Apple Greeting",
                        subtitle: "Preview iconic 'hello' animations (Cursive, Neon Aurora, Liquid Glass)"
                    ) {
                        Button("Play Animation") {
                            controller.triggerHelloSignature()
                        }
                        .controlSize(.small)
                    }
                }
            }
            
            // Notch Drop Shelf
            SettingsCard(
                icon: "tray.and.arrow.down.fill",
                iconGradient: [Color.indigo, Color.purple],
                title: "Notch Drop Shelf & Auto-Capture",
                subtitle: "Interactive file shelf embedded directly at the top of your screen"
            ) {
                VStack(spacing: 12) {
                    SettingsRow(
                        icon: "camera.viewfinder",
                        iconColor: .indigo,
                        title: "Auto-Stash Screenshots & Downloads",
                        subtitle: "Instantly captures new screenshots and downloads onto the shelf for quick drag & drop and AirDrop"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { FileShelfService.shared.isAutoCaptureEnabled },
                            set: { FileShelfService.shared.isAutoCaptureEnabled = $0 }
                        ))
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    }
                }
            }
            
            // Display Information
            SettingsCard(
                icon: "display",
                iconGradient: [Color.teal, Color.blue],
                title: "Hardware Notch & Geometry",
                subtitle: "Display detection and hardware camera notch specifications"
            ) {
                let info = controller.displayManager.currentNotchInfo
                VStack(spacing: 10) {
                    HStack {
                        Text("Notch Status")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(info.hasPhysicalNotch ? Color.green : Color.blue)
                                .frame(width: 6, height: 6)
                            Text(info.hasPhysicalNotch ? "Physical Camera Notch Detected" : "Virtual Notch Emulated")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(info.hasPhysicalNotch ? .green : .blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((info.hasPhysicalNotch ? Color.green : Color.blue).opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    Divider().opacity(0.5)
                    
                    HStack {
                        Text("Notch Dimensions")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(Int(info.notchSize.width)) × \(Int(info.notchSize.height)) pt")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Divider().opacity(0.5)
                    
                    HStack {
                        Text("Screen Resolution")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(Int(info.screenFrame.width)) × \(Int(info.screenFrame.height)) pt")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Tab 2: Activities & HUDs Settings

public struct ActivitiesSettingsTab: View {
    @ObservedObject public var controller: DynamicIslandController
    @ObservedObject private var sports = SportsService.shared
    
    public var body: some View {
        VStack(spacing: 16) {
            // System HUD Overlays
            SettingsCard(
                icon: "slider.horizontal.3",
                iconGradient: [Color.blue, Color.indigo],
                title: "Dynamic Island System HUDs",
                subtitle: "Replace standard macOS overlays with smooth top-notch animations"
            ) {
                VStack(spacing: 11) {
                    SettingsRow(
                        icon: "bell.badge.fill",
                        iconColor: .blue,
                        title: "Enable All System HUDs",
                        subtitle: "Master switch for volume, brightness, battery and keyboard HUDs"
                    ) {
                        Toggle("", isOn: $controller.isHUDEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                    }
                    
                    Divider().opacity(0.5)
                    
                    Group {
                        SettingsRow(icon: "speaker.wave.3.fill", iconColor: .blue, title: "Volume HUD", subtitle: "Dynamic notch speaker volume bar") {
                            Toggle("", isOn: $controller.isVolumeHUDEnabled)
                                .toggleStyle(SwitchToggleStyle()).labelsHidden().disabled(!controller.isHUDEnabled)
                        }
                        
                        Divider().opacity(0.3)
                        
                        SettingsRow(icon: "sun.max.fill", iconColor: .yellow, title: "Brightness HUD", subtitle: "Notch brightness slider on function keys") {
                            Toggle("", isOn: $controller.isBrightnessHUDEnabled)
                                .toggleStyle(SwitchToggleStyle()).labelsHidden().disabled(!controller.isHUDEnabled)
                        }
                        
                        Divider().opacity(0.3)
                        
                        SettingsRow(icon: "bolt.batteryblock.fill", iconColor: .green, title: "Battery & MagSafe HUD", subtitle: "Connect animation and low battery warnings") {
                            Toggle("", isOn: $controller.isBatteryHUDEnabled)
                                .toggleStyle(SwitchToggleStyle()).labelsHidden().disabled(!controller.isHUDEnabled)
                        }
                        
                        Divider().opacity(0.3)
                        
                        SettingsRow(icon: "moon.fill", iconColor: .indigo, title: "Focus & Do Not Disturb", subtitle: "Focus mode transition indicator") {
                            Toggle("", isOn: $controller.isFocusModeHUDEnabled)
                                .toggleStyle(SwitchToggleStyle()).labelsHidden().disabled(!controller.isHUDEnabled)
                        }
                        
                        Divider().opacity(0.3)
                        
                        SettingsRow(icon: "capslock.fill", iconColor: .orange, title: "Caps Lock Indicator", subtitle: "Subtle indicator when Caps Lock is toggled") {
                            Toggle("", isOn: $controller.isCapsLockHUDEnabled)
                                .toggleStyle(SwitchToggleStyle()).labelsHidden().disabled(!controller.isHUDEnabled)
                        }
                        
                        Divider().opacity(0.3)
                        
                        SettingsRow(icon: "lock.fill", iconColor: .teal, title: "Screen Lock / Unlock State", subtitle: "Presents lock glyph when waking or locking") {
                            Toggle("", isOn: $controller.isLockHUDEnabled)
                                .toggleStyle(SwitchToggleStyle()).labelsHidden().disabled(!controller.isHUDEnabled)
                        }
                        
                        Divider().opacity(0.3)
                        
                        SettingsRow(icon: "cup.and.saucer.fill", iconColor: .brown, title: "Caffeine (Keep Awake)", subtitle: "Display sleep prevention status in notch") {
                            Toggle("", isOn: $controller.isCaffeineHUDEnabled)
                                .toggleStyle(SwitchToggleStyle()).labelsHidden().disabled(!controller.isHUDEnabled)
                        }
                    }
                    
                    Divider().opacity(0.6)
                    
                    SettingsRow(
                        icon: "xmark.square.fill",
                        iconColor: .red,
                        title: "Hide Stock macOS HUD Overlays",
                        subtitle: "Suppresses macOS default square bezels for volume and display brightness"
                    ) {
                        Toggle("", isOn: $controller.isNativeHUDSuppressionEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                            .onChange(of: controller.isNativeHUDSuppressionEnabled) { enabled in
                                NativeHUDInterceptor.shared.setEnabled(enabled)
                            }
                    }
                }
            }
            
            // Live Activity Modules
            SettingsCard(
                icon: "sparkles",
                iconGradient: [Color.purple, Color.pink],
                title: "Live Activity Modules",
                subtitle: "Persistent interactive tasks running in the compact and expanded notch"
            ) {
                VStack(spacing: 11) {
                    SettingsRow(
                        icon: "music.note",
                        iconColor: .pink,
                        title: "Music & Now Playing",
                        subtitle: "Album artwork, media controls, and audio waveforms for Apple Music, Spotify, YouTube & Netflix"
                    ) {
                        Toggle("", isOn: $controller.isMusicEnabled)
                            .toggleStyle(SwitchToggleStyle()).labelsHidden()
                    }
                    
                    Divider().opacity(0.4)
                    
                    SettingsRow(
                        icon: "timer",
                        iconColor: .orange,
                        title: "Timer & Countdown",
                        subtitle: "Live countdowns and stopwatch timers inside the notch"
                    ) {
                        Toggle("", isOn: $controller.isTimerEnabled)
                            .toggleStyle(SwitchToggleStyle()).labelsHidden()
                    }
                    
                    Divider().opacity(0.4)
                    
                    SettingsRow(
                        icon: "doc.on.clipboard.fill",
                        iconColor: .purple,
                        title: "Smart Clipboard Monitor",
                        subtitle: "Shows copied text snippets and quick actions"
                    ) {
                        Toggle("", isOn: $controller.isClipboardEnabled)
                            .toggleStyle(SwitchToggleStyle()).labelsHidden()
                    }
                    
                    Divider().opacity(0.4)
                    
                    SettingsRow(
                        icon: "cloud.sun.fill",
                        iconColor: .cyan,
                        title: "Ambient Weather & Air Quality",
                        subtitle: "Shows temperature, conditions and live AQI during system idle"
                    ) {
                        Toggle("", isOn: $controller.isWeatherEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                            .onChange(of: controller.isWeatherEnabled) { enabled in
                                if enabled {
                                    let act = WeatherActivity(weather: WeatherService.shared.currentWeather)
                                    controller.activityManager.presentActivity(act)
                                } else {
                                    controller.activityManager.removeActivity(id: "activity.weather")
                                }
                            }
                    }
                    
                    Divider().opacity(0.4)
                    
                    SettingsRow(
                        icon: "soccerball",
                        iconColor: .green,
                        title: "Live Sports Ticker",
                        subtitle: "Pins live scores and match clocks for Premier League, NBA, F1, and Cricket"
                    ) {
                        Toggle("", isOn: $controller.isSportsEnabled)
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                            .onChange(of: controller.isSportsEnabled) { enabled in
                                if !enabled {
                                    SportsService.shared.dismissMatch()
                                } else if let match = SportsService.shared.activeMatch {
                                    SportsService.shared.pinMatch(match)
                                }
                            }
                    }
                }
            }
            
            // Live Sports Scoreboard & Match Selector Card
            SettingsCard(
                icon: "sportscourt.fill",
                iconGradient: [Color.green, Color.orange],
                title: "Live Sports & Favorite Teams",
                subtitle: "Real-time scores, team crests, and matchday tracking for Soccer, NBA, F1, and Cricket"
            ) {
                VStack(spacing: 14) {
                    // Real-Time Live Feed Status Bar
                    HStack(spacing: 8) {
                        Circle()
                            .fill(sports.isLiveFeedConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        
                        Text(sports.isLiveFeedConnected ? "ESPN Live Sports Feed" : "Connecting to ESPN...")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(sports.isLiveFeedConnected ? .green : .orange)
                        
                        if let last = sports.lastUpdated {
                            Text("• \(last.formatted(date: .omitted, time: .standard))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            sports.fetchLiveScores()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                    .rotationEffect(.degrees(sports.isFetching ? 360 : 0))
                                    .animation(sports.isFetching ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: sports.isFetching)
                                Text(sports.isFetching ? "Syncing..." : "Refresh Scores")
                                    .font(.system(size: 10.5, weight: .medium))
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    // Matchday Auto-Pin Toggle
                    SettingsRow(
                        icon: "calendar.badge.clock",
                        iconColor: .green,
                        title: "Auto-Show on Matchday",
                        subtitle: "Automatically surfaces upcoming scheduled and in-game matches for your favorite teams"
                    ) {
                        Toggle("", isOn: $sports.autoShowMatchday)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    }
                    
                    Divider().opacity(0.4)
                    
                    // Only Show Favorite Teams Toggle
                    SettingsRow(
                        icon: "star.fill",
                        iconColor: .yellow,
                        title: "Only Show Favorite Teams",
                        subtitle: "Limits Dynamic Island strictly to matches featuring your selected favorite teams"
                    ) {
                        Toggle("", isOn: $sports.onlyShowFavorites)
                        .toggleStyle(SwitchToggleStyle())
                        .labelsHidden()
                    }
                    
                    Divider().opacity(0.4)
                    
                    // Enabled Sports Selector
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Select Sports to Show:")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("Click to toggle in Island")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 8) {
                            // Football
                            SportToggleChip(
                                title: "Football",
                                icon: "soccerball",
                                iconColor: Color.accentColor,
                                isEnabled: $sports.isFootballEnabled
                            )
                            
                            // Basketball
                            SportToggleChip(
                                title: "Basketball",
                                icon: "basketball.fill",
                                iconColor: .orange,
                                isEnabled: $sports.isBasketballEnabled
                            )
                            
                            // F1
                            SportToggleChip(
                                title: "Formula 1",
                                icon: "flag.checkered",
                                iconColor: .red,
                                isEnabled: $sports.isF1Enabled
                            )
                            
                            // Cricket
                            SportToggleChip(
                                title: "Cricket",
                                icon: "cricket.ball.fill",
                                iconColor: .cyan,
                                isEnabled: $sports.isCricketEnabled
                            )
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    Divider().opacity(0.4)
                    
                    // Favorite Teams Pickers
                    VStack(spacing: 9) {
                        HStack {
                            Text("Your Favorite Teams:")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                        }
                        
                        // Football
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "soccerball")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentColor)
                                Text("Football:")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Picker("", selection: $sports.favoriteFootball) {
                                ForEach(SportsService.footballTeams, id: \.name) { team in
                                    Text(team.name).tag(team.name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        .disabled(!sports.isFootballEnabled)
                        .opacity(sports.isFootballEnabled ? 1.0 : 0.4)
                        
                        // Basketball
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "basketball.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                Text("Basketball (NBA):")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Picker("", selection: $sports.favoriteBasketball) {
                                ForEach(SportsService.basketballTeams, id: \.name) { team in
                                    Text(team.name).tag(team.name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        .disabled(!sports.isBasketballEnabled)
                        .opacity(sports.isBasketballEnabled ? 1.0 : 0.4)
                        
                        // Formula 1
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                                Text("Formula 1:")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Picker("", selection: $sports.favoriteF1) {
                                ForEach(SportsService.f1Teams, id: \.name) { team in
                                    Text(team.name).tag(team.name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        .disabled(!sports.isF1Enabled)
                        .opacity(sports.isF1Enabled ? 1.0 : 0.4)
                        
                        // Cricket
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "cricket.ball.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.cyan)
                                Text("Cricket:")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Spacer()
                            Picker("", selection: $sports.favoriteCricket) {
                                ForEach(SportsService.cricketTeams, id: \.name) { team in
                                    Text(team.name).tag(team.name)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 170)
                        }
                        .disabled(!sports.isCricketEnabled)
                        .opacity(sports.isCricketEnabled ? 1.0 : 0.4)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    Divider().opacity(0.4)
                    
                    // Match Selection & Active Fixture Status
                    HStack {
                        Text("Active Fixture:")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        if let match = sports.activeMatch {
                            HStack(spacing: 4) {
                                if match.isScheduled {
                                    Text("\(match.team1.abbreviation) vs \(match.team2.abbreviation) (\(match.scheduledTime))")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.cyan)
                                } else {
                                    Text("\(match.team1.abbreviation) \(match.team1.score) - \(match.team2.score) \(match.team2.abbreviation) (\(match.periodText))")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((match.isScheduled ? Color.cyan : Color.green).opacity(0.12))
                            .clipShape(Capsule())
                        } else {
                            Text("None active")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if sports.availableMatches.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                            Text("All sports are disabled or no matches available today.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(sports.availableMatches, id: \.id) { match in
                                    Button(action: {
                                        sports.pinMatch(match)
                                    }) {
                                        HStack(spacing: 5) {
                                            if sports.isMatchFavorite(match) {
                                                Image(systemName: "star.fill")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.yellow)
                                            }
                                            
                                            Image(systemName: match.sport.icon)
                                                .font(.system(size: 10))
                                            
                                            Text("\(match.team1.abbreviation) \(match.isScheduled ? "vs" : match.team1.score + "-" + match.team2.score) \(match.team2.abbreviation)")
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            
                                            if match.isScheduled {
                                                Text("⏰")
                                                    .font(.system(size: 9))
                                            } else {
                                                Text("🔴")
                                                    .font(.system(size: 7))
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(sports.activeMatch?.id == match.id ? Color.accentColor : Color.primary.opacity(0.06))
                                        .foregroundColor(sports.activeMatch?.id == match.id ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    
                    Divider().opacity(0.4)
                    
                    HStack {
                        Button(action: {
                            sports.fetchLiveScores()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.accentColor)
                                Text("Refresh Live Feeds")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .controlSize(.small)
                        
                        Spacer()
                        
                        Button(action: {
                            sports.dismissMatch()
                        }) {
                            Text("Unpin Match")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.red)
                        }
                        .controlSize(.small)
                    }
                }
            }
            
            // Audio Reactive Visualizer
            SettingsCard(
                icon: "waveform.path.ecg",
                iconGradient: [Color.green, Color.teal],
                title: "Audio Reactive Waves",
                subtitle: "Hardware notch real-time audio visualization across all system audio"
            ) {
                VStack(spacing: 12) {
                    SettingsRow(
                        icon: "waveform",
                        iconColor: .green,
                        title: "Enable Reactive Waves",
                        subtitle: "Renders real-time audio waves directly on the notch borders"
                    ) {
                        Toggle("", isOn: Binding(
                            get: { AudioVisualizerService.shared.isEnabled },
                            set: { AudioVisualizerService.shared.isEnabled = $0 }
                        ))
                        .toggleStyle(SwitchToggleStyle()).labelsHidden()
                    }
                    
                    Divider().opacity(0.4)
                    
                    SettingsRow(
                        icon: "paintbrush.fill",
                        iconColor: .cyan,
                        title: "Visualizer Style",
                        subtitle: "Wave animation geometry along the notch contours"
                    ) {
                        Picker("", selection: Binding(
                            get: { AudioVisualizerService.shared.currentStyle },
                            set: { AudioVisualizerService.shared.currentStyle = $0 }
                        )) {
                            ForEach(VisualizerStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .disabled(!AudioVisualizerService.shared.isEnabled)
                    }
                    
                    Divider().opacity(0.4)
                    
                    SettingsRow(
                        icon: "paintpalette.fill",
                        iconColor: .pink,
                        title: "Color Theme",
                        subtitle: "Vibrant neon color gradients for audio frequencies"
                    ) {
                        Picker("", selection: Binding(
                            get: { AudioVisualizerService.shared.currentTheme },
                            set: { AudioVisualizerService.shared.currentTheme = $0 }
                        )) {
                            ForEach(VisualizerTheme.allCases) { theme in
                                Text(theme.rawValue).tag(theme)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .disabled(!AudioVisualizerService.shared.isEnabled)
                    }
                }
            }
        }
    }
}

// MARK: - Tab 3: Privacy Settings

public struct PrivacySettingsTab: View {
    @ObservedObject public var controller: DynamicIslandController
    @ObservedObject private var permissions = PermissionsService.shared
    
    public var body: some View {
        VStack(spacing: 16) {
            // Privacy Guarantee Banner
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.square.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("100% Local & Private")
                            .font(.system(size: 13.5, weight: .bold))
                        Text("MacBook Notch runs exclusively on-device. No telemetry, analytics, or recordings leave your Mac.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )
            
            // Permissions Card
            SettingsCard(
                icon: "shield.lefthalf.filled",
                iconGradient: [Color.blue, Color.purple],
                title: "macOS System Permissions",
                subtitle: "\(permissions.grantedCount) of \(permissions.totalCount) permissions configured"
            ) {
                VStack(spacing: 12) {
                    // Quick Action to trigger in Notch
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Interactive Notch Permissions Setup")
                                .font(.system(size: 12.5, weight: .semibold))
                            Text("Presents the interactive card directly inside the expanded MacBook Notch")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Open in Notch") {
                            controller.triggerPermissionsOnboarding()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Divider().opacity(0.5)
                    
                    // 1. Accessibility
                    PermissionStatusRow(
                        title: "Accessibility",
                        subtitle: "Required for notch mouse gestures and stock HUD bezel suppression",
                        isGranted: permissions.isAccessibilityGranted
                    ) {
                        permissions.agreeAccessibility()
                    }
                    
                    Divider().opacity(0.3)
                    
                    // 2. Media Automation
                    PermissionStatusRow(
                        title: "Media Automation",
                        subtitle: "Playback controls and track info for Apple Music, Spotify and browsers",
                        isGranted: permissions.isAutomationGranted
                    ) {
                        permissions.agreeAutomation()
                    }
                    
                    Divider().opacity(0.3)
                    
                    // 3. Location Services
                    PermissionStatusRow(
                        title: "Location Services",
                        subtitle: "Local weather and live air quality monitoring",
                        isGranted: permissions.isLocationGranted
                    ) {
                        permissions.agreeLocation()
                    }
                    
                    Divider().opacity(0.3)
                    
                    // 4. Bluetooth Devices
                    PermissionStatusRow(
                        title: "Bluetooth & AirPods",
                        subtitle: "Battery status for connected headphones and wireless gear",
                        isGranted: permissions.isBluetoothGranted
                    ) {
                        permissions.agreeBluetooth()
                    }
                }
            }
        }
        .onAppear {
            permissions.checkAllPermissions()
        }
    }
}

public struct PermissionStatusRow: View {
    public let title: String
    public let subtitle: String
    public let isGranted: Bool
    public let onAction: () -> Void
    
    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isGranted ? .green : .orange)
                .font(.system(size: 15))
            
            VStack(alignment: .leading, spacing: 1.5) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Text("Allowed")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Button("Allow") {
                    onAction()
                }
                .controlSize(.small)
            }
        }
    }
}

public struct SportToggleChip: View {
    public let title: String
    public let icon: String
    public let iconColor: Color
    @Binding public var isEnabled: Bool
    
    public var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isEnabled.toggle()
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5))
                    .foregroundColor(isEnabled ? iconColor : .secondary)
                Text(title)
                    .font(.system(size: 11, weight: isEnabled ? .semibold : .medium))
                Image(systemName: isEnabled ? "checkmark" : "plus")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isEnabled ? iconColor : .secondary.opacity(0.5))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isEnabled ? iconColor.opacity(0.12) : Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isEnabled ? iconColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundColor(isEnabled ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 4: Simulator Tab

public struct DebugSimulatorTab: View {
    @ObservedObject public var controller: DynamicIslandController
    
    public var body: some View {
        DebugControlView(controller: controller)
    }
}
