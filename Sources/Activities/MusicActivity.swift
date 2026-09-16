import SwiftUI

public final class MusicActivity: DynamicIslandActivity, ObservableObject {
    public let id: String
    public let type: ActivityType = .music
    public let priority: ActivityPriority = .standard
    public var timeoutDuration: TimeInterval? = nil
    
    @Published public var title: String
    @Published public var artist: String
    @Published public var album: String
    @Published public var isPlaying: Bool {
        didSet {
            if isPlaying {
                startPlaybackTimer()
            } else {
                playbackTimer?.invalidate()
                playbackTimer = nil
            }
        }
    }
    @Published public var duration: TimeInterval
    @Published public var elapsedTime: TimeInterval
    @Published public var sourceApp: String
    @Published public var artwork: NSImage?
    
    public var subtitle: String { artist }
    public var iconName: String { "music.note" }
    public var tintColor: Color {
        if sourceApp == "Apple Music" {
            return Color(red: 0.98, green: 0.18, blue: 0.35)
        } else if sourceApp == "YouTube" {
            return Color(red: 1.0, green: 0.1, blue: 0.1)
        } else if sourceApp == "Netflix" {
            return Color(red: 0.89, green: 0.04, blue: 0.08)
        } else if sourceApp == "JioHotstar" || sourceApp == "Hotstar" || sourceApp == "JioCinema" {
            return Color(red: 0.05, green: 0.45, blue: 1.0)
        }
        return Color(red: 0.18, green: 0.82, blue: 0.35)
    }
    
    public var progress: Double? {
        guard duration > 0 else { return 0 }
        return max(0.0, min(1.0, elapsedTime / duration))
    }
    
    public var compactPreferredWidth: CGFloat { 248 }
    public var expandedPreferredSize: CGSize {
        if duration > 0 {
            return CGSize(width: 390, height: 165)
        }
        return CGSize(width: 380, height: 140)
    }
    
    private var playbackTimer: Timer?
    
    public init(
        id: String = "activity.music",
        title: String = "Not Playing",
        artist: String = "No Artist",
        album: String = "",
        isPlaying: Bool = false,
        duration: TimeInterval = 180,
        elapsedTime: TimeInterval = 0,
        sourceApp: String = "Spotify",
        artwork: NSImage? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.sourceApp = sourceApp
        self.artwork = artwork
        
        if isPlaying {
            startPlaybackTimer()
        }
    }
    
    deinit {
        playbackTimer?.invalidate()
    }
    
    public func startPlaybackTimer() {
        playbackTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying, self.duration > 0 else { return }
            if self.elapsedTime < self.duration {
                self.elapsedTime += 1
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.playbackTimer = timer
    }
    
    public func compactLeadingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            MusicCompactLeadingView(activity: self, namespace: namespace)
        )
    }
    
    public func compactTrailingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            MusicCompactTrailingView(activity: self, namespace: namespace)
        )
    }
    
    public func expandedView(controller: DynamicIslandController, namespace: Namespace.ID?) -> AnyView {
        AnyView(
            MusicExpandedCardView(activity: self, controller: controller, namespace: namespace)
        )
    }
    
    public var minimalBubbleView: AnyView {
        AnyView(
            MusicMinimalBubbleView(activity: self)
        )
    }
}

public struct MusicMinimalBubbleView: View {
    @ObservedObject public var activity: MusicActivity
    
    public var body: some View {
        Group {
            if let artwork = activity.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if activity.sourceApp == "YouTube" {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.1, blue: 0.1), Color(red: 0.8, green: 0.0, blue: 0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            } else if activity.sourceApp == "Netflix" {
                ZStack {
                    Color.black
                    Text("N")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.89, green: 0.04, blue: 0.08))
                }
            } else if activity.sourceApp == "JioHotstar" || activity.sourceApp == "Hotstar" || activity.sourceApp == "JioCinema" {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.45, blue: 1.0), Color(red: 0.0, green: 0.15, blue: 0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.2, blue: 0.4), Color(red: 0.8, green: 0.1, blue: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Compact Leading View observing MusicActivity for live artwork updates
public struct MusicCompactLeadingView: View {
    @ObservedObject public var activity: MusicActivity
    public let namespace: Namespace.ID?
    
    public var body: some View {
        Group {
            if let art = activity.artwork {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if activity.sourceApp == "YouTube" {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.1, blue: 0.1), Color(red: 0.8, green: 0.0, blue: 0.0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            } else if activity.sourceApp == "Netflix" {
                ZStack {
                    Color.black
                    Text("N")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.89, green: 0.04, blue: 0.08))
                }
            } else if activity.sourceApp == "JioHotstar" || activity.sourceApp == "Hotstar" || activity.sourceApp == "JioCinema" {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.45, blue: 1.0), Color(red: 0.0, green: 0.15, blue: 0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.95, green: 0.2, blue: 0.4), Color(red: 0.8, green: 0.1, blue: 0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: 21, height: 21)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .padding(.leading, 4)
        .matchedGeometryIfAvailable(id: "music_art_\(activity.id)", in: namespace)
    }
}

/// Compact Trailing View observing playback state for live equalizer animation
public struct MusicCompactTrailingView: View {
    @ObservedObject public var activity: MusicActivity
    public let namespace: Namespace.ID?
    
    public var body: some View {
        MusicWaveformIndicator(isPlaying: activity.isPlaying, tintColor: activity.tintColor)
            .padding(.trailing, 2.5)
            .matchedGeometryIfAvailable(id: "music_wave_\(activity.id)", in: namespace)
    }
}

/// Animated 4-Bar Audio Equalizer Waveform Indicator
public struct MusicWaveformIndicator: View {
    public let isPlaying: Bool
    public var tintColor: Color = Color(red: 0.18, green: 0.82, blue: 0.35)
    
    @State private var barHeights: [CGFloat] = [0.35, 0.75, 1.0, 0.55]
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    
    public var body: some View {
        HStack(spacing: 2.2) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tintColor)
                    .frame(width: 2.6, height: isPlaying ? max(3.5, 16.5 * barHeights[index]) : 3.5)
                    .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPlaying ? barHeights[index] : 0)
            }
        }
        .onReceive(timer) { _ in
            if isPlaying {
                barHeights = [
                    CGFloat.random(in: 0.25...1.0),
                    CGFloat.random(in: 0.2...0.9),
                    CGFloat.random(in: 0.35...1.0),
                    CGFloat.random(in: 0.2...0.85)
                ]
            }
        }
    }
}

