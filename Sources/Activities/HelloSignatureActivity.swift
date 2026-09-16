import SwiftUI
import AppKit

// MARK: - Animation Styles

public enum HelloAnimationStyle: String, CaseIterable, Identifiable, Sendable {
    case classicCursive = "Classic Cursive"
    case neonAurora = "Neon Aurora"
    case liquidGlass = "Liquid Glass"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .classicCursive: return "pencil.tip"
        case .neonAurora: return "sparkles"
        case .liquidGlass: return "cube.transparent"
        }
    }
    
    public var shortTitle: String {
        switch self {
        case .classicCursive: return "✍️ Cursive"
        case .neonAurora: return "⚡️ Aurora"
        case .liquidGlass: return "💎 Glass"
        }
    }
}

/// Dynamic Island Activity representing Apple's iconic "hello" signature welcome greeting.
/// Configured to persist in the expanded state until the user finishes setup.
public final class HelloSignatureActivity: DynamicIslandActivity, ObservableObject {
    public let id: String
    public let type: ActivityType = .custom
    public let priority: ActivityPriority = .critical
    public var timeoutDuration: TimeInterval? = nil // NEVER auto-close; persists until user interacts
    
    @Published public var style: HelloAnimationStyle {
        didSet {
            UserDefaults.standard.set(style.rawValue, forKey: "macbooknotch.hello.style")
        }
    }
    
    public static var currentStyle: HelloAnimationStyle {
        if let raw = UserDefaults.standard.string(forKey: "macbooknotch.hello.style"),
           let s = HelloAnimationStyle(rawValue: raw) {
            return s
        }
        return .classicCursive
    }
    
    public var title: String { "hello" }
    public var subtitle: String { "Welcome to Dynamic Island" }
    public var iconName: String { style.icon }
    public var tintColor: Color { Color(red: 0.95, green: 0.45, blue: 0.75) }
    public var progress: Double? { nil }
    
    public var compactPreferredWidth: CGFloat { 282 }
    public var expandedPreferredSize: CGSize { CGSize(width: 440, height: 195) }
    
    public init(id: String = "activity.hello", style: HelloAnimationStyle = HelloSignatureActivity.currentStyle) {
        self.id = id
        self.style = style
    }
    
    public func compactLeadingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.4, blue: 0.6), Color(red: 0.6, green: 0.4, blue: 1.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .matchedGeometryIfAvailable(id: "hello_icon_\(id)", in: namespace)
                
                Text("hello")
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundColor(.white)
            }
            .padding(.leading, 6)
        )
    }
    
    public func compactTrailingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            Text("MacBook Notch")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .padding(.trailing, 8)
        )
    }
    
    public func expandedView(controller: DynamicIslandController, namespace: Namespace.ID?) -> AnyView {
        AnyView(
            HelloSignatureExpandedCardView(activity: self, controller: controller, namespace: namespace)
        )
    }
}

// MARK: - Expanded Card View

public struct HelloSignatureExpandedCardView: View {
    @ObservedObject public var activity: HelloSignatureActivity
    public let controller: DynamicIslandController
    public let namespace: Namespace.ID?
    
    @State private var replayToken: UUID = UUID()
    @State private var subtitleOpacity: Double = 0.0
    @State private var buttonScale: CGFloat = 0.8
    @State private var isAnimationDone: Bool = false
    
