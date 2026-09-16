import SwiftUI
import Combine

/// Manages active activities, priority queues, preemption, interruptions, auto-timeouts, and multi-activity swiping.
public final class ActivityManager: ObservableObject {
    @Published public private(set) var activeActivity: (any DynamicIslandActivity)?
    @Published public private(set) var activityStack: [any DynamicIslandActivity] = []
    @Published public private(set) var currentIndex: Int = 0
    
    public var onActivityChanged: ((_ old: (any DynamicIslandActivity)?, _ new: (any DynamicIslandActivity)?) -> Void)?
    
    private var timeoutTimers: [String: Timer] = [:]
    
    public init() {}
    
    /// Retrieves an existing activity by ID from the active stack without modifying priority or selection.
    public func getActivity(id: String) -> (any DynamicIslandActivity)? {
        return activityStack.first(where: { $0.id == id })
    }
    
    /// The secondary concurrent activity displayed in the detached bubble (strictly for persistent tasks like Music, Timers, Calls, Voice Memos)
    public var secondaryActivity: (any DynamicIslandActivity)? {
        // If current active activity is a temporary HUD or Weather, suppress secondary bubble
        if let current = activeActivity, current.priority == .critical || current.type == .volume || current.type == .brightness || current.type == .battery || current.type == .clipboard || current.type == .weather || current.id == "activity.focus" {
            return nil
        }
        
        // Filter stack for persistent multi-activity candidates only (Music, Timer, Calls, Voice Memos, Downloads)
        let eligibleStack = activityStack.filter {
            $0.type != .volume && $0.type != .brightness && $0.type != .battery && $0.type != .clipboard && $0.type != .weather && $0.id != "activity.focus" && $0.id != "hud.capslock" && $0.id != "hud.lock" && $0.id != "activity.caffeine"
        }
        
        guard eligibleStack.count > 1 else { return nil }
        
        if let current = activeActivity, let idx = eligibleStack.firstIndex(where: { $0.id == current.id }) {
            let nextIdx = (idx + 1) % eligibleStack.count
            return eligibleStack[nextIdx]
        }
        return eligibleStack.count > 1 ? eligibleStack[1] : nil
    }
    
    /// Determines the correct foreground activity, ensuring Weather is ONLY shown when truly idle
    public func resolveActiveActivity() -> (any DynamicIslandActivity)? {
        let nonWeather = activityStack.filter { $0.type != .weather }
        if !nonWeather.isEmpty {
            if let current = activeActivity, let match = nonWeather.first(where: { $0.id == current.id }) {
                return match
            }
            return nonWeather.first
        } else {
            return activityStack.first(where: { $0.type == .weather })
        }
    }
    
    /// Presents or queues an activity according to priority.
    public func presentActivity(_ activity: any DynamicIslandActivity) {
        // Invalidate any existing timer for this activity ID
        timeoutTimers[activity.id]?.invalidate()
        timeoutTimers.removeValue(forKey: activity.id)
        
        let previousActive = activeActivity
        
        // Remove existing instance if present
        activityStack.removeAll { $0.id == activity.id }
        
        // Insert into stack maintaining priority order
        activityStack.append(activity)
        activityStack.sort { $0.priority > $1.priority }
        
        // Resolve new active activity (Weather is strictly suppressed if any non-weather activity exists)
        let newActive: (any DynamicIslandActivity)?
        if activity.type != .weather {
            if let previous = previousActive {
                if previous.id == "activity.hello" && activity.id != "activity.permissions" {
                    newActive = previous
                } else if previous.id == "activity.permissions" && !PermissionsService.shared.allGranted {
                    newActive = previous
                } else if previous.priority > activity.priority {
                    newActive = previous
                } else {
                    newActive = activity
                }
            } else {
                newActive = activity
            }
        } else {
            newActive = resolveActiveActivity()
        }
        
        self.activeActivity = newActive
        if let newActive = newActive, let idx = activityStack.firstIndex(where: { $0.id == newActive.id }) {
            self.currentIndex = idx
        }
        self.objectWillChange.send()
        
        self.onActivityChanged?(previousActive, newActive)
        
        // Schedule auto-timeout if configured using .common RunLoop mode
        if let timeout = activity.timeoutDuration {
            timeoutTimers[activity.id]?.invalidate()
            let timer = Timer(timeInterval: timeout, repeats: false) { [weak self] _ in
                self?.removeActivity(id: activity.id)
            }
            RunLoop.main.add(timer, forMode: .common)
            timeoutTimers[activity.id] = timer
        }
    }
    
    /// Sets the active primary activity by ID without re-inserting or recreating the activity instance.
    public func setActiveActivity(id: String) {
        guard let idx = activityStack.firstIndex(where: { $0.id == id }) else { return }
        let previousActive = activeActivity
        self.currentIndex = idx
        let newActive = activityStack[idx]
        self.activeActivity = newActive
        self.objectWillChange.send()
        if previousActive?.id != newActive.id {
            self.onActivityChanged?(previousActive, newActive)
        }
    }
    
