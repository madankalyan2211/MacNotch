import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as menu bar accessory / status bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Set custom app icon
        if let iconImage = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = iconImage
        } else if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: iconURL)
        }
        
        // Initialize window manager & island
        _ = WindowManager.shared
        
        // Start Native HUD Interceptor for system volume & brightness suppression
        NativeHUDInterceptor.shared.start()
        
        // Automatically play iconic signature "hello" greeting, which transitions seamlessly into expanded permissions setup if permissions are needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if DynamicIslandController.shared.activityManager.activeActivity == nil {
                DynamicIslandController.shared.triggerHelloSignature()
            }
        }
    }
    
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    public func applicationWillTerminate(_ notification: Notification) {
        NativeHUDInterceptor.shared.stop()
    }
}