    public var body: some View {
        VStack(spacing: 7) {
            // Top Header: Branding & Animation Style Switcher
            HStack(alignment: .center) {
                HStack(spacing: 5.5) {
                    if let icon = NSImage(named: "AppIcon") ?? (Bundle.main.url(forResource: "AppIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) }) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 14, height: 14)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    } else {
                        Image(systemName: "apple.logo")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    Text("MacBook Notch")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // 3 Animation Style Switcher Pills (Rounded Rectangles)
                HStack(spacing: 4) {
                    ForEach(HelloAnimationStyle.allCases) { style in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                activity.style = style
                                replayToken = UUID()
                                triggerAnimationTimeline()
                            }
                        }) {
                            Text(style.shortTitle)
                                .font(.system(size: 9.5, weight: activity.style == style ? .bold : .medium, design: .rounded))
                                .foregroundColor(activity.style == style ? .white : .white.opacity(0.55))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(activity.style == style ? Color.white.opacity(0.18) : Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(activity.style == style ? Color.white.opacity(0.3) : Color.clear, lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Replay Current Animation Button
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            replayToken = UUID()
                            triggerAnimationTimeline()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(4.5)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Replay Animation")
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            
            // Animation Showcase Stage
            ZStack {
                switch activity.style {
                case .classicCursive:
                    HelloCursiveAnimatedView()
                        .id("cursive_\(replayToken)")
                case .neonAurora:
                    HelloNeonAuroraAnimatedView()
                        .id("neon_\(replayToken)")
                case .liquidGlass:
                    HelloLiquidGlassAnimatedView()
                        .id("glass_\(replayToken)")
                }
            }
            .frame(height: 58)
            .padding(.horizontal, 8)
            
            // Footer: Subtitle & Non-Collapsing Action Button
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Your dynamic workspace is ready.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("Music, Calls, Sports, Clipboard & Shelf in your notch")
                        .font(.system(size: 9.5, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }
                .opacity(subtitleOpacity)
                
                Spacer()
                
                if !isAnimationDone {
                    HStack(spacing: 5) {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 14, height: 14)
                        Text("Writing...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .transition(.opacity)
                } else {
                    Button(action: {
                        controller.activityManager.removeActivity(id: activity.id)
                        if !PermissionsService.shared.allGranted {
                            controller.triggerPermissionsOnboarding()
                        } else if controller.activeActivity != nil {
                            controller.transition(to: .compact)
                        } else {
                            controller.transition(to: .idle)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("Let's Go")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color.white, Color(white: 0.88)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: Color.white.opacity(0.3), radius: 6, y: 1)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(buttonScale)
                    .opacity(subtitleOpacity)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            triggerAnimationTimeline()
        }
    }
    
    private func triggerAnimationTimeline() {
        isAnimationDone = false
        subtitleOpacity = 0.0
        buttonScale = 0.8
        
        // Wait for signature animation completion before unveiling "Let's Go"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                self.isAnimationDone = true
                self.subtitleOpacity = 1.0
                self.buttonScale = 1.0
            }
        }
    }
}

// MARK: - Animation 1: Classic Cursive Handwriting

public struct HelloCursiveAnimatedView: View {
    @State private var strokeProgress: CGFloat = 0.0
    @State private var gradientOffset: CGFloat = -1.0
    @State private var auraPulse: Bool = false
    
    private let rainbowColors: [Color] = [
        Color(red: 1.0, green: 0.35, blue: 0.45),
        Color(red: 1.0, green: 0.65, blue: 0.20),
        Color(red: 0.30, green: 0.85, blue: 0.45),
        Color(red: 0.25, green: 0.65, blue: 1.00),
        Color(red: 0.70, green: 0.40, blue: 0.95),
        Color(red: 1.0, green: 0.35, blue: 0.75)
    ]
    
    public var body: some View {
        ZStack {
            // Glowing Aura Background
            HelloCursiveShape()
                .stroke(
                    LinearGradient(
                        colors: rainbowColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 7.0, lineCap: .round, lineJoin: .round)
                )
                .blur(radius: auraPulse ? 10 : 6)
                .opacity(0.55 * strokeProgress)
            
            // Core Animated Handwriting Stroke
            HelloCursiveShape()
                .trim(from: 0.0, to: strokeProgress)
                .stroke(
                    LinearGradient(
                        colors: rainbowColors,
                        startPoint: UnitPoint(x: gradientOffset, y: 0),
                        endPoint: UnitPoint(x: gradientOffset + 1.2, y: 1)
                    ),
                    style: StrokeStyle(lineWidth: 4.2, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: Color.white.opacity(0.4), radius: 3)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8)) {
                strokeProgress = 1.0
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                gradientOffset = 1.0
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                auraPulse = true
            }
        }
    }
}

// MARK: - Animation 2: Neon Aurora (Retro Cyber Wave)

public struct HelloNeonAuroraAnimatedView: View {
    @State private var lettersRevealed: [Bool] = [false, false, false, false, false, false]
    @State private var beamOffset: CGFloat = -180
    @State private var glowIntensity: Double = 0.5
    @State private var sparkPulse: Bool = false
    
    private let letters = ["h", "e", "l", "l", "o", "."]
    
    private let neonGradients: [LinearGradient] = [
        LinearGradient(colors: [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 0.2, green: 0.5, blue: 1.0)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 1.0), Color(red: 0.6, green: 0.2, blue: 1.0)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(red: 0.6, green: 0.2, blue: 1.0), Color(red: 1.0, green: 0.1, blue: 0.7)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(red: 1.0, green: 0.1, blue: 0.7), Color(red: 1.0, green: 0.3, blue: 0.3)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(red: 1.0, green: 0.4, blue: 0.2), Color(red: 1.0, green: 0.8, blue: 0.1)], startPoint: .top, endPoint: .bottom),
        LinearGradient(colors: [Color(red: 0.0, green: 1.0, blue: 0.6), Color(red: 0.0, green: 0.8, blue: 1.0)], startPoint: .top, endPoint: .bottom)
    ]
    
    public var body: some View {
        ZStack {
            // Ambient Aurora Plasma Glow
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.cyan.opacity(0.35), Color.purple.opacity(0.25), Color.clear],
                        center: .center,
                        startRadius: 5,
                        endRadius: 100
                    )
                )
                .frame(width: 260, height: 50)
                .blur(radius: 12)
                .scaleEffect(glowIntensity > 0.6 ? 1.15 : 0.9)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: glowIntensity)
            
            // Staggered Neon Letters
            HStack(spacing: 3.5) {
                ForEach(0..<letters.count, id: \.self) { idx in
                    Text(letters[idx])
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(neonGradients[idx % neonGradients.count])
                        .shadow(color: Color.cyan.opacity(0.7), radius: 6, x: 0, y: 0)
                        .shadow(color: Color.pink.opacity(0.8), radius: 14, x: 0, y: 0)
                        .shadow(color: Color.purple.opacity(0.5), radius: 22, x: 0, y: 0)
                        .offset(y: lettersRevealed[idx] ? 0 : -24)
                        .scaleEffect(lettersRevealed[idx] ? 1.0 : 0.2)
                        .opacity(lettersRevealed[idx] ? 1.0 : 0.0)
                }
            }
            
            // Electric Laser Beam Sweep
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, Color.white.opacity(0.9), Color.cyan, Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 40, height: 42)
                .rotationEffect(.degrees(25))
                .offset(x: beamOffset)
                .blendMode(.screen)
            
            // Particle Sparkles
            HStack(spacing: 38) {
                ForEach(0..<4, id: \.self) { idx in
                    Image(systemName: "sparkle")
                        .font(.system(size: 9 + CGFloat(idx % 2) * 3, weight: .bold))
                        .foregroundColor(idx % 2 == 0 ? .cyan : .pink)
                        .scaleEffect(sparkPulse ? 1.3 : 0.6)
                        .opacity(sparkPulse ? 0.9 : 0.2)
                        .offset(y: idx % 2 == 0 ? -14 : 12)
                }
            }
        }
        .onAppear {
            for i in 0..<letters.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.58, blendDuration: 0.1)) {
                        lettersRevealed[i] = true
                    }
                }
            }
            
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false).delay(0.6)) {
                beamOffset = 180
            }
            
            glowIntensity = 0.9
            
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                sparkPulse = true
            }
        }
    }
}

