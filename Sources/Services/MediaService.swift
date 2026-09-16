import Foundation
import AppKit
import Combine
import CoreAudio

public struct MediaTrackInfo: Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var duration: TimeInterval
    public var elapsedTime: TimeInterval
    public var artwork: NSImage?
    public var artworkUrl: String?
    public var sourceApp: String
    public var isTabVisibleOnScreen: Bool
    
    public init(
        title: String = "Not Playing",
        artist: String = "No Artist",
        album: String = "",
        isPlaying: Bool = false,
        duration: TimeInterval = 180,
        elapsedTime: TimeInterval = 0,
        artwork: NSImage? = nil,
        artworkUrl: String? = nil,
        sourceApp: String = "Spotify",
        isTabVisibleOnScreen: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.elapsedTime = elapsedTime
        self.artwork = artwork
        self.artworkUrl = artworkUrl
        self.sourceApp = sourceApp
        self.isTabVisibleOnScreen = isTabVisibleOnScreen
    }
}

/// Service managing macOS media detection, album artwork download, and direct PID media controls for Spotify, Apple Music, and Chrome YouTube.
public final class MediaService: ObservableObject {
    public static let shared = MediaService()
    
    @Published public private(set) var currentTrack: MediaTrackInfo = MediaTrackInfo()
    @Published public private(set) var isPlaybackActive: Bool = false
    
    private var observers: [NSObjectProtocol] = []
    private var syncTimer: Timer?
    private var artworkCache: [String: NSImage] = [:]
    private var youtubeDurationCache: [String: TimeInterval] = [:]

    
    private var lastActiveChromeTabId: String? = nil
    private var isSyncing: Bool = false
    
    private init() {
        setupDistributedObservers()
        checkActiveMediaOnLaunch()
        
        // Polling sync timer (every 0.8s) for real-time track updates
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.checkActiveMediaOnLaunch()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.syncTimer = timer
    }
    
    deinit {
        syncTimer?.invalidate()
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
    
    private func setupDistributedObservers() {
        let center = DistributedNotificationCenter.default()
        
        let spotifyNames = [
            "com.spotify.client.PlaybackStateChanged",
            "com.spotify.client.playbackStateChanged"
        ]
        
        for name in spotifyNames {
            let obs = center.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.checkActiveMediaOnLaunch()
            }
            observers.append(obs)
        }
        
        let appleMusicNames = [
            "com.apple.Music.playerInfo",
            "com.apple.iTunes.playerInfo"
        ]
        
        for name in appleMusicNames {
            let obs = center.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.checkActiveMediaOnLaunch()
            }
            observers.append(obs)
        }
        
