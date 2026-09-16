import SwiftUI

/// Priority levels for Dynamic Island activities to manage preemption and stacking.
public enum ActivityPriority: Int, Comparable, Sendable {
    case ambient = 0    // Passive indicators (AirPods connected, Clipboard copied)
    case standard = 10  // Ongoing tasks (Music now playing, File downloads)
    case high = 20      // Active foreground timers, AI response completion
    case critical = 30  // System HUDs (Volume, Brightness, Low Battery, Charging)
    
    public static func < (lhs: ActivityPriority, rhs: ActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Type of activity for filtering and identification.
public enum ActivityType: String, CaseIterable, Sendable {
    case music
    case timer
    case clipboard
    case volume
    case brightness
    case battery
    case airpods
    case call
    case voiceMemo
    case capsLock
    case lock
    case caffeine
    case download
    case weather
    case shelf
    case whatsapp
    case permissions
    case sports
    case custom
}

/// Core protocol governing any Dynamic Island activity.
public protocol DynamicIslandActivity: AnyObject, Identifiable {
    var id: String { get }
    var type: ActivityType { get }
    var priority: ActivityPriority { get }
    var title: String { get }
    var subtitle: String { get }
    var iconName: String { get }
    var tintColor: Color { get }
    var progress: Double? { get } // 0.0 to 1.0
    var isLive: Bool { get }
    var timeoutDuration: TimeInterval? { get }
    
    // Size preferences
    var compactPreferredWidth: CGFloat { get }
    var expandedPreferredSize: CGSize { get }
    
    // View builders supporting matched geometry namespace
    @ViewBuilder func compactLeadingView(namespace: Namespace.ID?) -> AnyView
    @ViewBuilder func compactTrailingView(namespace: Namespace.ID?) -> AnyView
    @ViewBuilder func expandedView(controller: DynamicIslandController, namespace: Namespace.ID?) -> AnyView
    
    // Minimal detached secondary bubble view (for dual-activity mode)
    var minimalBubbleView: AnyView { get }
}

// Default protocol extensions
public extension DynamicIslandActivity {
    var compactPreferredWidth: CGFloat { 240 }
    var expandedPreferredSize: CGSize { CGSize(width: 390, height: 160) }
    var isLive: Bool { true }
    var timeoutDuration: TimeInterval? { nil }
    var progress: Double? { nil }
    var tintColor: Color { .white }
    
    var minimalBubbleView: AnyView {
        AnyView(
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tintColor)
        )
    }
}

public extension View {
    @ViewBuilder
    func matchedGeometryIfAvailable(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace = namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