// MARK: - Animation 3: Liquid Glass (Apple Vision 3D Specular)

public struct HelloLiquidGlassAnimatedView: View {
    @State private var shimmerPhase: CGFloat = -1.2
    @State private var isLevitating: Bool = false
    @State private var borderAngle: Double = 0
    
    public var body: some View {
        ZStack {
            // Iridescent Rotating Prismatic Rim
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [Color.cyan, Color.purple, Color.pink, Color.orange, Color.yellow, Color.cyan],
                        center: .center,
                        angle: .degrees(borderAngle)
                    ),
                    lineWidth: 1.6
                )
                .frame(width: 220, height: 46)
                .blur(radius: 1.2)
            
            // Frosted Liquid Glass Surface
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 46)
                .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
            
            // Embossed 3D "hello." Typography
            Text("hello.")
                .font(.system(size: 29, weight: .bold, design: .serif))
                .italic()
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(white: 0.92),
                            Color(red: 0.85, green: 0.90, blue: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1.5)
                .shadow(color: Color.white.opacity(0.2), radius: 4, x: 0, y: -1)
            
            // Iridescent Specular Light Gleam Sweep
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.white.opacity(0.1), location: 0.4),
                            .init(color: Color.white.opacity(0.85), location: 0.5),
                            .init(color: Color.cyan.opacity(0.5), location: 0.55),
                            .init(color: .clear, location: 0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 220, height: 46)
                .rotationEffect(.degrees(30))
                .offset(x: shimmerPhase * 160)
                .mask(
                    Text("hello.")
                        .font(.system(size: 29, weight: .bold, design: .serif))
                        .italic()
                )
            
            // Subtle Lens Flare Star
            Image(systemName: "sparkle")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .shadow(color: .cyan, radius: 4)
                .offset(x: 75, y: -13)
                .scaleEffect(isLevitating ? 1.2 : 0.8)
        }
        .offset(y: isLevitating ? -2 : 2)
        .onAppear {
            withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                borderAngle = 360
            }
            
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false).delay(0.2)) {
                shimmerPhase = 1.2
            }
            
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isLevitating = true
            }
        }
    }
}

