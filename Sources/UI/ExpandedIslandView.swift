import SwiftUI

/// Expanded Island View: Hosts the full interactive surface of an active activity,
/// positioning all content safely below the physical MacBook notch cutout.
public struct ExpandedIslandView: View {
    public let activity: any DynamicIslandActivity
    public let controller: DynamicIslandController
    public let namespace: Namespace.ID?
    
    public init(activity: any DynamicIslandActivity, controller: DynamicIslandController, namespace: Namespace.ID? = nil) {
        self.activity = activity
        self.controller = controller
        self.namespace = namespace
    }
    
    private var notchHeight: CGFloat {
        max(controller.displayManager.currentNotchInfo.notchSize.height, 32)
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Color.clear for physical MacBook notch camera clearance (fixed height, never expands)
            Color.clear
                .frame(height: notchHeight + 4)
            
            // Full Interactive Surface
            activity.expandedView(controller: controller, namespace: namespace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// Content switcher view that morphs smoothly between idle, compact, and expanded states.
public struct ActivityContentView: View {
    @ObservedObject public var controller: DynamicIslandController
    public let namespace: Namespace.ID?
    
    public init(controller: DynamicIslandController, namespace: Namespace.ID? = nil) {
        self.controller = controller
        self.namespace = namespace
    }
    
    public var body: some View {
        ZStack {
            switch controller.state {
            case .idle, .peek:
                IdleIslandView(isHovered: controller.isHovered)
                    .transition(.opacity)
                
            case .compact:
                if let activity = controller.activeActivity {
                    CompactIslandView(activity: activity, namespace: namespace)
                        .id(activity.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.94)),
                            removal: .opacity.combined(with: .scale(scale: 0.92))
                        ))
                }
                
            case .expanded:
                if let activity = controller.activeActivity {
                    ExpandedIslandView(activity: activity, controller: controller, namespace: namespace)
                        .id(activity.id + "_expanded")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity.combined(with: .scale(scale: 0.92))
                        ))
                }
            }
        }
        .animation(controller.state == .expanded ? controller.animationEngine.contentSpring : controller.animationEngine.collapseSpring, value: controller.state)
        .animation(controller.animationEngine.contentSpring, value: controller.activeActivity?.id)
    }
}
