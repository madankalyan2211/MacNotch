import SwiftUI

/// Dynamic Island Ambient Activity for Live Weather & Air Quality
public final class WeatherActivity: DynamicIslandActivity, ObservableObject {
    public let id: String
    public let type: ActivityType = .weather
    public let priority: ActivityPriority = .ambient
    public var timeoutDuration: TimeInterval? = 60.0 // Stays visible for 1 minute then auto-collapses to idle notch
    
    @Published public var weather: WeatherData
    
    public var title: String { "\(weather.temperature)° \(weather.conditionText)" }
    public var subtitle: String { weather.cityName }
    public var iconName: String { weather.iconName }
    public var tintColor: Color { weather.tintColor }
    public var progress: Double? { nil }
    
    public var compactPreferredWidth: CGFloat {
        // Dynamically compute width to perfectly fit any city name
        let nameCount = max(1, weather.cityName.count)
        let nameWidth = CGFloat(nameCount) * 8.2 + 28.0
        let wingWidth = max(55.0, nameWidth)
        return max(320.0, 185.0 + (wingWidth * 2.0))
    }
    public var expandedPreferredSize: CGSize { CGSize(width: 385, height: 145) }
    
    public init(id: String = "activity.weather", weather: WeatherData = .fallback) {
        self.id = id
        self.weather = weather
    }
    
    public func compactLeadingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            WeatherCompactLeadingView(activity: self, namespace: namespace)
        )
    }
    
    public func compactTrailingView(namespace: Namespace.ID?) -> AnyView {
        AnyView(
            WeatherCompactTrailingView(activity: self, namespace: namespace)
        )
    }
    
    public func expandedView(controller: DynamicIslandController, namespace: Namespace.ID?) -> AnyView {
        AnyView(
            WeatherExpandedCardView(activity: self, controller: controller, namespace: namespace)
        )
    }
    
    public var minimalBubbleView: AnyView {
        AnyView(
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tintColor)
        )
    }
}

public struct WeatherCompactLeadingView: View {
    @ObservedObject public var activity: WeatherActivity
    public let namespace: Namespace.ID?
    
    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: activity.weather.iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(activity.weather.tintColor)
            
            Text(activity.weather.cityName)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 8)
        .matchedGeometryIfAvailable(id: "weather_icon_\(activity.id)", in: namespace)
    }
}

public struct WeatherCompactTrailingView: View {
    @ObservedObject public var activity: WeatherActivity
    public let namespace: Namespace.ID?
    
    public var body: some View {
        Text("\(activity.weather.temperature)°")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundColor(activity.weather.tintColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, 8)
            .matchedGeometryIfAvailable(id: "weather_temp_\(activity.id)", in: namespace)
    }
}

public struct WeatherExpandedCardView: View {
    @ObservedObject public var activity: WeatherActivity
    public let controller: DynamicIslandController
    public let namespace: Namespace.ID?
    
    private var w: WeatherData { activity.weather }
    
    private func openMacOSWeatherApp() {
        if let weatherURL = URL(string: "weather://") {
            NSWorkspace.shared.open(weatherURL)
        } else {
            let appUrl = URL(fileURLWithPath: "/System/Applications/Weather.app")
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
    
    public var body: some View {
        VStack(spacing: 9) {
            // Header Row: City, Condition, Temperature & AQI badge + Open macOS Weather.app
            HStack(alignment: .center) {
                Button(action: openMacOSWeatherApp) {
                    HStack(spacing: 8) {
                        Image(systemName: w.iconName)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(w.tintColor)
                            .matchedGeometryIfAvailable(id: "weather_icon_\(activity.id)", in: namespace)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(w.cityName)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Image(systemName: "arrow.up.forward.app.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            
                            Text("\(w.conditionText) • H:\(w.highTemp)° L:\(w.lowTemp)°")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(.white.opacity(0.65))
                        }
                    }
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(w.temperature)°")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .matchedGeometryIfAvailable(id: "weather_temp_\(activity.id)", in: namespace)
                    
                    // AQI Pill
                    HStack(spacing: 3) {
                        Circle()
                            .fill(w.aqiColor)
                            .frame(width: 4, height: 4)
                        Text("AQI \(w.aqi) • \(w.aqiText)")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(w.aqiColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(w.aqiColor.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 4)
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            // Hourly Forecast Timeline
            HStack(spacing: 12) {
                ForEach(w.hourlyForecast) { item in
                    VStack(spacing: 4) {
                        Text(item.timeString)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Image(systemName: item.iconName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(item.iconName.contains("sun") ? Color(red: 1.0, green: 0.75, blue: 0.25) : Color(red: 0.45, green: 0.75, blue: 1.0))
                            .frame(height: 14)
                        
                        if item.rainChance > 15 {
                            Text("\(item.rainChance)%")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                        } else {
                            Text("\(item.temp)°")
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 2)
            
            // Quick metrics footer (Humidity, Wind, UV, and macOS Weather app launcher)
            HStack(spacing: 8) {
                WeatherMetricTag(icon: "humidity.fill", text: "\(w.humidity)%")
                WeatherMetricTag(icon: "wind", text: "\(w.windSpeed) \(w.isFahrenheit ? "mph" : "km/h")")
                WeatherMetricTag(icon: "sun.uv", text: "UV \(w.uvIndex)")
                
                Spacer()
                
                Button(action: {
                    WeatherService.shared.isFahrenheit.toggle()
                }) {
                    Text(w.isFahrenheit ? "Switch to °C" : "Switch to °F")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.35, green: 0.75, blue: 1.0))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 4)
    }
}

private struct WeatherMetricTag: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 3.5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text(text)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
