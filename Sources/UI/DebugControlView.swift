import SwiftUI

/// Debug Simulator: Interactive motion design testing panel.
public struct DebugControlView: View {
    @ObservedObject public var controller: DynamicIslandController
    @ObservedObject private var animConfig = IslandAnimationConfiguration.shared
    
    public init(controller: DynamicIslandController) {
        self.controller = controller
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Motion Speed Multiplier (Slow-Mo debugging)
            SettingsCard(
                icon: "hare.fill",
                iconGradient: [Color.orange, Color.red],
                title: "Animation & Motion Speed",
                subtitle: "Slow down motion physics to inspect fluid spring transitions"
            ) {
                VStack(spacing: 12) {
                    HStack {
                        Text("Current Speed Multiplier:")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text("\(String(format: "%.2fx", animConfig.speedMultiplier))")
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 8) {
                        speedButton(label: "0.25x Slow-Mo", value: 0.25)
                        speedButton(label: "0.5x Half", value: 0.5)
                        speedButton(label: "1.0x Normal", value: 1.0)
                        speedButton(label: "2.0x Fast", value: 2.0)
                    }
                }
            }
            
            // Spring Physics Tuning
            SettingsCard(
                icon: "waveform.path",
                iconGradient: [Color.purple, Color.blue],
                title: "Spring Physics Engine Tuning",
                subtitle: "Adjust response curves and damping ratios in real-time"
            ) {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Expansion Response Time")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(String(format: "%.2f", animConfig.expansionResponse))s")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $animConfig.expansionResponse, in: 0.15...0.70, step: 0.01)
                    }
                    
                    Divider().opacity(0.4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Expansion Damping Ratio")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(String(format: "%.2f", animConfig.expansionDamping))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $animConfig.expansionDamping, in: 0.40...1.0, step: 0.02)
                    }
                }
            }
            
            // Manual State Transitions
            SettingsCard(
                icon: "arrow.triangle.swap",
                iconGradient: [Color.cyan, Color.blue],
                title: "Direct State Transitions",
                subtitle: "Force Dynamic Island into specific geometry states"
            ) {
                HStack(spacing: 8) {
                    stateButton(title: "Idle", icon: "capsule") { controller.transition(to: .idle) }
                    stateButton(title: "Peek", icon: "eye.fill") { controller.transition(to: .peek) }
                    stateButton(title: "Compact", icon: "arrow.right.and.line.vertical.and.arrow.left") { controller.transition(to: .compact) }
                    stateButton(title: "Expanded", icon: "arrow.up.left.and.arrow.down.right") { controller.transition(to: .expanded) }
                }
            }
            
            // Interactive Activities Simulation
            SettingsCard(
                icon: "sparkles.rectangle.stack.fill",
                iconGradient: [Color.pink, Color.purple],
                title: "Live Activity Simulation",
                subtitle: "Trigger sample live activities into the notch pipeline"
            ) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    simButton(title: "Now Playing", icon: "music.note", color: .pink) {
                        let music = MusicActivity(title: "Blinding Lights", artist: "The Weeknd", isPlaying: true)
                        controller.activityManager.presentActivity(music)
                    }
                    
                    simButton(title: "Timer (5:00)", icon: "timer", color: .orange) {
                        TimerService.shared.startTimer(duration: 300, label: "Tea Timer")
                    }
                    
                    simButton(title: "Clipboard Copy", icon: "doc.on.clipboard.fill", color: .purple) {
                        ClipboardService.shared.simulateCopy(text: "https://apple.com/macbook-pro")
                    }
                    
                    simButton(title: "Volume 80%", icon: "speaker.wave.3.fill", color: .blue) {
                        SystemHUDService.shared.triggerVolumeHUD(level: 0.80)
                    }
                    
                    simButton(title: "Brightness 75%", icon: "sun.max.fill", color: .yellow) {
                        SystemHUDService.shared.triggerBrightnessHUD(level: 0.75)
                    }
                    
                    simButton(title: "MagSafe Connected", icon: "bolt.batteryblock.fill", color: .green) {
                        BatteryService.shared.simulateBattery(percentage: 95, isCharging: true)
                    }
                    
                    simButton(title: "Low Battery 15%", icon: "battery.25", color: .orange) {
                        BatteryService.shared.simulateBattery(percentage: 15, isCharging: false)
                    }
                    
                    simButton(title: "Caps Lock Toggle", icon: "capslock.fill", color: .teal) {
                        CapsLockService.shared.simulateToggle()
                    }
                    
                    simButton(title: "Screen Locked", icon: "lock.fill", color: .gray) {
                        LockStateService.shared.triggerManualState(isLocked: true)
                    }
                    
                    simButton(title: "Toggle Caffeine", icon: "cup.and.saucer.fill", color: .brown) {
                        CaffeineService.shared.toggle()
                    }
                    
                    simButton(title: "Live Weather (1 Min)", icon: "cloud.sun.fill", color: .cyan) {
                        let weatherAct = WeatherActivity(weather: WeatherService.shared.currentWeather)
                        controller.activityManager.presentActivity(weatherAct)
                        if controller.state == .idle || controller.state == .peek {
                            controller.transition(to: .compact)
                        }
                    }
                    
                    simButton(title: "⚽️ Premier League", icon: "soccerball", color: .red) {
                        if let match = SportsService.shared.availableMatches.first(where: { $0.sport == .football }) {
                            SportsService.shared.pinMatch(match)
                        }
                    }
                    
                    simButton(title: "🏀 NBA (LAL vs GSW)", icon: "basketball.fill", color: .orange) {
                        if let match = SportsService.shared.availableMatches.first(where: { $0.sport == .basketball }) {
                            SportsService.shared.pinMatch(match)
                        }
                    }
                    
                    simButton(title: "🏎️ F1 Monaco GP", icon: "flag.checkered", color: .blue) {
                        if let match = SportsService.shared.availableMatches.first(where: { $0.sport == .formula1 }) {
                            SportsService.shared.pinMatch(match)
                        }
                    }
                    
                    simButton(title: "🏏 Cricket (IND vs AUS)", icon: "cricket.ball.fill", color: .green) {
                        if let match = SportsService.shared.availableMatches.first(where: { $0.sport == .cricket }) {
                            SportsService.shared.pinMatch(match)
                        }
                    }
                    
                    simButton(title: "⚡️ Simulate Goal / Score", icon: "bolt.fill", color: .yellow) {
                        SportsService.shared.simulateScoreEvent()
                    }
                    
                    simButton(title: "⏰ Scheduled (Today 8 PM)", icon: "clock.fill", color: .cyan) {
                        if let scheduled = SportsService.shared.availableMatches.first(where: { $0.isScheduled }) {
                            SportsService.shared.pinMatch(scheduled)
                        }
                    }
                    
                    simButton(title: "🔴 Live (Your Fav Team)", icon: "play.circle.fill", color: .red) {
                        if let live = SportsService.shared.availableMatches.first(where: { $0.isLive }) {
                            SportsService.shared.pinMatch(live)
                        }
                    }
                    
                    simButton(title: "✍️ Hello (Cursive)", icon: "pencil.tip", color: .pink) {
                        controller.triggerHelloSignature(style: .classicCursive)
                    }
                    
                    simButton(title: "⚡️ Hello (Neon Aurora)", icon: "sparkles", color: .cyan) {
                        controller.triggerHelloSignature(style: .neonAurora)
                    }
                    
                    simButton(title: "💎 Hello (Liquid Glass)", icon: "cube.transparent", color: .purple) {
                        controller.triggerHelloSignature(style: .liquidGlass)
                    }
                    
                    simButton(title: "🛡️ Permissions Setup", icon: "shield.lefthalf.filled", color: .blue) {
                        controller.triggerPermissionsOnboarding()
                    }
                }
            }
            
            // Motion Transition Sequences & Stress Test
            SettingsCard(
                icon: "bolt.badge.clock.fill",
                iconGradient: [Color.indigo, Color.purple],
                title: "Stress & Interruption Tests",
                subtitle: "Simulate concurrent activities and rapid state switching"
            ) {
                VStack(spacing: 8) {
                    Button(action: {
                        let music = MusicActivity(title: "Starboy", artist: "The Weeknd")
                        controller.activityManager.presentActivity(music)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            TimerService.shared.startTimer(duration: 60, label: "Focus")
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.left.arrow.right")
                            Text("Music ➔ Timer Morph Sequence")
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: {
                        controller.activityManager.clearAllActivities()
                        TimerService.shared.stopTimer()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Clear All Dynamic Island Activities")
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    @ViewBuilder
    private func speedButton(label: String, value: Double) -> some View {
        Button(action: {
            animConfig.speedMultiplier = value
        }) {
            Text(label)
                .font(.system(size: 11, weight: animConfig.speedMultiplier == value ? .bold : .medium))
                .foregroundColor(animConfig.speedMultiplier == value ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(animConfig.speedMultiplier == value ? Color.accentColor : Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func stateButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func simButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
