import Foundation
import SwiftUI
import Combine
import AVFoundation

public enum VisualizerTheme: String, CaseIterable, Identifiable, Sendable {
    case ocean = "Ocean Waves"
    case sunset = "Sunset Neon"
    case cyberpunk = "Cyberpunk"
    case aurora = "Aurora Green"
    case fire = "Blazing Fire"
    
    public var id: String { rawValue }
    
    public var gradientColors: [Color] {
        switch self {
        case .ocean:
            return [
                Color(red: 0.0, green: 0.85, blue: 1.0),
                Color(red: 0.1, green: 0.5, blue: 1.0),
                Color(red: 0.4, green: 0.2, blue: 1.0)
            ]
        case .sunset:
            return [
                Color(red: 1.0, green: 0.2, blue: 0.5),
                Color(red: 1.0, green: 0.55, blue: 0.2),
                Color(red: 1.0, green: 0.85, blue: 0.2)
            ]
        case .cyberpunk:
            return [
                Color(red: 0.8, green: 0.1, blue: 1.0),
                Color(red: 0.0, green: 1.0, blue: 0.8),
                Color(red: 0.9, green: 0.0, blue: 0.6)
            ]
        case .aurora:
            return [
                Color(red: 0.15, green: 0.95, blue: 0.65),
                Color(red: 0.0, green: 0.8, blue: 0.9),
                Color(red: 0.2, green: 1.0, blue: 0.4)
            ]
        case .fire:
            return [
                Color(red: 1.0, green: 0.15, blue: 0.0),
                Color(red: 1.0, green: 0.5, blue: 0.0),
                Color(red: 1.0, green: 0.85, blue: 0.2)
            ]
        }
    }
}

public enum VisualizerStyle: String, CaseIterable, Identifiable, Sendable {
    case bottomContour = "Bottom Notch Wave"
    case dualWings = "Symmetric Equalizer"
    case neonGlow = "Ambient Aura Glow"
    
    public var id: String { rawValue }
}

/// Service that monitors audio playback and generates smooth reactive waveform spectra
public final class AudioVisualizerService: ObservableObject {
    public static let shared = AudioVisualizerService()
    
    @Published public var isEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "macbooknotch.visualizer.enabled")
            if !isEnabled {
                currentAmplitudes = Array(repeating: 0.0, count: 16)
            }
        }
    }
    
    @Published public var currentTheme: VisualizerTheme = .ocean {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "macbooknotch.visualizer.theme")
        }
    }
    
    @Published public var currentStyle: VisualizerStyle = .bottomContour {
        didSet {
            UserDefaults.standard.set(currentStyle.rawValue, forKey: "macbooknotch.visualizer.style")
        }
    }
    
    @Published public private(set) var isAudioActive: Bool = false
    @Published public private(set) var currentAmplitudes: [CGFloat] = Array(repeating: 0.05, count: 16)
    @Published public private(set) var overallIntensity: CGFloat = 0.0
    
    private var renderTimer: Timer?
    private var phase: Double = 0.0
    private var targetAmplitudes: [CGFloat] = Array(repeating: 0.05, count: 16)
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        let storedEnabled = UserDefaults.standard.object(forKey: "macbooknotch.visualizer.enabled") as? Bool ?? true
        self.isEnabled = storedEnabled
        
        if let storedThemeStr = UserDefaults.standard.string(forKey: "macbooknotch.visualizer.theme"),
           let theme = VisualizerTheme(rawValue: storedThemeStr) {
            self.currentTheme = theme
        }
        
        if let storedStyleStr = UserDefaults.standard.string(forKey: "macbooknotch.visualizer.style"),
           let style = VisualizerStyle(rawValue: storedStyleStr) {
            self.currentStyle = style
        }
        
        startAudioMonitoring()
    }
    
    public func startAudioMonitoring() {
        // Connect to MediaService for active music playback
        MediaService.shared.$isPlaybackActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPlaying in
                self?.isAudioActive = isPlaying
            }
            .store(in: &cancellables)
        
        // 60fps / 16ms high-speed physics render loop for fluid audio reactive movement
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updatePhysicsStep()
        }
        if let timer = renderTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func updatePhysicsStep() {
        guard isEnabled else { return }
        
        let isTabVisible = MediaService.shared.currentTrack.isTabVisibleOnScreen
        let active = (isAudioActive || MediaService.shared.isPlaybackActive) && !isTabVisible
        phase += 0.08
        
        if active {
            // Generate dynamic rhythmic beat patterns
            let bassKick = max(0, sin(phase * 0.8)) * 0.85
            let midEnergy = (sin(phase * 2.3) + 1.0) * 0.45
            let trebleSpike = abs(cos(phase * 3.7)) * 0.6
            
            var newAmps: [CGFloat] = []
            for i in 0..<16 {
                let normalizedI = Double(i) / 15.0
                let wave = sin(phase * 2.0 + normalizedI * Double.pi * 3.0) * 0.35 + 0.55
                
                // Frequency band weighting
                var bandEnergy: Double
                if i < 4 { // Bass
                    bandEnergy = (bassKick * 0.6 + wave * 0.4)
                } else if i < 11 { // Mids
                    bandEnergy = (midEnergy * 0.5 + wave * 0.5)
                } else { // Highs
                    bandEnergy = (trebleSpike * 0.5 + wave * 0.5)
                }
                
                // Random micro-jitter for organic live equalizer feel
                let jitter = Double.random(in: -0.08...0.08)
                let target = CGFloat(max(0.08, min(1.0, bandEnergy + jitter)))
                newAmps.append(target)
            }
            
            // Smooth spring lerp interpolation towards target amplitudes
            for i in 0..<16 {
                currentAmplitudes[i] += (newAmps[i] - currentAmplitudes[i]) * 0.32
            }
            
            let avg = currentAmplitudes.reduce(0, +) / CGFloat(currentAmplitudes.count)
            overallIntensity = avg
        } else {
            // Smooth decay back to zero
            var allZero = true
            for i in 0..<16 {
                currentAmplitudes[i] += (0.0 - currentAmplitudes[i]) * 0.15
                if currentAmplitudes[i] > 0.01 {
                    allZero = false
                }
            }
            overallIntensity += (0.0 - overallIntensity) * 0.15
            if allZero {
                currentAmplitudes = Array(repeating: 0.0, count: 16)
                overallIntensity = 0.0
            }
        }
    }
}
