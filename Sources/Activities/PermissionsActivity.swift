import SwiftUI
import AppKit

/// Dynamic Island Activity that presents an interactive Apple-style permissions card
/// directly inside the expanded notch when the app starts.
public final class PermissionsActivity: DynamicIslandActivity, ObservableObject {
    public let id: String
    public let type: ActivityType = .permissions
    public let priority: ActivityPriority = .critical
    public var timeoutDuration: TimeInterval? = nil // Persist until user interacts
    
    public var title: String { "Permissions & Setup" }
    public var subtitle: String { "Grant access for Dynamic Island features" }
    public var iconName: String { "shield.lefthalf.filled" }
    public var tintColor: Color { Color(red: 0.35, green: 0.65, blue: 1.0) }
    public var progress: Double? { nil }
    
    public var compactPreferredWidth: CGFloat { 260 }
    public var expandedPreferredSize: CGSize { CGSize(width: 440, height: 295) }
    
    public init(id: String = "activity.permissions") {
        self.id = id
    }
    
    public func compactLeadingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                    .matchedGeometryIfAvailable(id: "permissions_icon_\(id)", in: namespace)
                
                Text("Permissions")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.leading, 6)
        )
    }
    
    public func compactTrailingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            HStack(spacing: 4) {
                Text("\(PermissionsService.shared.grantedCount)/\(PermissionsService.shared.totalCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PermissionsService.shared.allGranted ? .green : .white.opacity(0.8))
                
                Circle()
                    .fill(PermissionsService.shared.allGranted ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
            }
            .padding(.trailing, 8)
        )
    }
    
    public func expandedView(controller: DynamicIslandController, namespace: Namespace.ID?) -> AnyView {
        AnyView(
            PermissionsExpandedCardView(activity: self, controller: controller, namespace: namespace)
        )
    }
}

// MARK: - Expanded Card View

public struct PermissionsExpandedCardView: View {
    @ObservedObject public var activity: PermissionsActivity
    @ObservedObject public var controller: DynamicIslandController
    public let namespace: Namespace.ID?
    
    @ObservedObject private var service = PermissionsService.shared
    
    public var body: some View {
        VStack(spacing: 7) {
            // Hardware Notch camera clearance
            Spacer()
                .frame(height: 14)
            
            // Header Row
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.15, green: 0.5, blue: 1.0), Color(red: 0.6, green: 0.25, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                    
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .matchedGeometryIfAvailable(id: "permissions_icon_\(activity.id)", in: namespace)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Permissions & Setup")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Required for Dynamic Island features")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                }
                
                Spacer()
                
                // Status Badge (Rounded Rectangle)
                HStack(spacing: 5) {
                    Circle()
                        .fill(service.allGranted ? Color.green : Color(red: 1.0, green: 0.7, blue: 0.2))
                        .frame(width: 6, height: 6)
                    
                    Text(service.allGranted ? "All Allowed" : "\(service.grantedCount) of \(service.totalCount) Allowed")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(service.allGranted ? .green : .white.opacity(0.85))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(service.allGranted ? Color.green.opacity(0.16) : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(service.allGranted ? Color.green.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            
            // 4 Sleek Glassmorphism Permission Cards
            VStack(spacing: 5.5) {
                // 1. Accessibility
                PermissionCardRow(
                    icon: "hand.raised.fill",
                    gradientColors: [Color(red: 0.6, green: 0.3, blue: 0.95), Color(red: 0.45, green: 0.15, blue: 0.8)],
                    title: "Accessibility",
                    subtitle: "Notch gestures, hover tracking & display alignment",
                    isGranted: service.isAccessibilityGranted,
                    actionTitle: "Allow"
                ) {
                    service.agreeAccessibility()
                }
                
                // 2. Automation & Media
                PermissionCardRow(
                    icon: "play.square.stack.fill",
                    gradientColors: [Color(red: 1.0, green: 0.25, blue: 0.5), Color(red: 0.8, green: 0.1, blue: 0.35)],
                    title: "Media Automation",
                    subtitle: "Playback controls for Spotify, Apple Music & Chrome tabs",
                    isGranted: service.isAutomationGranted,
                    actionTitle: "Allow"
                ) {
                    service.agreeAutomation()
                }
                
                // 3. Location Services
                PermissionCardRow(
                    icon: "location.fill",
                    gradientColors: [Color(red: 0.0, green: 0.65, blue: 1.0), Color(red: 0.0, green: 0.4, blue: 0.85)],
                    title: "Location Services",
                    subtitle: "Accurate local live weather, temperature & air quality",
                    isGranted: service.isLocationGranted,
                    actionTitle: "Allow"
                ) {
                    service.agreeLocation()
                }
                
                // 4. Bluetooth Devices
                PermissionCardRow(
                    icon: "airpodspro",
                    gradientColors: [Color(red: 0.2, green: 0.5, blue: 1.0), Color(red: 0.1, green: 0.3, blue: 0.8)],
                    title: "Bluetooth & AirPods",
                    subtitle: "Battery levels for AirPods, headphones & wireless gear",
                    isGranted: service.isBluetoothGranted,
                    actionTitle: "Allow"
                ) {
                    service.agreeBluetooth()
                }
            }
            .padding(.horizontal, 10)
            
            // Bottom Footer
            HStack {
                Button(action: {
                    service.openPrivacySettings()
                }) {
                    HStack(spacing: 4) {
                        Text("System Settings")
                            .font(.system(size: 10.5, weight: .medium))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.white.opacity(0.65))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        if service.allGranted {
                            dismissOnboarding()
                        } else {
                            service.agreeToAllPermissions()
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Text(service.allGranted ? "Let's Go" : "Agree to All")
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        Image(systemName: service.allGranted ? "arrow.right.circle.fill" : "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(
                            colors: service.allGranted
                                ? [Color(red: 0.1, green: 0.78, blue: 0.38), Color(red: 0.05, green: 0.58, blue: 0.28)]
                                : [Color(red: 0.15, green: 0.5, blue: 1.0), Color(red: 0.5, green: 0.3, blue: 0.95)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    )
                    .shadow(color: (service.allGranted ? Color.green : Color.blue).opacity(0.35), radius: 5, x: 0, y: 1.5)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            service.startPolling()
            service.checkAllPermissions()
        }
        .onDisappear {
            service.stopPolling()
        }
    }
    
    private func dismissOnboarding() {
        guard service.allGranted else { return }
        service.hasCompletedOnboarding = true
        controller.activityManager.removeActivity(id: activity.id)
        if controller.activityManager.activeActivity != nil {
            controller.transition(to: .compact)
        } else {
            controller.transition(to: .idle)
        }
    }
}

// MARK: - Row Subview

private struct PermissionCardRow: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon squircle (Rounded Rectangle)
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: gradientColors[0].opacity(0.3), radius: 3, x: 0, y: 1)
                
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Info text
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status or Action Button (Rounded Rectangles)
            if isGranted {
                HStack(spacing: 3.5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                    Text("Allowed")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(Color.green.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 0.8)
                )
            } else {
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        action()
                    }
                }) {
                    Text(actionTitle)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 0.15, green: 0.5, blue: 1.0), Color(red: 0.3, green: 0.35, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                        )
                        .shadow(color: Color.blue.opacity(0.4), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.09) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.08), lineWidth: 0.8)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                self.isHovered = hovering
            }
        }
    }
}
