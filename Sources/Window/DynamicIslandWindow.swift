import AppKit
import SwiftUI

/// Custom content hosting view that fits the Dynamic Island window exactly and captures trackpad swipes & drag-and-drop.
public final class DynamicIslandHostingView<Content: View>: NSHostingView<Content> {
    private var trackingArea: NSTrackingArea?
    private var lastScrollTime: Date = Date.distantPast
    
    @MainActor public required init(rootView: Content) {
        super.init(rootView: rootView)
        setupDragRegistration()
    }
    
    @MainActor required dynamic init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDragRegistration()
    }
    
    private func setupDragRegistration() {
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .string,
            .fileContents,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        ])
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        self.trackingArea = area
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupDragRegistration()
    }
    
    // MARK: - NSDraggingDestination
    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        let urls = extractURLs(from: pasteboard)
        let hasFileTypes = pasteboard.types?.contains(.fileURL) == true ||
                           pasteboard.types?.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) == true ||
                           pasteboard.types?.contains(NSPasteboard.PasteboardType("public.file-url")) == true
        
        if !urls.isEmpty || hasFileTypes {
            DispatchQueue.main.async {
                FileShelfService.shared.isDropTargeted = true
                if DynamicIslandController.shared.state == .idle {
                    DynamicIslandController.shared.transition(to: .compact)
                }
            }
            return .copy
        }
        return []
    }
    
    public override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        let urls = extractURLs(from: pasteboard)
        let hasFileTypes = pasteboard.types?.contains(.fileURL) == true ||
                           pasteboard.types?.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) == true ||
                           pasteboard.types?.contains(NSPasteboard.PasteboardType("public.file-url")) == true
        
        if !urls.isEmpty || hasFileTypes {
            if !FileShelfService.shared.isDropTargeted {
                DispatchQueue.main.async {
                    FileShelfService.shared.isDropTargeted = true
                }
            }
            return .copy
        }
        return []
    }
    
    public override func draggingExited(_ sender: NSDraggingInfo?) {
        DispatchQueue.main.async {
            FileShelfService.shared.isDropTargeted = false
        }
    }
    
    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        DispatchQueue.main.async {
            FileShelfService.shared.isDropTargeted = false
        }
        let pasteboard = sender.draggingPasteboard
        let urls = extractURLs(from: pasteboard)
        
        if !urls.isEmpty {
            DispatchQueue.main.async {
                FileShelfService.shared.addFiles(urls: urls)
                let shelfAct = FileShelfActivity(files: FileShelfService.shared.files)
                DynamicIslandController.shared.activityManager.presentActivity(shelfAct)
                DynamicIslandController.shared.transition(to: .expanded)
            }
            return true
        }
        return false
    }
    
    private func extractURLs(from pasteboard: NSPasteboard) -> [URL] {
        var results: [URL] = []
        
        // 1. NSFilenamesPboardType (Standard Finder Drag Format)
        if let filenames = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for path in filenames {
                results.append(URL(fileURLWithPath: path))
            }
        }
        
        // 2. Read NSURL objects
        if results.isEmpty, let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            results.append(contentsOf: urls)
        }
        
        // 3. URLs with fileURL reading option
        if results.isEmpty, let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true]) as? [URL] {
            results.append(contentsOf: urls)
        }
        
        // 4. Pasteboard items inspect
        if results.isEmpty, let items = pasteboard.pasteboardItems {
            for item in items {
                for type in item.types {
                    if let stringVal = item.string(forType: type) {
                        if stringVal.hasPrefix("file://"), let u = URL(string: stringVal) {
                            results.append(u)
                        } else if stringVal.hasPrefix("/"), FileManager.default.fileExists(atPath: stringVal) {
                            results.append(URL(fileURLWithPath: stringVal))
                        }
                    }
                }
            }
        }
        
        return results
    }
    
    // Precise shape hit testing: passes clicks through to desktop & underlying apps
    // whenever the mouse is outside the active island capsule / bubble,
    // while providing a generous spring-loaded drop target during file drag operations.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let controller = DynamicIslandController.shared
        let geometry = controller.currentGeometry
        
        let topY = bounds.height
        let bottomY = topY - max(geometry.height, 30.5)
        
        let mainWidth = max(geometry.width, 160)
        let hasSecondary = (controller.state == .compact && controller.activityManager.secondaryActivity != nil)
        let bubbleExtraRight: CGFloat = hasSecondary ? (geometry.height + 20.0) : 0
        
        let minX = (bounds.width - mainWidth) / 2.0
        let maxX = (bounds.width + mainWidth) / 2.0 + bubbleExtraRight
        
        let activeRect = NSRect(x: minX, y: bottomY, width: maxX - minX, height: topY - bottomY)
        
        if activeRect.contains(point) {
            return super.hitTest(point)
        }
        
        // During Drag operations (dragging files from Finder), provide an accessible drop target
        if FileShelfService.shared.isDropTargeted {
            let dropHeight = max(geometry.height, 50.0)
            let dropWidth = max(geometry.width, 340.0)
            let dMinX = (bounds.width - dropWidth) / 2.0
            let dMaxX = (bounds.width + dropWidth) / 2.0
            let dropRect = NSRect(x: dMinX, y: topY - dropHeight, width: dMaxX - dMinX, height: dropHeight)
            if dropRect.contains(point) {
                return self
            }
        }
        
        return nil
    }
    
    // Native macOS Two-Finger Trackpad Horizontal Swipe Detection
    public override func scrollWheel(with event: NSEvent) {
        let now = Date()
        let deltaX = event.scrollingDeltaX
        
        if abs(deltaX) > 4.0 && now.timeIntervalSince(lastScrollTime) > 0.28 {
            lastScrollTime = now
            if deltaX < 0 {
                DynamicIslandController.shared.handleSwipeLeft()
            } else {
                DynamicIslandController.shared.handleSwipeRight()
            }
            return
        }
        
        super.scrollWheel(with: event)
    }
}

/// Borderless, non-activating floating overlay panel positioned at the top edge of the active screen.
public final class DynamicIslandWindow: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isFloatingPanel = true
        self.level = .statusBar
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
        self.acceptsMouseMovedEvents = true
        self.ignoresMouseEvents = false
        
        registerForDraggedTypes([
            .fileURL,
            .URL,
            .string,
            .fileContents,
            NSPasteboard.PasteboardType("public.file-url"),
            NSPasteboard.PasteboardType("public.url"),
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url")
        ])
    }
    
    // Allows keyboard input when in expanded text entry mode, otherwise yields focus to active apps
    public override var canBecomeKey: Bool {
        return DynamicIslandController.shared.state == .expanded
    }
    
    public override var canBecomeMain: Bool {
        return false
    }
}