    /// Highlights a persistent concurrent activity in foreground for `duration` seconds when it starts,
    /// then smoothly switches foreground focus back to `returnToId` (e.g. Music) while keeping the activity active in the stack (secondary bubble)!
    public func highlightPersistentActivity(activity: any DynamicIslandActivity, duration: TimeInterval, returnToId: String) {
        // Insert into stack persistently
        presentActivity(activity)
        
        // After duration, return foreground focus to returnToId if it is still present in stack
        let returnTimer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if self.activeActivity?.id == activity.id && self.getActivity(id: returnToId) != nil {
                self.setActiveActivity(id: returnToId)
            }
        }
        RunLoop.main.add(returnTimer, forMode: .common)
    }
    
    /// Temporarily makes an activity the active foreground activity for `duration` seconds,
    /// then cleanly removes it and smoothly restores foreground focus to `fallbackId` (e.g. Music).
    public func promoteTemporarily(activity: any DynamicIslandActivity, duration: TimeInterval, fallbackId: String?) {
        if let current = activeActivity {
            if current.id == "activity.hello" || (current.id == "activity.permissions" && !PermissionsService.shared.allGranted) {
                return
            }
        }
        
        // Invalidate any existing timeout timer for this activity
        timeoutTimers[activity.id]?.invalidate()
        timeoutTimers.removeValue(forKey: activity.id)
        
        let previousActive = activeActivity
        activityStack.removeAll { $0.id == activity.id }
        
        // Insert into stack
        activityStack.append(activity)
        activityStack.sort { $0.priority > $1.priority }
        
        // Force newly promoted activity to be the foreground activeActivity immediately!
        self.currentIndex = activityStack.firstIndex(where: { $0.id == activity.id }) ?? 0
        let newActive = activityStack[currentIndex]
        self.activeActivity = newActive
        self.objectWillChange.send()
        
        if previousActive?.id != newActive.id {
            self.onActivityChanged?(previousActive, newActive)
        }
        
        // Schedule the switch-back timer: cleanly remove the temporary activity
        let switchTimer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.removeActivity(id: activity.id)
        }
        RunLoop.main.add(switchTimer, forMode: .common)
        timeoutTimers[activity.id] = switchTimer
    }
    
    /// Cycles to the next live activity in the stack (Swipe Left / Tap Bubble).
    public func cycleNext() {
        let eligible = activityStack.filter { $0.type != .weather }
        guard eligible.count > 1 else { return }
        let previousActive = activeActivity
        let currentEligibleIdx = eligible.firstIndex(where: { $0.id == previousActive?.id }) ?? 0
        let nextIdx = (currentEligibleIdx + 1) % eligible.count
        let newActive = eligible[nextIdx]
        
        self.activeActivity = newActive
        if let stackIdx = activityStack.firstIndex(where: { $0.id == newActive.id }) {
            self.currentIndex = stackIdx
        }
        self.objectWillChange.send()
        if previousActive?.id != newActive.id {
            self.onActivityChanged?(previousActive, newActive)
        }
    }
    
    /// Cycles to the previous live activity in the stack (Swipe Right).
    public func cyclePrevious() {
        let eligible = activityStack.filter { $0.type != .weather }
        guard eligible.count > 1 else { return }
        let previousActive = activeActivity
        let currentEligibleIdx = eligible.firstIndex(where: { $0.id == previousActive?.id }) ?? 0
        let prevIdx = (currentEligibleIdx - 1 + eligible.count) % eligible.count
        let newActive = eligible[prevIdx]
        
        self.activeActivity = newActive
        if let stackIdx = activityStack.firstIndex(where: { $0.id == newActive.id }) {
            self.currentIndex = stackIdx
        }
        self.objectWillChange.send()
        if previousActive?.id != newActive.id {
            self.onActivityChanged?(previousActive, newActive)
        }
    }
    
    /// Removes an activity from the active stack and gracefully resumes previous activity.
    public func removeActivity(id: String) {
        timeoutTimers[id]?.invalidate()
        timeoutTimers.removeValue(forKey: id)
        
        let previousActive = activeActivity
        activityStack.removeAll { $0.id == id }
        
        let newActive = resolveActiveActivity()
        self.activeActivity = newActive
        if let newActive = newActive, let idx = activityStack.firstIndex(where: { $0.id == newActive.id }) {
            self.currentIndex = idx
        } else {
            self.currentIndex = 0
        }
        self.objectWillChange.send()
        
        if previousActive?.id != newActive?.id {
            self.onActivityChanged?(previousActive, newActive)
        }
    }
    
    /// Removes all activities matching the given type.
    public func removeActivities(ofType type: ActivityType) {
        let matchingIds = activityStack.filter { $0.type == type }.map { $0.id }
        for id in matchingIds {
            removeActivity(id: id)
        }
    }
    
    /// Clears all activities and returns to idle.
    public func clearAllActivities() {
        for timer in timeoutTimers.values {
            timer.invalidate()
        }
        timeoutTimers.removeAll()
        
        let previousActive = activeActivity
        activityStack.removeAll()
        currentIndex = 0
        self.activeActivity = nil
        
        if previousActive != nil {
            self.onActivityChanged?(previousActive, nil)
        }
    }
}
