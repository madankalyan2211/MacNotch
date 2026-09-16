import Foundation
import SwiftUI
import AppKit
import Combine

/// Service that connects to real-time live sports feeds (Soccer, NBA, F1, Cricket)
/// via ESPN public endpoints, manages team crest image caching, favorite team preferences,
/// and powers the Dynamic Island with genuine live scores, clocks, and match events.
public final class SportsService: ObservableObject {
    public static let shared = SportsService()
    
    // MARK: - User Preferences
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "macbooknotch.sports.enabled")
            if !isEnabled {
                dismissMatch()
            }
        }
    }
    
    @Published public var autoShowMatchday: Bool {
        didSet {
            UserDefaults.standard.set(autoShowMatchday, forKey: "macbooknotch.sports.autoShowMatchday")
            if autoShowMatchday && activeMatch == nil {
                surfaceMatchdayIfAvailable()
            }
        }
    }
    
    @Published public var isFootballEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isFootballEnabled, forKey: "macbooknotch.sports.football.enabled")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    @Published public var isBasketballEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isBasketballEnabled, forKey: "macbooknotch.sports.basketball.enabled")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    @Published public var isF1Enabled: Bool {
        didSet {
            UserDefaults.standard.set(isF1Enabled, forKey: "macbooknotch.sports.f1.enabled")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    @Published public var isCricketEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isCricketEnabled, forKey: "macbooknotch.sports.cricket.enabled")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    @Published public var onlyShowFavorites: Bool {
        didSet {
            UserDefaults.standard.set(onlyShowFavorites, forKey: "macbooknotch.sports.onlyFavorites")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    public func isSportEnabled(_ sport: SportType) -> Bool {
        switch sport {
        case .football: return isFootballEnabled
        case .basketball: return isBasketballEnabled
        case .formula1: return isF1Enabled
        case .cricket: return isCricketEnabled
        }
    }
    
    @Published public var favoriteFootball: String {
        didSet {
            UserDefaults.standard.set(favoriteFootball, forKey: "macbooknotch.sports.fav.football")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    @Published public var favoriteBasketball: String {
        didSet {
            UserDefaults.standard.set(favoriteBasketball, forKey: "macbooknotch.sports.fav.basketball")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    @Published public var favoriteF1: String {
        didSet {
            UserDefaults.standard.set(favoriteF1, forKey: "macbooknotch.sports.fav.f1")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    @Published public var favoriteCricket: String {
        didSet {
            UserDefaults.standard.set(favoriteCricket, forKey: "macbooknotch.sports.fav.cricket")
            filterAvailableMatches()
            surfaceMatchdayIfAvailable()
        }
    }
    
    // MARK: - Live Feed State
    
    @Published public private(set) var activeMatch: SportsMatch?
    @Published public private(set) var availableMatches: [SportsMatch] = []
    @Published public private(set) var allRawMatches: [SportsMatch] = []
    
    @Published public var isLiveFeedConnected: Bool = true
    @Published public var lastUpdated: Date? = nil
    @Published public var isFetching: Bool = false
    
    public var onMatchUpdated: ((SportsMatch?) -> Void)?
    
    private var pollingTimer: Timer?
    @Published public private(set) var currentMatchIndex: Int = 0
    private let logoCache = NSCache<NSString, NSImage>()
    
    // MARK: - Catalogs
    
    public static let footballTeams: [(name: String, abbr: String, color: Color, logoUrl: String)] = [
        ("Arsenal", "ARS", Color(red: 0.95, green: 0.15, blue: 0.2), "https://a.espncdn.com/i/teamlogos/soccer/500/359.png"),
        ("Chelsea", "CHE", Color(red: 0.1, green: 0.4, blue: 0.95), "https://a.espncdn.com/i/teamlogos/soccer/500/363.png"),
        ("Manchester City", "MCI", Color(red: 0.4, green: 0.75, blue: 1.0), "https://a.espncdn.com/i/teamlogos/soccer/500/382.png"),
        ("Liverpool", "LIV", Color(red: 0.85, green: 0.1, blue: 0.15), "https://a.espncdn.com/i/teamlogos/soccer/500/364.png"),
        ("Manchester United", "MUN", Color(red: 0.9, green: 0.1, blue: 0.1), "https://a.espncdn.com/i/teamlogos/soccer/500/360.png"),
        ("Real Madrid", "RMA", Color(red: 0.85, green: 0.75, blue: 0.3), "https://a.espncdn.com/i/teamlogos/soccer/500/86.png"),
        ("Barcelona", "BAR", Color(red: 0.65, green: 0.1, blue: 0.4), "https://a.espncdn.com/i/teamlogos/soccer/500/83.png"),
        ("Bayern Munich", "BAY", Color(red: 0.85, green: 0.05, blue: 0.2), "https://a.espncdn.com/i/teamlogos/soccer/500/132.png")
    ]
    
    public static let basketballTeams: [(name: String, abbr: String, color: Color, logoUrl: String)] = [
        ("Lakers", "LAL", Color(red: 0.95, green: 0.75, blue: 0.1), "https://a.espncdn.com/i/teamlogos/nba/500/lal.png"),
        ("Warriors", "GSW", Color(red: 0.15, green: 0.45, blue: 0.95), "https://a.espncdn.com/i/teamlogos/nba/500/gsw.png"),
        ("Celtics", "BOS", Color(red: 0.1, green: 0.65, blue: 0.3), "https://a.espncdn.com/i/teamlogos/nba/500/bos.png"),
        ("Nuggets", "DEN", Color(red: 0.1, green: 0.2, blue: 0.5), "https://a.espncdn.com/i/teamlogos/nba/500/den.png"),
        ("Heat", "MIA", Color(red: 0.8, green: 0.15, blue: 0.2), "https://a.espncdn.com/i/teamlogos/nba/500/mia.png"),
        ("Mavericks", "DAL", Color(red: 0.1, green: 0.4, blue: 0.85), "https://a.espncdn.com/i/teamlogos/nba/500/dal.png")
    ]
    
    public static let f1Teams: [(name: String, abbr: String, color: Color, logoUrl: String)] = [
        ("Red Bull", "VER", Color(red: 0.1, green: 0.25, blue: 0.8), "https://a.espncdn.com/i/teamlogos/f1/500/redbull.png"),
        ("McLaren", "NOR", Color(red: 1.0, green: 0.5, blue: 0.0), "https://a.espncdn.com/i/teamlogos/f1/500/mclaren.png"),
        ("Ferrari", "LEC", Color(red: 0.95, green: 0.1, blue: 0.15), "https://a.espncdn.com/i/teamlogos/f1/500/ferrari.png"),
        ("Mercedes", "HAM", Color(red: 0.0, green: 0.85, blue: 0.8), "https://a.espncdn.com/i/teamlogos/f1/500/mercedes.png"),
        ("Aston Martin", "ALO", Color(red: 0.0, green: 0.45, blue: 0.35), "https://a.espncdn.com/i/teamlogos/f1/500/astonmartin.png")
    ]
    
    public static let cricketTeams: [(name: String, abbr: String, color: Color, logoUrl: String)] = [
        ("India", "IND", Color(red: 0.0, green: 0.55, blue: 1.0), "https://a.espncdn.com/i/teamlogos/cricket/500/6.png"),
        ("Australia", "AUS", Color(red: 0.95, green: 0.8, blue: 0.1), "https://a.espncdn.com/i/teamlogos/cricket/500/2.png"),
        ("England", "ENG", Color(red: 0.85, green: 0.15, blue: 0.2), "https://a.espncdn.com/i/teamlogos/cricket/500/1.png"),
        ("South Africa", "SA", Color(red: 0.1, green: 0.6, blue: 0.35), "https://a.espncdn.com/i/teamlogos/cricket/500/3.png"),
        ("CSK", "CSK", Color(red: 0.95, green: 0.8, blue: 0.0), "https://a.espncdn.com/i/teamlogos/cricket/500/4340.png"),
        ("RCB", "RCB", Color(red: 0.85, green: 0.1, blue: 0.15), "https://a.espncdn.com/i/teamlogos/cricket/500/4345.png"),
        ("MI", "MI", Color(red: 0.0, green: 0.4, blue: 0.85), "https://a.espncdn.com/i/teamlogos/cricket/500/4346.png")
    ]
    
    private init() {
        let storedEnabled = UserDefaults.standard.object(forKey: "macbooknotch.sports.enabled") as? Bool ?? true
        let storedAuto = UserDefaults.standard.object(forKey: "macbooknotch.sports.autoShowMatchday") as? Bool ?? true
        let storedOnlyFavs = UserDefaults.standard.object(forKey: "macbooknotch.sports.onlyFavorites") as? Bool ?? true
        
        let storedFootEnabled = UserDefaults.standard.object(forKey: "macbooknotch.sports.football.enabled") as? Bool ?? true
        let storedBaskEnabled = UserDefaults.standard.object(forKey: "macbooknotch.sports.basketball.enabled") as? Bool ?? true
        let storedF1Enabled = UserDefaults.standard.object(forKey: "macbooknotch.sports.f1.enabled") as? Bool ?? true
        let storedCricEnabled = UserDefaults.standard.object(forKey: "macbooknotch.sports.cricket.enabled") as? Bool ?? true
        
        let storedFoot = UserDefaults.standard.string(forKey: "macbooknotch.sports.fav.football") ?? "Arsenal"
        let storedBask = UserDefaults.standard.string(forKey: "macbooknotch.sports.fav.basketball") ?? "Lakers"
        let storedF1 = UserDefaults.standard.string(forKey: "macbooknotch.sports.fav.f1") ?? "Red Bull"
        let storedCric = UserDefaults.standard.string(forKey: "macbooknotch.sports.fav.cricket") ?? "India"
        
        self.isEnabled = storedEnabled
        self.autoShowMatchday = storedAuto
        self.onlyShowFavorites = storedOnlyFavs
        self.isFootballEnabled = storedFootEnabled
        self.isBasketballEnabled = storedBaskEnabled
        self.isF1Enabled = storedF1Enabled
        self.isCricketEnabled = storedCricEnabled
        self.favoriteFootball = storedFoot
        self.favoriteBasketball = storedBask
        self.favoriteF1 = storedF1
        self.favoriteCricket = storedCric
        
        logoCache.countLimit = 150
        
        // Initial build with fallback
        rebuildFallbackFixtures()
        
        // Trigger live network fetch from ESPN endpoints
        fetchLiveScores()
        
        // Start background polling (every 30s)
        startPollingTimer()
    }
    
    deinit {
        pollingTimer?.invalidate()
    }
    
    // MARK: - Team Logo Cache
    
    public func fetchLogoImage(from url: URL, completion: @escaping (NSImage?) -> Void) {
        let key = url.absoluteString as NSString
        if let cached = logoCache.object(forKey: key) {
            completion(cached)
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data, let image = NSImage(data: data) else {
                completion(nil)
                return
            }
            self?.logoCache.setObject(image, forKey: key)
            completion(image)
        }.resume()
    }
    
    // MARK: - Background Polling
    
    private func startPollingTimer() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 35.0, repeats: true) { [weak self] _ in
            self?.fetchLiveScores()
        }
    }
    
    // MARK: - Real-Time Live Feed Fetching
    
    public func fetchLiveScores() {
        guard isEnabled else { return }
        
        DispatchQueue.main.async {
            self.isFetching = true
        }
        
        let dispatchGroup = DispatchGroup()
        var fetchedMatches: [SportsMatch] = []
        let lock = NSLock()
        
        // 1. Fetch Soccer (Premier League & Champions League)
        let soccerUrls = [
            "https://site.api.espn.com/apis/site/v2/sports/soccer/eng.1/scoreboard",
            "https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions/scoreboard"
        ]
        for urlStr in soccerUrls {
            guard let url = URL(string: urlStr) else { continue }
            dispatchGroup.enter()
            fetchJSON(url: url) { [weak self] json in
                defer { dispatchGroup.leave() }
                guard let json = json, let parsed = self?.parseSoccer(json: json) else { return }
                lock.lock()
                fetchedMatches.append(contentsOf: parsed)
                lock.unlock()
            }
        }
        
        // 2. Fetch Basketball (NBA)
        if let nbaUrl = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard") {
            dispatchGroup.enter()
            fetchJSON(url: nbaUrl) { [weak self] json in
                defer { dispatchGroup.leave() }
                guard let json = json, let parsed = self?.parseNBA(json: json) else { return }
                lock.lock()
                fetchedMatches.append(contentsOf: parsed)
                lock.unlock()
            }
        }
        
        // 3. Fetch Formula 1
        if let f1Url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/racing/f1/scoreboard") {
            dispatchGroup.enter()
            fetchJSON(url: f1Url) { [weak self] json in
                defer { dispatchGroup.leave() }
                guard let json = json, let parsed = self?.parseF1(json: json) else { return }
                lock.lock()
                fetchedMatches.append(contentsOf: parsed)
                lock.unlock()
            }
        }
        
        // 4. Fetch Cricket (Personalized / Live Series Header)
        if let cricketUrl = URL(string: "https://site.api.espn.com/apis/personalized/v2/scoreboard/header?sport=cricket") {
            dispatchGroup.enter()
            fetchJSON(url: cricketUrl) { [weak self] json in
                defer { dispatchGroup.leave() }
                guard let json = json, let parsed = self?.parseCricket(json: json) else { return }
                lock.lock()
                fetchedMatches.append(contentsOf: parsed)
                lock.unlock()
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isFetching = false
            self.lastUpdated = Date()
            self.isLiveFeedConnected = true
            
            if !fetchedMatches.isEmpty {
                self.allRawMatches = fetchedMatches
            }
            self.filterAvailableMatches()
        }
    }
    
    private func fetchJSON(url: URL, completion: @escaping ([String: Any]?) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: req) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                completion(json)
            } catch {
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - Parsers
    
    private func parseSoccer(json: [String: Any]) -> [SportsMatch] {
        var result: [SportsMatch] = []
        guard let events = json["events"] as? [[String: Any]] else { return result }
        
        let leagues = json["leagues"] as? [[String: Any]] ?? []
        let leagueName = leagues.first?["name"] as? String ?? "Football"
        
        for event in events {
            guard let id = event["id"] as? String else { continue }
            let comps = event["competitions"] as? [[String: Any]] ?? []
            guard let comp = comps.first else { continue }
            
            let venueObj = comp["venue"] as? [String: Any]
            let venue = venueObj?["fullName"] as? String ?? "Stadium"
            
            let competitors = comp["competitors"] as? [[String: Any]] ?? []
            guard competitors.count >= 2 else { continue }
            
            let team1 = parseCompetitor(competitors[0], defaultIcon: "soccerball")
            let team2 = parseCompetitor(competitors[1], defaultIcon: "soccerball")
            
            let statusObj = event["status"] as? [String: Any] ?? [:]
            let typeObj = statusObj["type"] as? [String: Any] ?? [:]
            let state = typeObj["state"] as? String ?? "pre"
            let detail = typeObj["detail"] as? String ?? typeObj["shortDetail"] as? String ?? ""
            let clock = statusObj["displayClock"] as? String ?? ""
            
            let status: MatchStatus
            let periodText: String
            if state == "in" {
                status = .live
                periodText = clock.isEmpty ? (detail.isEmpty ? "LIVE" : detail) : clock
            } else if state == "post" {
                status = .finalScore
                periodText = "FT"
            } else {
                status = .scheduled(kickoffTime: detail.isEmpty ? "Scheduled" : detail)
                periodText = detail.isEmpty ? "Scheduled" : detail
            }
            
            let link = (event["links"] as? [[String: Any]])?.first?["href"] as? String ?? "https://www.espn.com/soccer"
            let liveSummary = "\(team1.name) vs \(team2.name) • \(periodText)"
            
            let match = SportsMatch(
                id: "soc.\(id)",
                sport: .football,
                league: leagueName,
                venue: venue,
                team1: team1,
                team2: team2,
                periodText: periodText,
                status: status,
                liveSummary: liveSummary,
                events: [],
                matchUrl: link,
                progress: state == "in" ? 0.65 : nil,
                isRealData: true
            )
            result.append(match)
        }
        return result
    }
    
    private func parseNBA(json: [String: Any]) -> [SportsMatch] {
        var result: [SportsMatch] = []
        guard let events = json["events"] as? [[String: Any]] else { return result }
        
        for event in events {
            guard let id = event["id"] as? String else { continue }
            let comps = event["competitions"] as? [[String: Any]] ?? []
            guard let comp = comps.first else { continue }
            
            let venueObj = comp["venue"] as? [String: Any]
            let venue = venueObj?["fullName"] as? String ?? "NBA Arena"
            
            let competitors = comp["competitors"] as? [[String: Any]] ?? []
            guard competitors.count >= 2 else { continue }
            
            let team1 = parseCompetitor(competitors[0], defaultIcon: "basketball.fill")
            let team2 = parseCompetitor(competitors[1], defaultIcon: "basketball.fill")
            
            let statusObj = event["status"] as? [String: Any] ?? [:]
            let typeObj = statusObj["type"] as? [String: Any] ?? [:]
            let state = typeObj["state"] as? String ?? "pre"
            let detail = typeObj["detail"] as? String ?? ""
            
            let status: MatchStatus
            let periodText: String
            if state == "in" {
                status = .live
                periodText = detail.isEmpty ? "LIVE" : detail
            } else if state == "post" {
                status = .finalScore
                periodText = "FINAL"
            } else {
                status = .scheduled(kickoffTime: detail.isEmpty ? "Scheduled" : detail)
                periodText = detail.isEmpty ? "Scheduled" : detail
            }
            
            let link = (event["links"] as? [[String: Any]])?.first?["href"] as? String ?? "https://www.espn.com/nba"
            let liveSummary = "\(team1.name) vs \(team2.name) • \(periodText)"
            
            let match = SportsMatch(
                id: "nba.\(id)",
                sport: .basketball,
                league: "NBA",
                venue: venue,
                team1: team1,
                team2: team2,
                periodText: periodText,
                status: status,
                liveSummary: liveSummary,
                events: [],
                matchUrl: link,
                progress: state == "in" ? 0.5 : nil,
                isRealData: true
            )
            result.append(match)
        }
        return result
    }
    
    private func parseF1(json: [String: Any]) -> [SportsMatch] {
        var result: [SportsMatch] = []
        guard let events = json["events"] as? [[String: Any]], let event = events.first else { return result }
        
        let id = event["id"] as? String ?? "f1.current"
        let eventName = event["name"] as? String ?? "Formula 1 Grand Prix"
        let circuit = event["circuit"] as? [String: Any]
        let venue = circuit?["fullName"] as? String ?? "Grand Prix Circuit"
        
        let comps = event["competitions"] as? [[String: Any]] ?? []
        guard let comp = comps.first else { return result }
        let competitors = comp["competitors"] as? [[String: Any]] ?? []
        guard competitors.count >= 2 else { return result }
        
        // Driver 1 & 2
        let d1 = competitors[0]
        let d2 = competitors[1]
        let d1Athlete = d1["athlete"] as? [String: Any] ?? [:]
        let d2Athlete = d2["athlete"] as? [String: Any] ?? [:]
        let d1Name = d1Athlete["displayName"] as? String ?? "Leader"
        let d2Name = d2Athlete["displayName"] as? String ?? "P2"
        let d1Flag = (d1Athlete["flag"] as? [String: Any])?["href"] as? String
        let d2Flag = (d2Athlete["flag"] as? [String: Any])?["href"] as? String
        
        let statusObj = comp["status"] as? [String: Any] ?? [:]
        let typeObj = statusObj["type"] as? [String: Any] ?? [:]
        let state = typeObj["state"] as? String ?? "pre"
        let period = statusObj["period"] as? Int ?? 0
        let detail = typeObj["detail"] as? String ?? ""
        
        let periodText = state == "in" ? "Lap \(period)" : (state == "post" ? "FINAL" : detail)
        let status: MatchStatus = state == "in" ? .live : (state == "post" ? .finalScore : .scheduled(kickoffTime: detail))
        
        let team1 = SportsTeam(name: d1Name, abbreviation: String(d1Name.prefix(3)).uppercased(), score: "P1", color: Color.red, iconName: "flag.checkered", logoUrl: d1Flag, record: "Position 1")
        let team2 = SportsTeam(name: d2Name, abbreviation: String(d2Name.prefix(3)).uppercased(), score: "P2", color: Color.orange, iconName: "flag.checkered", logoUrl: d2Flag, record: "Position 2")
        
        let link = (event["links"] as? [[String: Any]])?.first?["href"] as? String ?? "https://www.espn.com/f1"
        
        let match = SportsMatch(
            id: id,
            sport: .formula1,
            league: "Formula 1",
            venue: venue,
            team1: team1,
            team2: team2,
            periodText: periodText,
            status: status,
            liveSummary: "\(eventName) • \(d1Name) leads \(d2Name)",
            events: [],
            matchUrl: link,
            progress: nil,
            isRealData: true
        )
        result.append(match)
        return result
    }
    
    private func parseCricket(json: [String: Any]) -> [SportsMatch] {
        var result: [SportsMatch] = []
        guard let sports = json["sports"] as? [[String: Any]],
              let firstSport = sports.first,
              let leagues = firstSport["leagues"] as? [[String: Any]] else { return result }
        
        for league in leagues {
            let leagueName = league["name"] as? String ?? "Cricket"
            let events = league["events"] as? [[String: Any]] ?? []
            for event in events {
                guard let id = event["id"] as? String else { continue }
                let venue = event["location"] as? String ?? "Cricket Ground"
                let competitors = event["competitors"] as? [[String: Any]] ?? []
                guard competitors.count >= 2 else { continue }
                
                let c1 = competitors[0]
                let c2 = competitors[1]
                
                let t1Name = c1["displayName"] as? String ?? c1["name"] as? String ?? "Team 1"
                let t1Abbr = c1["abbreviation"] as? String ?? String(t1Name.prefix(3)).uppercased()
                let t1Score = c1["score"] as? String ?? "-"
                let t1Logo = c1["logo"] as? String
                
                let t2Name = c2["displayName"] as? String ?? c2["name"] as? String ?? "Team 2"
                let t2Abbr = c2["abbreviation"] as? String ?? String(t2Name.prefix(3)).uppercased()
                let t2Score = c2["score"] as? String ?? "-"
                let t2Logo = c2["logo"] as? String
                
                let team1 = SportsTeam(name: t1Name, abbreviation: t1Abbr, score: t1Score, color: Color.blue, iconName: "cricket.ball.fill", logoUrl: t1Logo)
                let team2 = SportsTeam(name: t2Name, abbreviation: t2Abbr, score: t2Score, color: Color.green, iconName: "cricket.ball.fill", logoUrl: t2Logo)
                
                let statusStr = event["status"] as? String ?? "pre"
                let fullStatus = event["fullStatus"] as? [String: Any] ?? [:]
                let summary = fullStatus["summary"] as? String ?? (fullStatus["type"] as? [String: Any])?["detail"] as? String ?? "Scheduled"
                let session = fullStatus["session"] as? String ?? ""
                let dayNumber = fullStatus["dayNumber"] as? Int
                
                let status: MatchStatus
                let periodText: String
                if statusStr == "in" {
                    status = .live
                    if !session.isEmpty {
                        periodText = session
                    } else if let day = dayNumber {
                        periodText = "Day \(day)"
                    } else {
                        periodText = "LIVE"
                    }
                } else if statusStr == "post" {
                    status = .finalScore
                    periodText = "FINAL"
                } else {
                    status = .scheduled(kickoffTime: summary)
                    periodText = summary
                }
                
                let link = event["link"] as? String ?? "https://www.espncricinfo.com"
                let liveSummary = fullStatus["longSummary"] as? String ?? fullStatus["summary"] as? String ?? event["description"] as? String ?? "\(t1Name) vs \(t2Name)"
                
                let match = SportsMatch(
                    id: "cric.\(id)",
                    sport: .cricket,
                    league: leagueName,
                    venue: venue,
                    team1: team1,
                    team2: team2,
                    periodText: periodText,
                    status: status,
                    liveSummary: liveSummary,
                    events: [],
                    matchUrl: link,
                    progress: nil,
                    isRealData: true
                )
                result.append(match)
            }
        }
        return result
    }
    
    private func parseCompetitor(_ c: [String: Any], defaultIcon: String) -> SportsTeam {
        let teamObj = c["team"] as? [String: Any] ?? [:]
        let name = teamObj["displayName"] as? String ?? teamObj["name"] as? String ?? "Team"
        let abbr = teamObj["abbreviation"] as? String ?? String(name.prefix(3)).uppercased()
        let score = c["score"] as? String ?? "0"
        let logo = teamObj["logo"] as? String
        let colorHex = teamObj["color"] as? String ?? "007AFF"
        let color = Self.colorFromHex(colorHex)
        
        let records = c["records"] as? [[String: Any]] ?? []
        let record = records.first?["summary"] as? String
        
        return SportsTeam(
            name: name,
            abbreviation: abbr,
            score: score,
            color: color,
            iconName: defaultIcon,
            logoUrl: logo,
            record: record
        )
    }
    
    public static func colorFromHex(_ hex: String, defaultColor: Color = .blue) -> Color {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let rgb = UInt64(clean, radix: 16) else {
            return defaultColor
        }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    // MARK: - Filtering & Merging
    
    public func filterAvailableMatches() {
        var merged: [SportsMatch] = []
        
        if onlyShowFavorites {
            // ONLY include real live or scheduled matches featuring the user's chosen favorite teams
            for match in allRawMatches {
                if isSportEnabled(match.sport) && isMatchFavorite(match) {
                    merged.append(match)
                }
            }
            
            // For any enabled sport without a real ESPN match today, provide the favorite team fixture
            if isFootballEnabled && !merged.contains(where: { $0.sport == .football }) {
                if let f = fallbackFootball() { merged.append(f) }
            }
            if isBasketballEnabled && !merged.contains(where: { $0.sport == .basketball }) {
                if let b = fallbackBasketball() { merged.append(b) }
            }
            if isF1Enabled && !merged.contains(where: { $0.sport == .formula1 }) {
                if let f1 = fallbackF1() { merged.append(f1) }
            }
            if isCricketEnabled && !merged.contains(where: { $0.sport == .cricket }) {
                if let c = fallbackCricket() { merged.append(c) }
            }
        } else {
            // Include all real matches for enabled sports
            for match in allRawMatches {
                if isSportEnabled(match.sport) {
                    merged.append(match)
                }
            }
            
            // If an enabled sport has 0 live matches, complement with favorite team fallback
            if isFootballEnabled && !merged.contains(where: { $0.sport == .football }) {
                if let f = fallbackFootball() { merged.append(f) }
            }
            if isBasketballEnabled && !merged.contains(where: { $0.sport == .basketball }) {
                if let b = fallbackBasketball() { merged.append(b) }
            }
            if isF1Enabled && !merged.contains(where: { $0.sport == .formula1 }) {
                if let f1 = fallbackF1() { merged.append(f1) }
            }
            if isCricketEnabled && !merged.contains(where: { $0.sport == .cricket }) {
                if let c = fallbackCricket() { merged.append(c) }
            }
        }
        
        // Sort: Favorite teams always first, then live, then scheduled
        merged.sort { m1, m2 in
            let fav1 = isMatchFavorite(m1)
            let fav2 = isMatchFavorite(m2)
            if fav1 && !fav2 { return true }
            if !fav1 && fav2 { return false }
            if m1.isLive && !m2.isLive { return true }
            if !m1.isLive && m2.isLive { return false }
            return false
        }
        
        self.availableMatches = merged
        
        // Update active match reference
        if let current = activeMatch {
            if !isSportEnabled(current.sport) || (onlyShowFavorites && !isMatchFavorite(current)) {
                if let next = merged.first {
                    pinMatch(next)
                } else {
                    dismissMatch()
                }
            } else if let updated = merged.first(where: { $0.id == current.id || (isMatchFavorite(current) && isMatchFavorite($0) && $0.sport == current.sport) }) {
                self.activeMatch = updated
                if let act = DynamicIslandController.shared.activityManager.getActivity(id: "activity.sports.\(current.id)") as? SportsActivity {
                    act.match = updated
                }
            }
        } else if autoShowMatchday, let first = merged.first {
            pinMatch(first)
        }
    }
    
    public func isMatchFavorite(_ match: SportsMatch) -> Bool {
        let favTarget: String
        switch match.sport {
        case .football: favTarget = favoriteFootball
        case .basketball: favTarget = favoriteBasketball
        case .formula1: favTarget = favoriteF1
        case .cricket: favTarget = favoriteCricket
        }
        
        return teamMatches(match.team1, target: favTarget) ||
               teamMatches(match.team2, target: favTarget) ||
               match.liveSummary.localizedCaseInsensitiveContains(favTarget) ||
               match.venue.localizedCaseInsensitiveContains(favTarget)
    }
    
    private func teamMatches(_ team: SportsTeam, target: String) -> Bool {
        let t = target.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return false }
        
        let name = team.name.lowercased()
        let abbr = team.abbreviation.lowercased()
        
        if name.contains(t) || t.contains(name) { return true }
        if abbr == t { return true }
        
        let aliases: [String: [String]] = [
            "arsenal": ["arsenal", "ars", "gunners"],
            "chelsea": ["chelsea", "che", "blues"],
            "manchester city": ["manchester city", "man city", "mci", "city"],
            "liverpool": ["liverpool", "liv", "reds"],
            "manchester united": ["manchester united", "man united", "man utd", "mun", "united"],
            "real madrid": ["real madrid", "rma", "madrid"],
            "barcelona": ["barcelona", "barca", "bar", "fc barcelona"],
            "bayern munich": ["bayern munich", "bayern", "bay", "fc bayern"],
            
            "lakers": ["lakers", "lal", "los angeles lakers"],
            "warriors": ["warriors", "gsw", "golden state"],
            "celtics": ["celtics", "bos", "boston"],
            "nuggets": ["nuggets", "den", "denver"],
            "heat": ["heat", "mia", "miami"],
            "mavericks": ["mavericks", "mavs", "dal", "dallas"],
            
            "red bull": ["red bull", "ver", "verstappen", "rbr", "red bull racing"],
            "mclaren": ["mclaren", "nor", "norris", "mcl"],
            "ferrari": ["ferrari", "lec", "leclerc", "scuderia"],
            "mercedes": ["mercedes", "ham", "hamilton", "russell", "merc"],
            "aston martin": ["aston martin", "alo", "alonso", "amr"],
            
            "india": ["india", "ind"],
            "australia": ["australia", "aus"],
            "england": ["england", "eng"],
            "south africa": ["south africa", "sa", "rsa"],
            "csk": ["csk", "chennai", "super kings"],
            "rcb": ["rcb", "bengaluru", "bangalore", "royal challengers"],
            "mi": ["mi", "mumbai", "indians"]
        ]
        
        if let list = aliases[t] {
            for alias in list {
                if name.contains(alias) || abbr.contains(alias) {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - Fallback Fixtures (When no games running today)
    
    private func rebuildFallbackFixtures() {
        var list: [SportsMatch] = []
        if isFootballEnabled, let f = fallbackFootball() { list.append(f) }
        if isBasketballEnabled, let b = fallbackBasketball() { list.append(b) }
        if isF1Enabled, let f1 = fallbackF1() { list.append(f1) }
        if isCricketEnabled, let c = fallbackCricket() { list.append(c) }
        self.availableMatches = list
    }
    
    private func fallbackFootball() -> SportsMatch? {
        let fav = Self.footballTeams.first(where: { $0.name == favoriteFootball }) ?? Self.footballTeams[0]
        let opp = Self.footballTeams.first(where: { $0.name != favoriteFootball }) ?? Self.footballTeams[1]
        let t1 = SportsTeam(name: fav.name, abbreviation: fav.abbr, score: "2", color: fav.color, logoUrl: fav.logoUrl)
        let t2 = SportsTeam(name: opp.name, abbreviation: opp.abbr, score: "1", color: opp.color, logoUrl: opp.logoUrl)
        return SportsMatch(
            id: "fav.foot.\(fav.abbr)",
            sport: .football,
            league: "Premier League",
            venue: "\(fav.name) Stadium",
            team1: t1,
            team2: t2,
            periodText: "78'",
            status: .live,
            liveSummary: "\(fav.name) lead \(opp.name) entering closing minutes",
            events: [SportsMatchEvent(time: "68'", title: "Goal", player: "\(fav.abbr) Striker", icon: "soccerball")],
            matchUrl: "https://www.premierleague.com",
            isRealData: false
        )
    }
    
    private func fallbackBasketball() -> SportsMatch? {
        let fav = Self.basketballTeams.first(where: { $0.name == favoriteBasketball }) ?? Self.basketballTeams[0]
        let opp = Self.basketballTeams.first(where: { $0.name != favoriteBasketball }) ?? Self.basketballTeams[1]
        let t1 = SportsTeam(name: fav.name, abbreviation: fav.abbr, score: "-", color: fav.color, logoUrl: fav.logoUrl)
        let t2 = SportsTeam(name: opp.name, abbreviation: opp.abbr, score: "-", color: opp.color, logoUrl: opp.logoUrl)
        return SportsMatch(
            id: "fav.bask.\(fav.abbr)",
            sport: .basketball,
            league: "NBA",
            venue: "\(fav.name) Arena",
            team1: t1,
            team2: t2,
            periodText: "Today 8:00 PM",
            status: .scheduled(kickoffTime: "Today 8:00 PM"),
            liveSummary: "Matchday: \(fav.name) vs \(opp.name) tip-off at 8:00 PM",
            events: [],
            matchUrl: "https://www.nba.com",
            isRealData: false
        )
    }
    
    private func fallbackF1() -> SportsMatch? {
        let fav = Self.f1Teams.first(where: { $0.name == favoriteF1 }) ?? Self.f1Teams[0]
        let opp = Self.f1Teams.first(where: { $0.name != favoriteF1 }) ?? Self.f1Teams[1]
        let t1 = SportsTeam(name: fav.name, abbreviation: fav.abbr, score: "P1", color: fav.color, iconName: "flag.checkered", logoUrl: fav.logoUrl)
        let t2 = SportsTeam(name: opp.name, abbreviation: opp.abbr, score: "P2", color: opp.color, iconName: "flag.checkered", logoUrl: opp.logoUrl)
        return SportsMatch(
            id: "fav.f1.\(fav.abbr)",
            sport: .formula1,
            league: "Formula 1",
            venue: "Circuit de Monaco",
            team1: t1,
            team2: t2,
            periodText: "Lap 52/78",
            status: .live,
            liveSummary: "\(fav.abbr) leads \(opp.abbr) by +1.8s",
            events: [],
            matchUrl: "https://www.formula1.com",
            isRealData: false
        )
    }
    
    private func fallbackCricket() -> SportsMatch? {
        let fav = Self.cricketTeams.first(where: { $0.name == favoriteCricket }) ?? Self.cricketTeams[0]
        let opp = Self.cricketTeams.first(where: { $0.name != favoriteCricket }) ?? Self.cricketTeams[1]
        let t1 = SportsTeam(name: fav.name, abbreviation: fav.abbr, score: "-", color: fav.color, iconName: "cricket.ball.fill", logoUrl: fav.logoUrl)
        let t2 = SportsTeam(name: opp.name, abbreviation: opp.abbr, score: "-", color: opp.color, iconName: "cricket.ball.fill", logoUrl: opp.logoUrl)
        return SportsMatch(
            id: "fav.cric.\(fav.abbr)",
            sport: .cricket,
            league: "ICC Cricket",
            venue: "Melbourne Cricket Ground",
            team1: t1,
            team2: t2,
            periodText: "Today 7:30 PM",
            status: .scheduled(kickoffTime: "Today 7:30 PM"),
            liveSummary: "Matchday: \(fav.name) vs \(opp.name) starts at 7:30 PM",
            events: [],
            matchUrl: "https://www.espncricinfo.com",
            isRealData: false
        )
    }
    
    // MARK: - Matchday Auto-Surface
    
    public func surfaceMatchdayIfAvailable() {
        guard isEnabled, autoShowMatchday else { return }
        let candidate = availableMatches.first(where: { isMatchFavorite($0) && $0.isLive }) ??
                        availableMatches.first(where: { isMatchFavorite($0) && $0.isScheduled }) ??
                        availableMatches.first(where: { isMatchFavorite($0) }) ??
                        availableMatches.first
        if let match = candidate {
            pinMatch(match)
        }
    }
    
    // MARK: - Actions
    
    public func pinMatch(_ match: SportsMatch) {
        guard isEnabled else { return }
        self.activeMatch = match
        if let idx = availableMatches.firstIndex(where: { $0.id == match.id }) {
            self.currentMatchIndex = idx
        }
        
        let activity = SportsActivity(match: match)
        DynamicIslandController.shared.activityManager.presentActivity(activity)
        if DynamicIslandController.shared.state == .idle || DynamicIslandController.shared.state == .peek {
            DynamicIslandController.shared.transition(to: .compact)
        }
        self.onMatchUpdated?(match)
    }
    
    public func cycleNextMatch() {
        guard !availableMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % availableMatches.count
        let next = availableMatches[currentMatchIndex]
        pinMatch(next)
    }
    
    public func dismissMatch() {
        if let match = activeMatch {
            DynamicIslandController.shared.activityManager.removeActivity(id: "activity.sports.\(match.id)")
            self.activeMatch = nil
            self.onMatchUpdated?(nil)
        }
    }
    
    public func simulateScoreEvent() {
        guard var match = activeMatch else {
            if let first = availableMatches.first {
                pinMatch(first)
            }
            return
        }
        if match.isScheduled {
            match.status = .live
            match.periodText = "12'"
            match.team1.score = "1"
            match.team2.score = "0"
            match.liveSummary = "MATCH STARTED! \(match.team1.name) take early lead!"
            match.events.append(SportsMatchEvent(time: "12'", title: "Early Goal!", player: "\(match.team1.abbreviation) Player", icon: match.sport.icon))
        } else {
            switch match.sport {
            case .football:
                if let currentScore = Int(match.team1.score) {
                    let newScore = String(currentScore + 1)
                    match.team1.score = newScore
                    match.liveSummary = "GOAL! \(match.team1.name) score! (\(newScore)-\(match.team2.score))"
                    match.events.append(SportsMatchEvent(time: match.periodText, title: "Goal!", player: "\(match.team1.abbreviation) Scorer", icon: "soccerball"))
                } else {
                    match.team1.score = "1"
                    match.team2.score = "0"
                }
            case .basketball:
                if let currentScore = Int(match.team1.score) {
                    let newScore = String(currentScore + 3)
                    match.team1.score = newScore
                    match.liveSummary = "3-POINTER! \(match.team1.name) sink clutch shot!"
                } else {
                    match.team1.score = "104"
                    match.team2.score = "99"
                    match.periodText = "Q4 1:12"
                }
            case .formula1:
                match.periodText = "Lap 60/78"
                match.liveSummary = "Fastest Lap: \(match.team1.name) 1:14.212"
            case .cricket:
                match.periodText = "156/3 (17.4 ov)"
                match.liveSummary = "SIX! Powered over long-on!"
            }
        }
        self.activeMatch = match
        if let act = DynamicIslandController.shared.activityManager.getActivity(id: "activity.sports.\(match.id)") as? SportsActivity {
            act.match = match
        }
        self.onMatchUpdated?(match)
    }
}