// MARK: - Custom Vector Cursive Shape

public struct HelloCursiveShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let scaleX = rect.width / 240.0
        let scaleY = rect.height / 50.0
        
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }
        
        // --- 'h' ---
        path.move(to: pt(10, 38))
        path.addCurve(to: pt(28, 6), control1: pt(14, 25), control2: pt(22, 10))
        path.addCurve(to: pt(26, 42), control1: pt(32, 2), control2: pt(26, 28))
        path.addCurve(to: pt(46, 26), control1: pt(26, 30), control2: pt(36, 22))
        path.addCurve(to: pt(52, 42), control1: pt(50, 30), control2: pt(52, 38))
        
        // --- 'e' ---
        path.addCurve(to: pt(76, 26), control1: pt(56, 38), control2: pt(68, 28))
        path.addCurve(to: pt(72, 42), control1: pt(82, 24), control2: pt(80, 42))
        path.addCurve(to: pt(92, 34), control1: pt(65, 42), control2: pt(86, 36))
        
        // --- 'l' (first) ---
        path.addCurve(to: pt(112, 4), control1: pt(96, 32), control2: pt(106, 12))
        path.addCurve(to: pt(116, 42), control1: pt(116, -1), control2: pt(114, 28))
        
        // --- 'l' (second) ---
        path.addCurve(to: pt(138, 4), control1: pt(122, 36), control2: pt(132, 12))
        path.addCurve(to: pt(142, 42), control1: pt(142, -1), control2: pt(140, 28))
        
        // --- 'o' ---
        path.addCurve(to: pt(168, 25), control1: pt(148, 38), control2: pt(158, 24))
        path.addCurve(to: pt(186, 34), control1: pt(178, 24), control2: pt(186, 28))
        path.addCurve(to: pt(168, 43), control1: pt(186, 40), control2: pt(176, 44))
        path.addCurve(to: pt(166, 26), control1: pt(160, 42), control2: pt(160, 28))
        path.addCurve(to: pt(205, 24), control1: pt(176, 24), control2: pt(192, 22))
        
        // --- signature swirl / flourish ---
        path.addCurve(to: pt(230, 28), control1: pt(212, 25), control2: pt(222, 26))
        
        return path
    }
}