        let wsCenter = NSWorkspace.shared.notificationCenter
        let appActiveObs = wsCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkActiveMediaOnLaunch()
        }
        observers.append(appActiveObs)
        
        let appDeactiveObs = wsCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkActiveMediaOnLaunch()
        }
        observers.append(appDeactiveObs)
    }
    
    public func checkActiveMediaOnLaunch() {
        guard !isSyncing else { return }
        isSyncing = true
        
        let apps = NSWorkspace.shared.runningApplications
        let isSpotifyRunning = apps.contains { $0.bundleIdentifier == "com.spotify.client" }
        let isMusicRunning = apps.contains { $0.bundleIdentifier == "com.apple.Music" }
        let isChromeRunning = apps.contains { $0.bundleIdentifier == "com.google.Chrome" }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            defer { self.isSyncing = false }
            
            // 1. Check Spotify first (fast check)
            if isSpotifyRunning, let spotTrack = self.querySpotifyDirectly() {
                if spotTrack.isPlaying {
                    DispatchQueue.main.async {
                        self.updateTrackState(spotTrack)
                    }
                    return
                }
            }
            
            // 2. Check Apple Music (fast check)
            if isMusicRunning, let musicTrack = self.queryAppleMusicDirectly() {
                if musicTrack.isPlaying {
                    DispatchQueue.main.async {
                        self.updateTrackState(musicTrack)
                    }
                    return
                }
            }
            
            // 3. Check Google Chrome (YouTube, JioHotstar, Netflix)
            if isChromeRunning, let chromeTrack = self.queryChromeMediaDirectly() {
                if chromeTrack.isPlaying {
                    DispatchQueue.main.async {
                        self.updateTrackState(chromeTrack)
                    }
                    return
                } else if ["YouTube", "Netflix", "JioHotstar", "JioCinema"].contains(self.currentTrack.sourceApp) {
                    DispatchQueue.main.async {
                        self.updateTrackState(chromeTrack)
                    }
                    return
                }
            }
            
            // 4. Nothing active
            if self.isPlaybackActive {
                DispatchQueue.main.async {
                    self.isPlaybackActive = false
                    self.currentTrack.isPlaying = false
                }
            }
        }
    }
    
    private func updateTrackState(_ newTrack: MediaTrackInfo) {
        let isHttpUrl = newTrack.artworkUrl?.starts(with: "http") == true
        let shouldFetchArtwork = (isHttpUrl && newTrack.artworkUrl != self.currentTrack.artworkUrl) || (self.currentTrack.artwork == nil && isHttpUrl)
        
        var trackToSet = newTrack
        if let key = newTrack.artworkUrl, let cached = artworkCache[key] {
            trackToSet.artwork = cached
        } else if let directArt = newTrack.artwork {
            trackToSet.artwork = directArt
            if let key = newTrack.artworkUrl {
                artworkCache[key] = directArt
            }
        }
        
        self.currentTrack = trackToSet
        self.isPlaybackActive = trackToSet.isPlaying
        
        if shouldFetchArtwork, let urlString = newTrack.artworkUrl, let url = URL(string: urlString) {
            downloadArtwork(from: url, forUrlKey: urlString)
        }
    }
    
    private func downloadArtwork(from url: URL, forUrlKey: String) {
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, let image = NSImage(data: data) else { return }
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.artworkCache[forUrlKey] = image
                if self.currentTrack.artworkUrl == forUrlKey || self.currentTrack.artwork == nil {
                    var updated = self.currentTrack
                    updated.artwork = image
                    self.currentTrack = updated
                }
            }
        }.resume()
    }
    
    private func fetchYouTubeDuration(videoID: String) {
        guard youtubeDurationCache[videoID] == nil else { return }
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else { return }
        
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self, let data = data, let str = String(data: data, encoding: .utf8) else { return }
            
            var durationSecs: Double? = nil
            if let range = str.range(of: "\"lengthSeconds\":\"") {
                let sub = str[range.upperBound...]
                if let endRange = sub.range(of: "\"") {
                    let secondsStr = String(sub[..<endRange.lowerBound])
                    durationSecs = Double(secondsStr)
                }
            } else if let range = str.range(of: "\"approxDurationMs\":\"") {
                let sub = str[range.upperBound...]
                if let endRange = sub.range(of: "\"") {
                    let msStr = String(sub[..<endRange.lowerBound])
                    if let msNum = Double(msStr) {
                        durationSecs = msNum / 1000
                    }
                }
            }
            
            if let duration = durationSecs, duration > 0 {
                DispatchQueue.main.async {
                    self.youtubeDurationCache[videoID] = duration
                    if self.currentTrack.sourceApp == "YouTube" && self.currentTrack.duration != duration {
                        var updated = self.currentTrack
                        updated.duration = duration
                        self.currentTrack = updated
                    }
                }
            }
        }.resume()
    }
    
    private func querySpotifyDirectly() -> MediaTrackInfo? {
        let script = """
        tell application "Spotify"
            set pState to player state as string
            set isPlay to (pState is "playing")
            if not isPlay then
                return "|||||||||false|||0|||0|||"
            end if
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDuration to (duration of current track) / 1000
            set tPosition to player position
            set tArt to ""
            try
                set tArt to artwork url of current track
            end try
            return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (isPlay as string) & "|||" & (tDuration as string) & "|||" & (tPosition as string) & "|||" & tArt
        end tell
        """
        
        guard let output = executeAppleScript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }
        
        let isPlaying = parts[3].lowercased().contains("true")
        if !isPlaying { return nil }
        
        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        
        let artUrl = parts.count >= 7 ? parts[6].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let exactDuration = Double(parts[4]) ?? 180
        let exactElapsedTime = Double(parts[5]) ?? 0
        
        return MediaTrackInfo(
            title: title,
            artist: parts[1].trimmingCharacters(in: .whitespacesAndNewlines),
            album: parts[2].trimmingCharacters(in: .whitespacesAndNewlines),
            isPlaying: isPlaying,
            duration: exactDuration,
            elapsedTime: exactElapsedTime,
            artwork: nil,
            artworkUrl: artUrl?.isEmpty == false ? artUrl : nil,
            sourceApp: "Spotify"
        )
    }
    
    private func queryAppleMusicDirectly() -> MediaTrackInfo? {
        let script = """
        tell application "Music"
            set pState to player state as string
            set isPlay to (pState is "playing")
            if not isPlay then
                return "|||||||||false|||0|||0"
            end if
            set tName to name of current track
            set tArtist to artist of current track
            set tAlbum to album of current track
            set tDuration to duration of current track
            set tPosition to player position
            return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & (isPlay as string) & "|||" & (tDuration as string) & "|||" & (tPosition as string)
        end tell
        """
        
        guard let output = executeAppleScript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "|||")
        guard parts.count >= 6 else { return nil }
        
        let isPlaying = parts[3].lowercased().contains("true")
        if !isPlaying { return nil }
        
        let title = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        
        let artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let album = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        let exactDuration = Double(parts[4]) ?? 180
        let exactElapsedTime = Double(parts[5]) ?? 0
        
        let trackKey = "apple_music:\(title):\(artist):\(album)"
        var trackArtwork: NSImage? = artworkCache[trackKey]
        
        if trackArtwork == nil {
            if let directArt = fetchAppleMusicArtwork() {
                artworkCache[trackKey] = directArt
                trackArtwork = directArt
            } else {
                searchiTunesArtwork(title: title, artist: artist, album: album, cacheKey: trackKey)
            }
        }
        
        return MediaTrackInfo(
            title: title,
            artist: artist,
            album: album,
            isPlaying: isPlaying,
            duration: exactDuration,
            elapsedTime: exactElapsedTime,
            artwork: trackArtwork,
            artworkUrl: trackKey,
            sourceApp: "Apple Music"
        )
    }
    
    private func fetchAppleMusicArtwork() -> NSImage? {
        let script = """
        tell application "Music"
            tell current track
                if (count of artworks) > 0 then
                    return raw data of artwork 1
                end if
            end tell
        end tell
        return ""
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            let descriptor = appleScript.executeAndReturnError(&error)
            if error == nil {
                let data = descriptor.data
                if !data.isEmpty, let image = NSImage(data: data) {
                    return image
                }
            }
        }
        return nil
    }
    
    private func searchiTunesArtwork(title: String, artist: String, album: String, cacheKey: String) {
        guard !title.isEmpty else { return }
        let cleanTitle = title.components(separatedBy: " (feat.")[0].components(separatedBy: " [feat.")[0]
        let query = "\(cleanTitle) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=1") else {
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let results = json["results"] as? [[String: Any]],
                   let first = results.first,
                   let artUrl100 = first["artworkUrl100"] as? String {
                    let highRes = artUrl100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
                    if let artUrl = URL(string: highRes) {
                        self.downloadArtwork(from: artUrl, forUrlKey: cacheKey)
                    }
                }
            } catch {}
        }.resume()
    }
    
    private func isSystemAudioPlaying() -> Bool {
        // 1. Check default output device
        var defaultOutputDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil, &propertySize, &defaultOutputDeviceID) == noErr, defaultOutputDeviceID != 0 {
            var isRunning: UInt32 = 0
            var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
            var isRunningAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(defaultOutputDeviceID, &isRunningAddr, 0, nil, &isRunningSize, &isRunning) == noErr, isRunning != 0 {
                return true
            }
        }
        
        // 2. Check all audio devices to catch Bluetooth, AirPods, HDMI, etc.
        var propSize: UInt32 = 0
        var allDevsAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &allDevsAddr, 0, nil, &propSize) == noErr {
            let count = Int(propSize / UInt32(MemoryLayout<AudioDeviceID>.size))
            var devices = [AudioDeviceID](repeating: 0, count: count)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &allDevsAddr, 0, nil, &propSize, &devices) == noErr {
                for dev in devices {
                    var runningSomewhere: UInt32 = 0
                    var rSize = UInt32(MemoryLayout<UInt32>.size)
                    var rAddr = AudioObjectPropertyAddress(
                        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                        mScope: kAudioObjectPropertyScopeGlobal,
                        mElement: kAudioObjectPropertyElementMain
                    )
                    if AudioObjectGetPropertyData(dev, &rAddr, 0, nil, &rSize, &runningSomewhere) == noErr, runningSomewhere != 0 {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    private struct ChromeTabCandidate {
        let tabId: String
        let title: String
        let url: String
        let isFrontWindow: Bool
        let isActiveTab: Bool
        let isMinimized: Bool
        let jsState: String
    }
    
    private func queryChromeMediaDirectly() -> MediaTrackInfo? {
        let script = """
        tell application "Google Chrome"
            set foundTabs to {}
            set frontWinId to -1
            try
                set frontWinId to id of front window
            end try
            repeat with w in windows
                set wId to id of w
                set isFW to (wId is frontWinId)
                set isMin to false
                try
                    set isMin to miniaturized of w
                end try
                set activeTabId to -1
                try
                    set activeTabId to id of (active tab of w)
                end try
                repeat with t in tabs of w
                    set tUrl to URL of t
                    set isMedia to false
                    if (tUrl starts with "https://www.youtube.com/" or tUrl starts with "https://youtube.com/" or tUrl starts with "https://m.youtube.com/" or tUrl starts with "https://music.youtube.com/" or tUrl starts with "https://youtu.be/" or tUrl starts with "http://www.youtube.com/" or tUrl starts with "http://youtube.com/") then
                        set isMedia to true
                    else if (tUrl starts with "https://www.netflix.com/" or tUrl starts with "https://netflix.com/") then
                        set isMedia to true
                    else if (tUrl starts with "https://www.hotstar.com/" or tUrl starts with "https://hotstar.com/" or tUrl starts with "https://www.jiocinema.com/" or tUrl starts with "https://jiocinema.com/" or tUrl starts with "https://www.jiostar.com/" or tUrl starts with "https://jiostar.com/") then
                        set isMedia to true
                    end if
                    if isMedia then
                        set tId to id of t
                        set tTitle to title of t
                        set isAct to (tId is activeTabId)
                        set jsState to "UNKNOWN"
                        try
                            set jsState to execute t javascript "(function(){
                                var vs = document.querySelectorAll('video');
                                if (!vs || vs.length === 0) return 'NO_VIDEO';
                                var chosen = null;
                                for (var i = 0; i < vs.length; i++) {
                                    var v = vs[i];
                                    if (!v.paused && !v.ended && v.readyState >= 2) {
                                        chosen = v;
                                        break;
                                    }
                                }
                                if (!chosen) {
                                    chosen = document.querySelector('video.html5-main-video') || vs[0];
                                }
                                var isP = (!chosen.paused && !chosen.ended && chosen.readyState >= 2);
                                var cur = Math.floor(chosen.currentTime || 0);
                                var dur = Math.floor(chosen.duration || 0);
                                var art = '';
                                var metas = document.getElementsByTagName('meta');
                                for (var m = 0; m < metas.length; m++) {
                                    var prop = metas[m].getAttribute('property') || metas[m].getAttribute('name');
                                    if (prop === 'og:image' || prop === 'og:image:secure_url' || prop === 'twitter:image') {
                                        var c = metas[m].getAttribute('content');
                                        if (c && c.indexOf('http') === 0 && !c.includes('netflix_logo') && !c.includes('icon')) {
                                            art = c;
                                            break;
                                        }
                                    }
                                }
                                if (!art && chosen && chosen.poster && chosen.poster.indexOf('http') === 0) {
                                    art = chosen.poster;
                                }
                                if (!art) {
                                    var nflxImg = document.querySelector('.watch-video--player-view img, .ptrack-content img, .evidence-overlay img, .nf-billboard-row img');
                                    if (nflxImg && nflxImg.src && nflxImg.src.indexOf('http') === 0) {
                                        art = nflxImg.src;
                                    }
                                }
                                return (isP ? 'PLAYING' : 'PAUSED') + '|||' + cur + '|||' + dur + '|||' + encodeURIComponent(art);
                            })()"
                        end try
                        set tabItem to (tId as string) & "<FIELD>" & tTitle & "<FIELD>" & tUrl & "<FIELD>" & (isFW as string) & "<FIELD>" & (isAct as string) & "<FIELD>" & (isMin as string) & "<FIELD>" & jsState
                        copy tabItem to end of foundTabs
                    end if
                end repeat
            end repeat
            set AppleScript's text item delimiters to "<RECORD>"
            return foundTabs as string
        end tell
        """
        
        guard let output = executeAppleScript(script), !output.isEmpty else {
            lastActiveChromeTabId = nil
            return nil
        }
        
        let recordStrings = output.components(separatedBy: "<RECORD>")
        var candidates: [ChromeTabCandidate] = []
        
        for rec in recordStrings {
            let parts = rec.components(separatedBy: "<FIELD>")
            guard parts.count >= 7 else { continue }
            let tabId = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let url = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let isFW = parts[3].lowercased().contains("true")
            let isAct = parts[4].lowercased().contains("true")
            let isMin = parts[5].lowercased().contains("true")
            let jsState = parts[6].trimmingCharacters(in: .whitespacesAndNewlines)
            
            candidates.append(ChromeTabCandidate(
                tabId: tabId,
                title: title,
                url: url,
                isFrontWindow: isFW,
                isActiveTab: isAct,
                isMinimized: isMin,
                jsState: jsState
            ))
        }
        
        guard !candidates.isEmpty else {
            lastActiveChromeTabId = nil
            return nil
        }
        
        let selectedCandidate: ChromeTabCandidate
        if let playingCandidate = candidates.first(where: { $0.jsState.starts(with: "PLAYING") }) {
            selectedCandidate = playingCandidate
        } else if let lastId = lastActiveChromeTabId, let lastCandidate = candidates.first(where: { $0.tabId == lastId }) {
            selectedCandidate = lastCandidate
        } else if let frontActive = candidates.first(where: { $0.isFrontWindow && $0.isActiveTab }) {
            selectedCandidate = frontActive
        } else if let activeTab = candidates.first(where: { $0.isActiveTab }) {
            selectedCandidate = activeTab
        } else {
            selectedCandidate = candidates[0]
        }
        
        self.lastActiveChromeTabId = selectedCandidate.tabId
        return parseChromeMediaInfo(from: selectedCandidate)
    }
    
    private func parseChromeMediaInfo(from candidate: ChromeTabCandidate) -> MediaTrackInfo {
        let urlLower = candidate.url.lowercased()
        var sourceApp = "YouTube"
        var artist = "YouTube"
        var cleanTitle = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if urlLower.contains("netflix.com") {
            sourceApp = "Netflix"
            artist = "Netflix"
            
            cleanTitle = cleanTitle
                .replacingOccurrences(of: "Netflix - ", with: "")
                .replacingOccurrences(of: " - Netflix", with: "")
                .replacingOccurrences(of: " | Netflix", with: "")
                .replacingOccurrences(of: "Watch ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanTitle.isEmpty {
                cleanTitle = "Netflix Video"
            }
        } else if urlLower.contains("hotstar.com") || urlLower.contains("jiocinema.com") || urlLower.contains("jiostar.com") {
            let isJioCinema = urlLower.contains("jiocinema.com")
            sourceApp = isJioCinema ? "JioCinema" : "JioHotstar"
            artist = sourceApp
            
            cleanTitle = cleanTitle
                .replacingOccurrences(of: " - JioHotstar", with: "")
                .replacingOccurrences(of: " - Hotstar", with: "")
                .replacingOccurrences(of: " - Disney+ Hotstar", with: "")
                .replacingOccurrences(of: " - JioCinema", with: "")
                .replacingOccurrences(of: " on JioHotstar", with: "")
                .replacingOccurrences(of: "Watch ", with: "")
                .replacingOccurrences(of: " Online", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanTitle.isEmpty {
                cleanTitle = "\(sourceApp) Video"
            }
        } else {
            sourceApp = "YouTube"
            artist = "YouTube"
            
            // Clean notification counters e.g. "(15) "
            if let regex = try? NSRegularExpression(pattern: "^\\(\\d+\\+?\\)\\s*") {
                let range = NSRange(location: 0, length: cleanTitle.utf16.count)
                cleanTitle = regex.stringByReplacingMatches(in: cleanTitle, options: [], range: range, withTemplate: "")
            }
            if cleanTitle.hasPrefix("▶ ") {
                cleanTitle = String(cleanTitle.dropFirst(2))
            } else if cleanTitle.hasPrefix("▶") {
                cleanTitle = String(cleanTitle.dropFirst(1)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cleanTitle.hasSuffix(" - YouTube") {
                cleanTitle = String(cleanTitle.dropLast(" - YouTube".count))
            } else if cleanTitle.hasSuffix(" | YouTube") {
                cleanTitle = String(cleanTitle.dropLast(" | YouTube".count))
            }
            
            // Smart Artist & Song separator: " - " or " | "
            if cleanTitle.contains(" - ") {
                let parts = cleanTitle.components(separatedBy: " - ")
                if parts.count >= 2 {
                    artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    cleanTitle = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if cleanTitle.contains(" | ") {
                let parts = cleanTitle.components(separatedBy: " | ")
                if parts.count >= 2 {
                    cleanTitle = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    artist = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            if cleanTitle.isEmpty {
                cleanTitle = "YouTube Video"
            }
        }
        
        var isPlaying = false
        var duration: TimeInterval = 240
        var elapsedTime: TimeInterval = 0
        var artworkUrl: String? = nil
        
        if candidate.jsState.starts(with: "PLAYING") || candidate.jsState.starts(with: "PAUSED") {
            isPlaying = candidate.jsState.starts(with: "PLAYING")
            let jsParts = candidate.jsState.components(separatedBy: "|||")
            if jsParts.count >= 3 {
                if let cur = Double(jsParts[1]), cur >= 0 {
                    elapsedTime = cur
                }
                if let dur = Double(jsParts[2]), dur > 0 {
                    duration = dur
                }
            }
            if jsParts.count >= 4 {
                let rawArt = jsParts[3].trimmingCharacters(in: .whitespacesAndNewlines)
                if let decoded = rawArt.removingPercentEncoding, decoded.starts(with: "http") {
                    artworkUrl = decoded
                }
            }
        } else {
            isPlaying = isSystemAudioPlaying()
        }
        
        // Exact YouTube video poster extraction via videoID
        if sourceApp == "YouTube" {
            if let videoID = extractYouTubeVideoID(from: candidate.url) {
                artworkUrl = "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg"
                if duration == 240 {
                    if let cached = youtubeDurationCache[videoID] {
                        duration = cached
                    } else {
                        fetchYouTubeDuration(videoID: videoID)
                    }
                }
            }
        }
        
        let isChromeFront = (NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome")
        let isChromeHidden = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first?.isHidden ?? false
        let isTabVisible = isChromeFront && !isChromeHidden && candidate.isFrontWindow && candidate.isActiveTab && !candidate.isMinimized
        
        return MediaTrackInfo(
            title: cleanTitle,
            artist: artist,
            album: "Google Chrome",
            isPlaying: isPlaying,
            duration: duration,
            elapsedTime: elapsedTime,
            artwork: nil,
            artworkUrl: artworkUrl,
            sourceApp: sourceApp,
            isTabVisibleOnScreen: isTabVisible
        )
    }
    
    private func extractYouTubeVideoID(from urlStr: String) -> String? {
        guard let url = URL(string: urlStr) else { return nil }
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        
        let path = url.path
        if path.contains("/shorts/") {
            let parts = path.components(separatedBy: "/shorts/")
            if parts.count > 1, let id = parts[1].components(separatedBy: "/").first, !id.isEmpty {
                return id
            }
        }
        
        if path.contains("/live/") {
            let parts = path.components(separatedBy: "/live/")
            if parts.count > 1, let id = parts[1].components(separatedBy: "/").first, !id.isEmpty {
                return id
            }
        }
        
        if url.host == "youtu.be" {
            let id = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty {
                return id
            }
        }
        
        return nil
    }
    
    // MARK: - Direct PID & Keystroke Control
    
    private func sendKeyToChromePID(keyCode: CGKeyCode, shift: Bool = false) {
        let chromeApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome")
        guard let chrome = chromeApps.first else { return }
        let pid = chrome.processIdentifier
        
        let src = CGEventSource(stateID: .hidSystemState)
        if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            if shift {
                keyDown.flags = .maskShift
                keyUp.flags = .maskShift
            }
            keyDown.postToPid(pid)
            usleep(40000)
            keyUp.postToPid(pid)
        }
    }
    
    // MARK: - Playback & Seeking Controls
    
    public func seek(to position: TimeInterval) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let isSpotifyRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
            let isMusicRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
            
            if isSpotifyRunning && self.currentTrack.sourceApp == "Spotify" {
                _ = self.executeAppleScript("tell application \"Spotify\" to set player position to \(position)")
            } else if isMusicRunning && self.currentTrack.sourceApp == "Apple Music" {
                _ = self.executeAppleScript("tell application \"Music\" to set player position to \(position)")
            } else if ["YouTube", "Netflix", "JioHotstar", "JioCinema"].contains(self.currentTrack.sourceApp) {
                var handled = false
                if let tabId = self.lastActiveChromeTabId {
                    let jsScript = """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if (id of t as string) is "\(tabId)" then
                                    try
                                        execute t javascript "(function(){ var v = document.querySelector('video.html5-main-video') || document.querySelector('video'); if (v) v.currentTime = \(position); })()"
                                        return "OK"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                    """
                    if self.executeAppleScript(jsScript) == "OK" {
                        handled = true
                    }
                }
                if !handled && self.currentTrack.sourceApp == "YouTube" {
                    let targetSecs = Int(position)
                    let ytScript = """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                set curUrl to URL of t
                                if curUrl contains "youtube.com" then
                                    set text item delimiters to "&t="
                                    set urlParts to text items of curUrl
                                    set basePart to item 1 of urlParts
                                    set text item delimiters to ""
                                    set newUrl to basePart & "&t=\(targetSecs)s"
                                    set URL of t to newUrl
                                    return
                                end if
                            end repeat
                        end repeat
                    end tell
                    """
                    _ = self.executeAppleScript(ytScript)
                }
            }
        }
    }
    
    public func togglePlayPause() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let isSpotifyRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
            let isMusicRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
            
            if isSpotifyRunning && self.currentTrack.sourceApp == "Spotify" {
                _ = self.executeAppleScript("tell application \"Spotify\" to playpause")
            } else if isMusicRunning && self.currentTrack.sourceApp == "Apple Music" {
                _ = self.executeAppleScript("tell application \"Music\" to playpause")
            } else {
                var handled = false
                if let tabId = self.lastActiveChromeTabId {
                    let jsScript = """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if (id of t as string) is "\(tabId)" then
                                    try
                                        execute t javascript "(function(){ var v = document.querySelector('video.html5-main-video') || document.querySelector('video'); if (v) { v.paused ? v.play() : v.pause(); return 'OK'; } return 'NO_VIDEO'; })()"
                                        return "OK"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                    """
                    if self.executeAppleScript(jsScript) == "OK" {
                        handled = true
                    }
                }
                if !handled {
                    if self.currentTrack.sourceApp == "YouTube" {
                        self.sendKeyToChromePID(keyCode: 40) // 'k' key
                    } else {
                        self.sendKeyToChromePID(keyCode: 49) // Spacebar key
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.currentTrack.isPlaying.toggle()
                self.isPlaybackActive = self.currentTrack.isPlaying
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkActiveMediaOnLaunch()
            }
        }
    }
    
    public func nextTrack() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let isSpotifyRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
            let isMusicRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
            
            if isSpotifyRunning && self.currentTrack.sourceApp == "Spotify" {
                _ = self.executeAppleScript("tell application \"Spotify\" to next track")
            } else if isMusicRunning && self.currentTrack.sourceApp == "Apple Music" {
                _ = self.executeAppleScript("tell application \"Music\" to next track")
            } else if self.currentTrack.sourceApp == "YouTube" {
                var handled = false
                if let tabId = self.lastActiveChromeTabId {
                    let jsScript = """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if (id of t as string) is "\(tabId)" then
                                    try
                                        execute t javascript "(function(){ var btn = document.querySelector('.ytp-next-button'); if (btn && btn.offsetParent !== null) { btn.click(); return 'OK'; } var v = document.querySelector('video.html5-main-video') || document.querySelector('video'); if (v) { v.currentTime += 10; return 'OK'; } return 'NO_VIDEO'; })()"
                                        return "OK"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                    """
                    if self.executeAppleScript(jsScript) == "OK" {
                        handled = true
                    }
                }
                if !handled {
                    self.sendKeyToChromePID(keyCode: 45, shift: true) // Shift + N
                }
            } else {
                // Netflix or JioHotstar: Skip forward 10s
                var handled = false
                if let tabId = self.lastActiveChromeTabId {
                    let jsScript = """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if (id of t as string) is "\(tabId)" then
                                    try
                                        execute t javascript "(function(){ var v = document.querySelector('video.html5-main-video') || document.querySelector('video'); if (v) { v.currentTime += 10; return 'OK'; } return 'NO_VIDEO'; })()"
                                        return "OK"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                    """
                    if self.executeAppleScript(jsScript) == "OK" {
                        handled = true
                    }
                }
                if !handled {
                    self.sendKeyToChromePID(keyCode: 124) // Right Arrow
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkActiveMediaOnLaunch()
            }
        }
    }
    
    public func previousTrack() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let isSpotifyRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
            let isMusicRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Music" }
            
            if isSpotifyRunning && self.currentTrack.sourceApp == "Spotify" {
                _ = self.executeAppleScript("tell application \"Spotify\" to previous track")
            } else if isMusicRunning && self.currentTrack.sourceApp == "Apple Music" {
                _ = self.executeAppleScript("tell application \"Music\" to previous track")
            } else if self.currentTrack.sourceApp == "YouTube" {
                var handled = false
                if let tabId = self.lastActiveChromeTabId {
                    let jsScript = """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if (id of t as string) is "\(tabId)" then
                                    try
                                        execute t javascript "(function(){ var v = document.querySelector('video.html5-main-video') || document.querySelector('video'); if (v) { v.currentTime = Math.max(0, v.currentTime - 10); return 'OK'; } return 'NO_VIDEO'; })()"
                                        return "OK"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                    """
                    if self.executeAppleScript(jsScript) == "OK" {
                        handled = true
                    }
                }
                if !handled {
                    self.sendKeyToChromePID(keyCode: 35, shift: true) // Shift + P
                }
            } else {
                // Netflix or JioHotstar: Rewind 10s
                var handled = false
                if let tabId = self.lastActiveChromeTabId {
                    let jsScript = """
                    tell application "Google Chrome"
                        repeat with w in windows
                            repeat with t in tabs of w
                                if (id of t as string) is "\(tabId)" then
                                    try
                                        execute t javascript "(function(){ var v = document.querySelector('video.html5-main-video') || document.querySelector('video'); if (v) { v.currentTime = Math.max(0, v.currentTime - 10); return 'OK'; } return 'NO_VIDEO'; })()"
                                        return "OK"
                                    end try
                                end if
                            end repeat
                        end repeat
                    end tell
                    """
                    if self.executeAppleScript(jsScript) == "OK" {
                        handled = true
                    }
                }
                if !handled {
                    self.sendKeyToChromePID(keyCode: 123) // Left Arrow
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkActiveMediaOnLaunch()
            }
        }
    }
    
    private var cachedScripts: [String: NSAppleScript] = [:]
    private let scriptLock = NSLock()
    
    private func executeAppleScript(_ source: String) -> String? {
        scriptLock.lock()
        let scriptObject: NSAppleScript
        if let cached = cachedScripts[source] {
            scriptObject = cached
        } else {
            guard let script = NSAppleScript(source: source) else {
                scriptLock.unlock()
                return nil
            }
            var compileErr: NSDictionary?
            script.compileAndReturnError(&compileErr)
            cachedScripts[source] = script
            scriptObject = script
        }
        scriptLock.unlock()
        
        var error: NSDictionary?
        let output = scriptObject.executeAndReturnError(&error)
        if error == nil, let val = output.stringValue, !val.isEmpty {
            return val
        }
        return nil
    }
}