public struct MusicExpandedCardView: View {
    @ObservedObject public var activity: MusicActivity
    public let controller: DynamicIslandController
    public let namespace: Namespace.ID?
    
    private var sourceAppFormatted: String {
        switch activity.sourceApp {
        case "YouTube": return "YouTube • Google Chrome"
        case "Netflix": return "Netflix • Google Chrome"
        case "JioHotstar": return "JioHotstar • Google Chrome"
        case "JioCinema": return "JioCinema • Google Chrome"
        default: return activity.sourceApp
        }
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Header Info & Artwork
            HStack(spacing: 14) {
                // Morphing Album Art / Thumbnail
                Group {
                    if let artwork = activity.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if activity.sourceApp == "YouTube" {
                        ZStack {
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.1, blue: 0.1), Color(red: 0.8, green: 0.0, blue: 0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "play.rectangle.fill")
                                .font(.system(size: 27, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    } else if activity.sourceApp == "Netflix" {
                        ZStack {
                            Color.black
                            Text("N")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(Color(red: 0.89, green: 0.04, blue: 0.08))
                        }
                    } else if activity.sourceApp == "JioHotstar" || activity.sourceApp == "Hotstar" || activity.sourceApp == "JioCinema" {
                        ZStack {
                            LinearGradient(
                                colors: [Color(red: 0.05, green: 0.45, blue: 1.0), Color(red: 0.0, green: 0.15, blue: 0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    } else if activity.sourceApp == "Apple Music" {
                        ZStack {
                            LinearGradient(
                                colors: [Color(red: 0.98, green: 0.18, blue: 0.35), Color(red: 0.85, green: 0.08, blue: 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white.opacity(0.95))
                        }
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Color(red: 0.15, green: 0.75, blue: 0.35), Color(red: 0.05, green: 0.35, blue: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: "music.note")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .matchedGeometryIfAvailable(id: "music_art_\(activity.id)", in: namespace)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(activity.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .matchedGeometryIfAvailable(id: "music_title_\(activity.id)", in: namespace)
                    
                    Text(activity.subtitle)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .lineLimit(1)
                    
                    Text(sourceAppFormatted)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                MusicWaveformIndicator(isPlaying: activity.isPlaying, tintColor: activity.tintColor)
                    .frame(width: 22, height: 18)
                    .matchedGeometryIfAvailable(id: "music_wave_\(activity.id)", in: namespace)
            }
            
            // Interactive Scrubber Timeline Bar (when duration is available)
            if activity.duration > 0 {
                MusicScrubberView(activity: activity)
            }
            
            // Playback Controls (available across all media sources)
            HStack(spacing: 36) {
                Button(action: {
                    MediaService.shared.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    MediaService.shared.togglePlayPause()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: activity.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                    }
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    MediaService.shared.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.leading, 6)
    }
}

/// Interactive Scrubber Slider for Seeking / Controlling Duration
public struct MusicScrubberView: View {
    @ObservedObject public var activity: MusicActivity
    @State private var isDragging: Bool = false
    @State private var dragProgress: Double = 0
    
    private var currentProgress: Double {
        if isDragging {
            return dragProgress
        }
        guard activity.duration > 0 else { return 0 }
        return max(0.0, min(1.0, activity.elapsedTime / activity.duration))
    }
    
    private var currentDisplayTime: TimeInterval {
        if isDragging {
            return dragProgress * activity.duration
        }
        return activity.elapsedTime
    }
    
    public var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                let clampedProg = max(0.0, min(1.0, currentProgress))
                
                ZStack(alignment: .leading) {
                    // Track Bar
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 5)
                    
                    // Filled Progress Bar
                    Capsule()
                        .fill(activity.tintColor)
                        .frame(width: width * CGFloat(clampedProg), height: 5)
                    
                    // Draggable Scrubber Thumb Dot
                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 12 : 9, height: isDragging ? 12 : 9)
                        .shadow(color: Color.black.opacity(0.4), radius: 2)
                        .offset(x: max(0, min(width - 9, width * CGFloat(clampedProg) - 4.5)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            let progress = max(0.0, min(1.0, Double(value.location.x / width)))
                            dragProgress = progress
                        }
                        .onEnded { value in
                            let progress = max(0.0, min(1.0, Double(value.location.x / width)))
                            let newTime = progress * activity.duration
                            activity.elapsedTime = newTime
                            MediaService.shared.seek(to: newTime)
                            isDragging = false
                        }
                )
            }
            .frame(height: 12)
            
            // Time Labels
            HStack {
                Text(formatTime(currentDisplayTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                Text("-" + formatTime(max(0, activity.duration - currentDisplayTime)))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
