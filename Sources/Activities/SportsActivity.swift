import SwiftUI
import AppKit

// MARK: - Sports Models

public enum SportType: String, CaseIterable, Sendable, Identifiable {
    case football = "Football"
    case basketball = "Basketball"
    case formula1 = "Formula 1"
    case cricket = "Cricket"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .football: return "soccerball"
        case .basketball: return "basketball.fill"
        case .formula1: return "flag.checkered.2.crossed"
        case .cricket: return "cricket.ball.fill"
        }
    }
}

public enum MatchStatus: Sendable, Equatable {
    case scheduled(kickoffTime: String)
    case live
    case finalScore
}

public struct SportsMatchEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public let time: String
    public let title: String
    public let player: String
    public let icon: String
    
    public init(id: String = UUID().uuidString, time: String, title: String, player: String, icon: String = "soccerball") {
        self.id = id
        self.time = time
        self.title = title
        self.player = player
        self.icon = icon
    }
}

public struct SportsTeam: Sendable, Equatable {
    public let name: String
    public let abbreviation: String
    public var score: String
    public let color: Color
    public let iconName: String
    public let logoUrl: String?
    public let record: String?
    
    /// Clean runs/score without overs or annotations (e.g. "90/3 (23.2 ov)" -> "90/3")
    public var displayScore: String {
        if let parenRange = score.range(of: " (") {
            let runsPart = String(score[..<parenRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            return runsPart.isEmpty ? score : runsPart
        }
        return score
    }
    
    /// Short concise score for compact dynamic island wings (e.g. "161 & 74/2" -> "74/2")
    public var compactScore: String {
        let clean = displayScore
        if clean.contains("&") {
            let parts = clean.components(separatedBy: "&")
            if let last = parts.last?.trimmingCharacters(in: .whitespaces), !last.isEmpty {
                return last
            }
        }
        return clean
    }
    
    public init(
        name: String,
        abbreviation: String,
        score: String,
        color: Color,
        iconName: String = "shield.fill",
        logoUrl: String? = nil,
        record: String? = nil
    ) {
        self.name = name
        self.abbreviation = abbreviation
        self.score = score
        self.color = color
        self.iconName = iconName
        self.logoUrl = logoUrl
        self.record = record
    }
}

public struct SportsMatch: Sendable, Equatable {
    public let id: String
    public let sport: SportType
    public let league: String
    public let venue: String
    public var team1: SportsTeam
    public var team2: SportsTeam
    public var periodText: String
    public var status: MatchStatus
    public var liveSummary: String
    public var events: [SportsMatchEvent]
    public var matchUrl: String
    public var progress: Double?
    public var isRealData: Bool
    
    public var isLive: Bool {
        if case .live = status { return true }
        return false
    }
    
    public var isScheduled: Bool {
        if case .scheduled = status { return true }
        return false
    }
    
    public var scheduledTime: String {
        if case .scheduled(let time) = status { return time }
        return "Today"
    }
    
    /// Highly concise period/clock for compact dynamic island wing
    public var compactPeriodText: String {
        if isScheduled {
            return scheduledTime
        }
        
        // Cricket overs extraction if present in team scores
        if sport == .cricket {
            for team in [team2, team1] {
                if let start = team.score.range(of: "("), let end = team.score.range(of: " ov") {
                    let overs = String(team.score[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if !overs.isEmpty {
                        return "\(overs) ov"
                    }
                }
            }
            if periodText.contains("Day") {
                return periodText
            }
            if periodText.count > 10 {
                return "LIVE"
            }
        }
        
        // Soccer: "Second Half 78'" -> "78'"
        if sport == .football {
            if periodText.contains("'") {
                let parts = periodText.components(separatedBy: " ")
                if let minute = parts.first(where: { $0.contains("'") }) {
                    return minute
                }
            }
            if periodText.lowercased().contains("halftime") || periodText.lowercased() == "ht" {
                return "HT"
            }
            if periodText.lowercased().contains("fulltime") || periodText.lowercased() == "ft" {
                return "FT"
            }
        }
        
        // Basketball: "4th Qtr 02:14" -> "Q4 02:14"
        if sport == .basketball {
            var p = periodText
            p = p.replacingOccurrences(of: "1st Qtr", with: "Q1")
            p = p.replacingOccurrences(of: "2nd Qtr", with: "Q2")
            p = p.replacingOccurrences(of: "3rd Qtr", with: "Q3")
            p = p.replacingOccurrences(of: "4th Qtr", with: "Q4")
            p = p.replacingOccurrences(of: "Halftime", with: "HT")
            p = p.replacingOccurrences(of: "End of ", with: "End ")
            if p.count <= 10 {
                return p
            }
        }
        
        if periodText.count > 10 {
            return String(periodText.prefix(9)) + "…"
        }
        return periodText
    }
    
    public init(
        id: String,
        sport: SportType,
        league: String,
        venue: String,
        team1: SportsTeam,
        team2: SportsTeam,
        periodText: String,
        status: MatchStatus = .live,
        liveSummary: String,
        events: [SportsMatchEvent] = [],
        matchUrl: String = "https://www.espn.com",
        progress: Double? = nil,
        isRealData: Bool = false
    ) {
        self.id = id
        self.sport = sport
        self.league = league
        self.venue = venue
        self.team1 = team1
        self.team2 = team2
        self.periodText = periodText
        self.status = status
        self.liveSummary = liveSummary
        self.events = events
        self.matchUrl = matchUrl
        self.progress = progress
        self.isRealData = isRealData
    }
}

// MARK: - Dynamic Island Sports Activity

public final class SportsActivity: DynamicIslandActivity, ObservableObject {
    public let id: String
    public let type: ActivityType = .sports
    public let priority: ActivityPriority = .high
    public var timeoutDuration: TimeInterval? = nil // Persistent live tracking
    
    @Published public var match: SportsMatch
    
    public var title: String {
        if match.isScheduled {
            return "\(match.team1.abbreviation) vs \(match.team2.abbreviation)"
        }
        return "\(match.team1.abbreviation) \(match.team1.score) - \(match.team2.score) \(match.team2.abbreviation)"
    }
    
    public var subtitle: String {
        if match.isScheduled {
            return "\(match.league) • \(match.scheduledTime)"
        }
        return "\(match.league) • \(match.periodText)"
    }
    
    public var iconName: String { match.sport.icon }
    public var tintColor: Color { match.team1.color }
    public var progress: Double? { match.progress }
    
    public var compactPreferredWidth: CGFloat {
        let notchWidth = max(DisplayManager.shared.currentNotchInfo.notchSize.width, 185.0)
        if match.isScheduled {
            return max(450.0, notchWidth + 265.0)
        }
        switch match.sport {
        case .cricket:
            return max(490.0, notchWidth + 305.0)
        default:
            return max(460.0, notchWidth + 275.0)
        }
    }
    
    public var expandedPreferredSize: CGSize { CGSize(width: 480, height: 215) }
    
    public init(match: SportsMatch) {
        self.id = "activity.sports.\(match.id)"
        self.match = match
    }
    
    public func compactLeadingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(SportsCompactLeadingView(activity: self, namespace: namespace))
    }
    
    public func compactTrailingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(SportsCompactTrailingView(activity: self, namespace: namespace))
    }
    
    public func expandedView(controller: DynamicIslandController, namespace: Namespace.ID?) -> AnyView {
        AnyView(SportsExpandedCardView(activity: self, controller: controller, namespace: namespace))
    }
    
    public var minimalBubbleView: AnyView {
        AnyView(SportsMinimalBubbleView(activity: self))
    }
}

// MARK: - Remote Team Logo View

public struct RemoteTeamLogoView: View {
    public let logoUrl: String?
    public let abbreviation: String
    public let color: Color
    public let size: CGFloat
    
    @State private var loadedImage: NSImage?
    
    public var body: some View {
        ZStack {
            if let img = loadedImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Sleek Monogram Badge Fallback with Team Color Accent
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.85), color],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size, height: size)
                    
                    Text(abbreviation.prefix(3))
                        .font(.system(size: size * 0.42, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: logoUrl) { _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        guard let urlStr = logoUrl, let url = URL(string: urlStr) else { return }
        SportsService.shared.fetchLogoImage(from: url) { image in
            DispatchQueue.main.async {
                self.loadedImage = image
            }
        }
    }
}

// MARK: - Compact Leading View (Home Wing)

public struct SportsCompactLeadingView: View {
    @ObservedObject public var activity: SportsActivity
    public let namespace: Namespace.ID?
    
    public var body: some View {
        let match = activity.match
        
        HStack(spacing: 6) {
            // Home Team Logo
            RemoteTeamLogoView(
                logoUrl: match.team1.logoUrl,
                abbreviation: match.team1.abbreviation,
                color: match.team1.color,
                size: 20
            )
            .shadow(color: match.team1.color.opacity(0.35), radius: 3, x: 0, y: 1)
            
            Text(match.team1.abbreviation)
                .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            
            if match.isScheduled {
                Text("vs")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
            } else {
                Text(match.team1.compactScore)
                    .font(.system(size: 13.5, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(match.team1.color.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .padding(.leading, 8)
        .matchedGeometryIfAvailable(id: "sports_lead_\(activity.id)", in: namespace)
    }
}

// MARK: - Compact Trailing View (Away Wing)

public struct SportsCompactTrailingView: View {
    @ObservedObject public var activity: SportsActivity
    public let namespace: Namespace.ID?
    
    @State private var isPulseActive: Bool = false
    
    public var body: some View {
        let match = activity.match
        
        HStack(spacing: 6) {
            if match.isScheduled {
                Text(match.team2.abbreviation)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                
                RemoteTeamLogoView(
                    logoUrl: match.team2.logoUrl,
                    abbreviation: match.team2.abbreviation,
                    color: match.team2.color,
                    size: 20
                )
                .shadow(color: match.team2.color.opacity(0.35), radius: 3, x: 0, y: 1)
                
                // Scheduled Kickoff Pill
                HStack(spacing: 3.5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 8.5, weight: .bold))
                    Text(match.compactPeriodText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background(Color.cyan.opacity(0.16))
                .clipShape(Capsule())
            } else {
                // Team 2 Score
                Text(match.team2.compactScore)
                    .font(.system(size: 13.5, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(match.team2.color.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                
                Text(match.team2.abbreviation)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                
                RemoteTeamLogoView(
                    logoUrl: match.team2.logoUrl,
                    abbreviation: match.team2.abbreviation,
                    color: match.team2.color,
                    size: 20
                )
                .shadow(color: match.team2.color.opacity(0.35), radius: 3, x: 0, y: 1)
                
                // Live Indicator Pill with breathing pulse
                HStack(spacing: 4) {
                    if match.isLive {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.4))
                                .frame(width: 8, height: 8)
                                .scaleEffect(isPulseActive ? 1.5 : 0.8)
                                .opacity(isPulseActive ? 0.0 : 0.9)
                                .animation(Animation.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: isPulseActive)
                            
                            Circle()
                                .fill(Color.red)
                                .frame(width: 4.5, height: 4.5)
                        }
                    }
                    
                    Text(match.compactPeriodText)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(match.isLive ? .red : .white.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background(match.isLive ? Color.red.opacity(0.14) : Color.white.opacity(0.1))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(match.isLive ? Color.red.opacity(0.35) : Color.clear, lineWidth: 0.8)
                )
            }
        }
        .padding(.trailing, 8)
        .matchedGeometryIfAvailable(id: "sports_trail_\(activity.id)", in: namespace)
        .onAppear {
            isPulseActive = true
        }
    }
}

// MARK: - Expanded Card View (Stadium Scoreboard)

public struct SportsExpandedCardView: View {
    @ObservedObject public var activity: SportsActivity
    @ObservedObject public var controller: DynamicIslandController
    @ObservedObject private var sportsService = SportsService.shared
    public let namespace: Namespace.ID?
    
    @State private var isRefreshing: Bool = false
    
    public var body: some View {
        let match = activity.match
        
        VStack(spacing: 7) {
            // Header Row: League, Venue & Status Badge
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: match.sport.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accentColor)
                    
                    Text("\(match.league) • \(match.venue)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: 8)
                
                HStack(spacing: 6) {
                    if match.isRealData {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4.5, height: 4.5)
                            Text("ESPN LIVE")
                                .font(.system(size: 8.5, weight: .black, design: .rounded))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    
                    if match.isScheduled {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 8.5))
                            Text("SCHEDULED • \(match.scheduledTime)")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.cyan.opacity(0.15))
                        .clipShape(Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(match.isLive ? Color.red : Color.gray)
                                .frame(width: 4.5, height: 4.5)
                            
                            Text(match.isLive ? "LIVE • \(match.periodText)" : match.periodText)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(match.isLive ? .red : .white.opacity(0.85))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(match.isLive ? Color.red.opacity(0.16) : Color.white.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            
            // Stadium Scoreboard Display Box
            HStack(alignment: .center, spacing: 8) {
                // Team 1 (Home)
                HStack(spacing: 8) {
                    RemoteTeamLogoView(
                        logoUrl: match.team1.logoUrl,
                        abbreviation: match.team1.abbreviation,
                        color: match.team1.color,
                        size: 36
                    )
                    .shadow(color: match.team1.color.opacity(0.4), radius: 4, x: 0, y: 1)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.team1.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                        
                        Text(match.team1.record ?? match.team1.abbreviation)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Center Score or Scheduled Time
                VStack(spacing: 2) {
                    if match.isScheduled {
                        VStack(spacing: 2) {
                            Text("VS")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.35))
                            Text(match.scheduledTime)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.cyan)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(match.team1.displayScore)
                                .font(.system(size: match.team1.displayScore.count > 3 ? 20 : 25, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            
                            Text(":")
                                .font(.system(size: 18, weight: .ultraLight))
                                .foregroundColor(.white.opacity(0.4))
                            
                            Text(match.team2.displayScore)
                                .font(.system(size: match.team2.displayScore.count > 3 ? 20 : 25, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        
                        Text(match.compactPeriodText.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(match.isLive ? .red : .white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 90, maxWidth: 130)
                
                // Team 2 (Away)
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(match.team2.name)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                        
                        Text(match.team2.record ?? match.team2.abbreviation)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                    
                    RemoteTeamLogoView(
                        logoUrl: match.team2.logoUrl,
                        abbreviation: match.team2.abbreviation,
                        color: match.team2.color,
                        size: 36
                    )
                    .shadow(color: match.team2.color.opacity(0.4), radius: 4, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 10)
            
            // Match Summary / Key Event
            HStack(spacing: 6) {
                if match.isScheduled {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)
                    Text(match.liveSummary)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if let lastEvent = match.events.last {
                    Image(systemName: lastEvent.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text("\(lastEvent.time) \(lastEvent.player) (\(lastEvent.title))")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Image(systemName: match.sport.icon)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                    Text(match.liveSummary)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            
            // Bottom Action Bar
            HStack(spacing: 8) {
                let currentIdx = sportsService.availableMatches.firstIndex(where: { $0.id == match.id }) ?? sportsService.currentMatchIndex
                let total = max(1, sportsService.availableMatches.count)
                Text("\(match.sport.rawValue) • \(currentIdx + 1)/\(total)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))
                
                Spacer()
                
                // Action Controls
                HStack(spacing: 6) {
                    // Refresh Button
                    Button(action: {
                        isRefreshing = true
                        sportsService.fetchLiveScores()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? Animation.linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            .padding(5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Next Match
                    Button(action: {
                        sportsService.cycleNextMatch()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                            Text("Next")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Official Gamecast URL
                    Button(action: {
                        if let url = URL(string: match.matchUrl) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("Gamecast")
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Dismiss Button
                    Button(action: {
                        controller.activityManager.removeActivity(id: activity.id)
                        if controller.activityManager.activeActivity != nil {
                            controller.transition(to: .compact)
                        } else {
                            controller.transition(to: .idle)
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(5)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Minimal Secondary Bubble View

public struct SportsMinimalBubbleView: View {
    @ObservedObject public var activity: SportsActivity
    
    public var body: some View {
        let match = activity.match
        VStack(spacing: 1) {
            Image(systemName: match.sport.icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(match.team1.color)
            
            if match.isScheduled {
                Text("VS")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundColor(.cyan)
            } else {
                Text("\(match.team1.score)-\(match.team2.score)")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }
}
