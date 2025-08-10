import SwiftUI
import AppKit
import Carbon
import Foundation

// MARK: - Extensions for Mouse Position
extension NSScreen {
    static func screenContaining(point: NSPoint) -> NSScreen? {
        return NSScreen.screens.first { screen in
            screen.frame.contains(point)
        }
    }
}

// MARK: - NSWindow Extension for Positioning
extension NSWindow {
    func positionWindowAtMouse(size: AppSize = .small, animated: Bool = true) {
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screenContaining(point: mouseLocation) ?? NSScreen.main!
        
        let windowWidth: CGFloat = size.dimensions.width
        let windowHeight: CGFloat = size.dimensions.height
        
        var windowX = mouseLocation.x - (windowWidth / 2)
        var windowY = mouseLocation.y - (windowHeight / 2)
        
        let screenFrame = currentScreen.visibleFrame
        
        if windowX < screenFrame.minX {
            windowX = screenFrame.minX + 20
        } else if windowX + windowWidth > screenFrame.maxX {
            windowX = screenFrame.maxX - windowWidth - 20
        }
        
        if windowY < screenFrame.minY {
            windowY = screenFrame.minY + 20
        } else if windowY + windowHeight > screenFrame.maxY {
            windowY = screenFrame.maxY - windowHeight - 20
        }
        
        let newFrame = NSRect(
            x: windowX,
            y: windowY,
            width: windowWidth,
            height: windowHeight
        )
        
        if animated {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.95)) {
                self.setFrame(newFrame, display: true)
                self.minSize = NSSize(width: 280, height: 380)
                self.makeKeyAndOrderFront(nil)
            }
        } else {
            self.setFrame(newFrame, display: true)
            self.minSize = NSSize(width: 280, height: 380)
            self.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Menu Bar Manager
class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()
    private var statusItem: NSStatusItem?
    @Published var isMenuBarEnabled = false
    
    private init() {}
    
    func createMenuBarIcon() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyMac")
            button.action = #selector(menuBarClicked)
            button.target = self
        }
        isMenuBarEnabled = true
    }
    
    func removeMenuBarIcon() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        isMenuBarEnabled = false
    }
    
    @objc private func menuBarClicked() {
        DispatchQueue.main.async {
            GlobalHotkeyManager.shared.toggleAppVisibility()
        }
    }
}

// MARK: - Global Hotkey Manager
class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()
    private var hotkeyRefs: [String: EventHotKeyRef] = [:]
    private var isAppVisible = false
    @Published var isRegistered = false
    @Published var permissionGranted = false
    private var eventHandler: EventHandlerRef?
    private static var permissionRequestInProgress = false
    private var permissionCheckTimer: Timer?
    
    private init() {
        setupEventHandler()
        startPermissionMonitoring()
        loadPermissionState()
    }
    
    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let result = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                guard let nextHandler = nextHandler,
                      let event = event,
                      let userData = userData else {
                    return noErr
                }
                return GlobalHotkeyManager.staticEventHandler(nextHandler: nextHandler, event: event, userData: userData)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        if result != noErr {
            print("Failed to install event handler: \(result)")
        }
    }
    
    private static func staticEventHandler(nextHandler: EventHandlerCallRef, event: EventRef, userData: UnsafeMutableRawPointer) -> OSStatus {
        let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let size = MemoryLayout<EventHotKeyID>.size
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            size,
            nil,
            &hotKeyID
        )
        if status == noErr {
            for (combo, _) in manager.hotkeyRefs {
                let refID = EventHotKeyID(signature: "CMAC".fourCharCode, id: UInt32(combo.hashValue & 0xFFFF))
                if hotKeyID.id == refID.id {
                    manager.toggleAppVisibility()
                    break
                }
            }
        }
        return noErr
    }
    
    private func startPermissionMonitoring() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePermissionStatus()
        }
        RunLoop.current.add(permissionCheckTimer!, forMode: .common)
        updatePermissionStatus()
    }
    
    private func updatePermissionStatus() {
        let wasGranted = permissionGranted
        permissionGranted = AXIsProcessTrusted()
        
        if permissionGranted != wasGranted {
            print("Permission state changed: \(permissionGranted ? "Granted" : "Revoked")")
            do {
                try savePermissionState()
            } catch {
                print("Failed to save permission state: \(error)")
            }
            DispatchQueue.main.async {
                if self.permissionGranted {
                    NotificationCenter.default.post(name: NSNotification.Name("AccessibilityPermissionGranted"), object: nil)
                    ClipboardViewModel.shared.updateGlobalHotkeys()
                } else {
                    NotificationCenter.default.post(name: NSNotification.Name("AccessibilityPermissionRevoked"), object: nil)
                    ClipboardViewModel.shared.updateGlobalHotkeys()
                }
            }
        }
    }
    
    private func savePermissionState() throws {
        let defaults = UserDefaults.standard
        defaults.set(permissionGranted, forKey: "AccessibilityPermissionGranted")
        // Verify write
        if defaults.bool(forKey: "AccessibilityPermissionGranted") != permissionGranted {
            throw NSError(domain: "CopyMac", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save accessibility permission state"])
        }
        print("Saved permission state: \(permissionGranted)")
    }
    
    private func loadPermissionState() {
        let defaults = UserDefaults.standard
        permissionGranted = defaults.bool(forKey: "AccessibilityPermissionGranted")
        let systemPermission = AXIsProcessTrusted()
        if permissionGranted != systemPermission {
            permissionGranted = systemPermission
            do {
                try savePermissionState()
            } catch {
                print("Failed to save permission state during load: \(error)")
            }
        }
        print("Loaded permission state: \(permissionGranted)")
    }
    
    func toggleAppVisibility() {
        DispatchQueue.main.async {
            if self.isAppVisible {
                self.hideApp()
            } else {
                self.showAppAtMouse()
            }
        }
    }
    
    func showApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        
        isAppVisible = true
    }
    
    func showAppAtMouse() {
        NSApp.setActivationPolicy(.regular)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            NSApp.activate(ignoringOtherApps: true)
            
            if let window = NSApp.windows.first {
                window.positionWindowAtMouse(animated: true)
                window.makeKeyAndOrderFront(nil)
            }
            
            self.isAppVisible = true
        }
    }
    
    func hideApp() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.95)) {
            for window in NSApp.windows {
                window.orderOut(nil)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.setActivationPolicy(.accessory)
            self.isAppVisible = false
            
            NotificationCenter.default.post(name: NSNotification.Name("AppWillHide"), object: nil)
        }
    }
    
    func hasAccessibilityPermission() -> Bool {
        let isTrusted = AXIsProcessTrusted()
        print("Checked accessibility permission: \(isTrusted)")
        return isTrusted
    }
    
    func requestAccessibilityPermission() {
        guard !Self.permissionRequestInProgress else {
            print("Permission request already in progress")
            return
        }
        
        Self.permissionRequestInProgress = true
        print("Requesting accessibility permission")
        
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // Immediate check after request
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.updatePermissionStatus()
            Self.permissionRequestInProgress = false
        }
    }
    
    func registerHotkey(_ keyCombo: String) -> Bool {
        print("Attempting to register hotkey: \(keyCombo)")
        
        guard hasAccessibilityPermission() else {
            print("Hotkey registration failed: No accessibility permission")
            isRegistered = false
            return false
        }
        
        guard let (keyCode, modifiers) = parseKeyCombo(keyCombo) else {
            print("Hotkey registration failed: Invalid key combo \(keyCombo)")
            return false
        }
        
        let reservedShortcuts = ["⌘V", "⌘C", "⌘X", "⌘Z"]
        if reservedShortcuts.contains(where: { $0 == keyCombo }) {
            print("Hotkey registration failed: \(keyCombo) is a reserved shortcut")
            return false
        }
        
        if hotkeyRefs[keyCombo] != nil {
            print("Hotkey already registered: \(keyCombo)")
            return true
        }
        
        var hotkeyRef: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: "CMAC".fourCharCode, id: UInt32(keyCombo.hashValue & 0xFFFF))
        
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if status == noErr, let ref = hotkeyRef {
            hotkeyRefs[keyCombo] = ref
            print("Hotkey registered successfully: \(keyCombo)")
            isRegistered = !hotkeyRefs.isEmpty
            return true
        }
        
        print("Hotkey registration failed with status: \(status)")
        return false
    }
    
    func unregisterHotkey(_ keyCombo: String) {
        if let ref = hotkeyRefs[keyCombo] {
            UnregisterEventHotKey(ref)
            hotkeyRefs.removeValue(forKey: keyCombo)
            print("Unregistered hotkey: \(keyCombo)")
        }
        isRegistered = !hotkeyRefs.isEmpty
    }
    
    func unregisterAllHotkeys() {
        for (combo, ref) in hotkeyRefs {
            UnregisterEventHotKey(ref)
            print("Unregistered hotkey: \(combo)")
        }
        hotkeyRefs.removeAll()
        isRegistered = false
    }
    
    func parseKeyCombo(_ combo: String) -> (keyCode: CGKeyCode, modifiers: UInt32)? {
        var modifiers: UInt32 = 0
        let keyChar = combo
        
        let modifierSymbols = ["⌘", "⇧", "⌃", "⌥", "⇪", "⇥", " ", "↑", "↓", "←", "→"]
        let replacements = ["", "", "", "", "", "TAB", "SPACE", "UP", "DOWN", "LEFT", "RIGHT"]
        
        var cleanedCombo = keyChar
        for (symbol, replacement) in zip(modifierSymbols, replacements) {
            cleanedCombo = cleanedCombo.replacingOccurrences(of: symbol, with: replacement)
        }
        cleanedCombo = cleanedCombo.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let baseKey = cleanedCombo.isEmpty ? keyChar : String(cleanedCombo.suffix(1))
        
        if keyChar.range(of: "⌘") != nil { modifiers |= UInt32(cmdKey) }
        if keyChar.range(of: "⇧") != nil { modifiers |= UInt32(shiftKey) }
        if keyChar.range(of: "⌃") != nil { modifiers |= UInt32(controlKey) }
        if keyChar.range(of: "⌥") != nil { modifiers |= UInt32(optionKey) }
        if keyChar.range(of: "⇪") != nil { modifiers |= 0x10000 }
        
        let cleanKey = baseKey.uppercased()
        guard let keyCode = charToKeyCode(cleanKey) else {
            print("Invalid key code for: \(cleanKey)")
            return nil
        }
        
        print("Parsed combo \(combo): keyCode = \(keyCode), modifiers = \(String(format: "0x%X", modifiers))")
        return (keyCode, modifiers)
    }
    
    private func charToKeyCode(_ char: String) -> CGKeyCode? {
        let keyMap: [String: CGKeyCode] = [
            "V": 9, "C": 8, "X": 7, "Z": 6, "A": 0, "S": 1, "D": 2, "F": 3,
            "H": 4, "G": 5, "Q": 12, "W": 13, "E": 14, "R": 15, "Y": 16,
            "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30,
            "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37, "J": 38,
            "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "N": 45,
            "M": 46, ".": 47, "`": 50, "§": 10, "SPACE": 49, "RETURN": 36,
            "TAB": 48, "DELETE": 51, "ESCAPE": 53, "F1": 122, "F2": 120,
            "F3": 99, "F4": 118, "F5": 96, "F6": 97, "F7": 98, "F8": 100,
            "F9": 101, "F10": 109, "F11": 103, "F12": 111, "UP": 126,
            "DOWN": 125, "LEFT": 123, "RIGHT": 124
        ]
        
        return keyMap[char]
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
            print("Opened Accessibility settings")
        }
    }
    
    deinit {
        permissionCheckTimer?.invalidate()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
        unregisterAllHotkeys()
    }
}

// MARK: - String Extension for FourCharCode
extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        let utf16 = self.utf16
        for char in utf16.prefix(4) {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}

// MARK: - Model
struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    var content: String
    var lowercaseContent: String
    var imageData: Data?
    var timestamp: Date
    var isFavorite: Bool
    var favoritePosition: Int?
    
    enum CodingKeys: String, CodingKey {
        case id, content, lowercaseContent, imageData, timestamp, isFavorite, favoritePosition
    }
    
    init(content: String = "", imageData: Data? = nil, isFavorite: Bool = false) {
        self.id = UUID()
        self.content = content
        self.lowercaseContent = content.lowercased()
        self.imageData = imageData
        self.timestamp = Date()
        self.isFavorite = isFavorite
        self.favoritePosition = nil
    }
    
    var isImage: Bool {
        return imageData != nil
    }
}

// MARK: - Theme
enum Theme: String, CaseIterable, Codable {
    case light, dark
    var colorScheme: ColorScheme {
        self == .light ? .light : .dark
    }
}

// MARK: - App Size Setting
enum AppSize: String, CaseIterable, Codable {
    case small = "Small"
    case large = "Large"
    
    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .small:
            return (340, 340)
        case .large:
            return (340, 460)
        }
    }
}

// MARK: - Keyboard Shortcut
struct KeyboardShortcut: Codable, Identifiable {
    let id: UUID
    let combo: String
    
    enum CodingKeys: String, CodingKey {
        case id, combo
    }
    
    init(combo: String) {
        self.id = UUID()
        self.combo = combo
    }
}

// MARK: - Theme Toggle Components
struct ThemeToggle: View {
    @Binding var theme: Theme
    
    var body: some View {
        HStack(spacing: 16) {
            // Light Mode Button
            VStack(spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        theme = .light
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(theme == .light ?
                                  Color.orange.opacity(0.1) :
                                  Color.gray.opacity(0.05))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(theme == .light ?
                                           Color.orange.opacity(0.3) :
                                           Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme == .light ?
                                           Color.orange :
                                           Color.gray.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                
                Text("Light")
                    .font(.caption2)
                    .foregroundColor(theme == .light ?
                                   Color.primary :
                                   Color.gray.opacity(0.6))
                    .fontWeight(theme == .light ? .medium : .regular)
            }
            
            // Dark Mode Button
            VStack(spacing: 6) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        theme = .dark
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(theme == .dark ?
                                  Color.blue.opacity(0.1) :
                                  Color.gray.opacity(0.05))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Circle()
                                    .stroke(theme == .dark ?
                                           Color.blue.opacity(0.3) :
                                           Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        
                        Image(systemName: "moon.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme == .dark ?
                                           Color.blue :
                                           Color.gray.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
                
                Text("Dark")
                    .font(.caption2)
                    .foregroundColor(theme == .dark ?
                                   Color.primary :
                                   Color.gray.opacity(0.6))
                    .fontWeight(theme == .dark ? .medium : .regular)
            }
        }
        .accessibilityLabel("Theme Selection")
    }
}

// MARK: - ViewModel
class ClipboardViewModel: ObservableObject {
    static let shared = ClipboardViewModel()
    
    @Published var items: [ClipboardItem] = []
    @Published var theme: Theme = .light {
        didSet {
            do {
                try saveSettings()
            } catch {
                print("Failed to save settings in theme didSet: \(error)")
                toast("Failed to save theme settings")
            }
        }
    }
    @Published var appSize: AppSize = .small
    @Published var showSettings = false
    @Published var showToast = false
    @Published var toastText = ""
    @Published var keyboardShortcuts: [KeyboardShortcut] = []
    @Published var showClearConfirm = false
    @Published var selectedItem: ClipboardItem?
    @Published var clickCount: [UUID: Int] = [:]
    @Published var showPreview = false
    @Published var previewItem: ClipboardItem?
    @Published var highlightedItem: ClipboardItem?
    @Published var searchText: String = "" {
        didSet {
            debounceSearch()
        }
    }
    @Published var showReturnToTop = false
    @Published var useMenuBarMode: Bool = false {
        didSet {
            do {
                try saveSettings()
            } catch {
                print("Failed to save settings in useMenuBarMode didSet: \(error)")
                toast("Failed to save menu bar settings")
            }
            updateAppMode()
        }
    }
    
    private var changeCount = NSPasteboard.general.changeCount
    private let historyKey = "ClipboardHistory"
    private var searchWorkItem: DispatchWorkItem?
    
    var currentDimensions: (width: CGFloat, height: CGFloat) {
        return appSize.dimensions
    }
    
    init() {
        loadSettings()
        loadHistory()
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pollClipboard()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppWillHide"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearSelectionStates()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AccessibilityPermissionGranted"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onPermissionGranted()
        }
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AccessibilityPermissionRevoked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onPermissionRevoked()
        }
        
        // Initial hotkey registration check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.checkAndRegisterHotkeys()
        }
    }
    
    private func updateAppMode() {
        if useMenuBarMode {
            MenuBarManager.shared.createMenuBarIcon()
            toast("Menu Bar mode activated")
        } else {
            MenuBarManager.shared.removeMenuBarIcon()
        }
    }
    
    private func checkAndRegisterHotkeys() {
        if !keyboardShortcuts.isEmpty && GlobalHotkeyManager.shared.hasAccessibilityPermission() {
            updateGlobalHotkeys()
        }
    }
    
    private func onPermissionGranted() {
        print("Permission granted notification received")
        updateGlobalHotkeys()
        toast("Accessibility permission granted - shortcuts activated")
    }
    
    private func onPermissionRevoked() {
        print("Permission revoked notification received")
        toast("Accessibility permission revoked - shortcuts disabled")
    }
    
    private func clearSelectionStates() {
        selectedItem = nil
        highlightedItem = nil
        clickCount.removeAll()
    }
    
    private func debounceSearch() {
        searchWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.objectWillChange.send()
        }
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    var filteredItems: [ClipboardItem] {
        let searchLowercased = searchText.lowercased()
        
        if searchText.isEmpty {
            let favorites = items.filter { $0.isFavorite }.sorted { (a, b) in
                (a.favoritePosition ?? 0) < (b.favoritePosition ?? 0)
            }
            let nonFavorites = items.filter { !$0.isFavorite }.sorted { $0.timestamp > $1.timestamp }
            return favorites + nonFavorites
        } else {
            return items.filter { $0.lowercaseContent.contains(searchLowercased) }
        }
    }
    
    func pollClipboard() {
        let pb = NSPasteboard.general
        if pb.changeCount != changeCount {
            changeCount = pb.changeCount
            
            if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                handleNewClipboardContent(content: str)
            } else if let imageData = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
                handleNewClipboardContent(imageData: imageData)
            }
        }
    }
    
    func handleNewClipboardContent(content: String = "", imageData: Data? = nil) {
        if !content.isEmpty {
            if items.contains(where: { $0.content == content }) {
                return
            }
            insert(content: content, showToast: false)
        } else if imageData != nil {
            if items.contains(where: { $0.isImage && $0.imageData == imageData }) {
                return
            }
            insert(imageData: imageData, showToast: false)
        }
    }
    
    func insert(content: String = "", imageData: Data? = nil, isFavorite: Bool = false, showToast: Bool = true) {
        let newItem = ClipboardItem(content: content, imageData: imageData, isFavorite: isFavorite)
        
        items.insert(newItem, at: 0)
        
        if showToast {
            toast(isFavorite ? "Favorite Added" : "Item Added")
        }
        
        saveHistory()
        
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    func copy(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        
        if item.isImage, let imageData = item.imageData {
            NSPasteboard.general.setData(imageData, forType: .png)
        } else {
            NSPasteboard.general.setString(item.content, forType: .string)
        }
        
        selectedItem = item
        toast("Copied")
        
        if !item.isFavorite {
            moveItemToTop(item)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            GlobalHotkeyManager.shared.hideApp()
        }
    }
    
    func copyFromPreview(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        
        if item.isImage, let imageData = item.imageData {
            NSPasteboard.general.setData(imageData, forType: .png)
        } else {
            NSPasteboard.general.setString(item.content, forType: .string)
        }
        
        selectedItem = item
        toast("Copied")
        
        if !item.isFavorite {
            moveItemToTop(item)
        }
    }
    
    private func moveItemToTop(_ item: ClipboardItem) {
        if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
            let itemToMove = items[currentIndex]
            items.remove(at: currentIndex)
            
            let favoriteCount = items.filter { $0.isFavorite }.count
            var updatedItem = itemToMove
            updatedItem.timestamp = Date()
            items.insert(updatedItem, at: favoriteCount)
            
            saveHistory()
        }
    }
    
    func showPreviewFor(_ item: ClipboardItem) {
        DispatchQueue.main.async {
            self.previewItem = item
            self.showPreview = true
        }
    }
    
    func hidePreview() {
        showPreview = false
        previewItem = nil
    }
    
    func handleItemTap(_ item: ClipboardItem) {
        highlightedItem = item
        
        let currentCount = clickCount[item.id] ?? 0
        clickCount[item.id] = currentCount + 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.clickCount[item.id] = 0
        }
        
        if clickCount[item.id] == 2 {
            copy(item)
            clickCount[item.id] = 0
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if self.clickCount[item.id] == 0 {
                    self.highlightedItem = nil
                }
            }
        }
    }
    
    func toggleFavorite(_ item: ClipboardItem) {
        if let idx = items.firstIndex(of: item) {
            var updatedItem = items[idx]
            updatedItem.isFavorite.toggle()
            
            items.remove(at: idx)
            
            if updatedItem.isFavorite {
                let maxPosition = items.filter { $0.isFavorite }.compactMap { $0.favoritePosition }.max() ?? -1
                updatedItem.favoritePosition = maxPosition + 1
                items.insert(updatedItem, at: 0)
            } else {
                updatedItem.favoritePosition = nil
                let favoriteCount = items.filter { $0.isFavorite }.count
                items.insert(updatedItem, at: favoriteCount)
            }
            saveHistory()
        }
    }
    
    func delete(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        saveHistory()
    }
    
    func clearNonFavorites() {
        items.removeAll { !$0.isFavorite }
        saveHistory()
    }
    
    func moveFavoriteUp(_ item: ClipboardItem) {
        guard item.isFavorite, let currentIndex = items.firstIndex(of: item) else { return }
        
        let favoritesBeforeCurrent = items[..<currentIndex].filter { $0.isFavorite }
        guard let targetItem = favoritesBeforeCurrent.last,
              let targetIndex = items.firstIndex(of: targetItem) else { return }
        
        items.swapAt(currentIndex, targetIndex)
        updateFavoritePositions()
        saveHistory()
        toast("Moved up")
    }
    
    func moveFavoriteDown(_ item: ClipboardItem) {
        guard item.isFavorite, let currentIndex = items.firstIndex(of: item) else { return }
        
        let favoritesAfterCurrent = items[(currentIndex + 1)...].filter { $0.isFavorite }
        guard let targetItem = favoritesAfterCurrent.first,
              let targetIndex = items.firstIndex(of: targetItem) else { return }
        
        items.swapAt(currentIndex, targetIndex)
        updateFavoritePositions()
        saveHistory()
        toast("Moved down")
    }
    
    private func updateFavoritePositions() {
        let favoriteItems = items.filter { $0.isFavorite }
        for (index, item) in favoriteItems.enumerated() {
            if let itemIndex = items.firstIndex(where: { $0.id == item.id }) {
                items[itemIndex].favoritePosition = index
            }
        }
    }
    
    func addShortcut(key: String, modifier: String) {
        print("Adding shortcut - key: '\(key)', modifier: '\(modifier)'")
        
        if modifier == "None" {
            print("No modifier selected - Carbon requires at least one modifier")
            toast("Please select a modifier key (⌘, ⌥, ⌃, or ⇧)")
            return
        }
        
        let modifierMap: [String: String] = [
            "Command (⌘)": "⌘",
            "Option (⌥)": "⌥",
            "Control (⌃)": "⌃",
            "Shift (⇧)": "⇧",
            "Caps Lock (⇪)": "⇪",
            "Tab (⇥)": "⇥",
            "Space": " ",
            "Up Arrow (↑)": "↑",
            "Down Arrow (↓)": "↓",
            "Left Arrow (←)": "←",
            "Right Arrow (→)": "→"
        ]
        
        let fullCombo = (modifierMap[modifier] ?? "") + key
        print("Full combo created: '\(fullCombo)'")
        
        if keyboardShortcuts.contains(where: { $0.combo == fullCombo }) {
            print("Shortcut already exists: \(fullCombo)")
            toast("Shortcut already exists")
            return
        }
        
        // Save the shortcut
        keyboardShortcuts.append(KeyboardShortcut(combo: fullCombo))
        do {
            try saveSettings()
        } catch {
            print("Failed to save settings: \(error)")
            toast("Failed to save shortcut - check storage permissions")
            keyboardShortcuts.removeAll { $0.combo == fullCombo }
            return
        }
        
        // Attempt registration
        if GlobalHotkeyManager.shared.hasAccessibilityPermission() {
            attemptHotkeyRegistration(fullCombo: fullCombo)
        } else {
            print("No accessibility permission - requesting...")
            toast("Please grant accessibility permission in System Settings to activate shortcuts")
            GlobalHotkeyManager.shared.requestAccessibilityPermission()
        }
    }
    
    private func attemptHotkeyRegistration(fullCombo: String) {
        if GlobalHotkeyManager.shared.registerHotkey(fullCombo) {
            print("Shortcut registered successfully: \(fullCombo)")
            toast("Shortcut registered: \(fullCombo)")
        } else {
            print("Failed to register shortcut: \(fullCombo)")
            toast("Failed to register shortcut - try a different combination")
            keyboardShortcuts.removeAll { $0.combo == fullCombo }
            do {
                try saveSettings()
            } catch {
                print("Failed to save settings after removing failed shortcut: \(error)")
            }
        }
    }
    
    func removeShortcut(_ shortcut: String) {
        keyboardShortcuts.removeAll { $0.combo == shortcut }
        GlobalHotkeyManager.shared.unregisterHotkey(shortcut)
        do {
            try saveSettings()
        } catch {
            print("Failed to save settings after removing shortcut: \(error)")
            toast("Failed to save settings - check storage permissions")
        }
        toast("Shortcut removed")
    }
    
    func updateGlobalHotkeys() {
        print("Updating all global hotkeys")
        GlobalHotkeyManager.shared.unregisterAllHotkeys()
        
        guard GlobalHotkeyManager.shared.hasAccessibilityPermission() else {
            print("Cannot register hotkeys: No accessibility permission")
            toast("Accessibility permission required for shortcuts")
            return
        }
        
        var successCount = 0
        var failedShortcuts: [String] = []
        
        for shortcut in keyboardShortcuts {
            if GlobalHotkeyManager.shared.registerHotkey(shortcut.combo) {
                successCount += 1
                print("Registered shortcut: \(shortcut.combo)")
            } else {
                print("Failed to register: \(shortcut.combo)")
                failedShortcuts.append(shortcut.combo)
            }
        }
        
        // Remove failed shortcuts
        keyboardShortcuts.removeAll { failedShortcuts.contains($0.combo) }
        do {
            try saveSettings()
        } catch {
            print("Failed to save settings after updating hotkeys: \(error)")
            toast("Failed to save shortcut settings")
        }
        
        if successCount > 0 {
            toast("\(successCount) shortcut(s) activated")
        } else if !keyboardShortcuts.isEmpty {
            toast("Failed to register shortcuts - try different combinations")
        }
    }
    
    func exportHistory() {
        let textItems = items.compactMap { item -> String? in
            if item.isImage {
                return nil
            }
            
            let prefix = item.isFavorite ? "[FAVORITE] " : ""
            return prefix + item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        
        let exportContent = textItems.joined(separator: "\n---\n")
        
        let savePanel = NSSavePanel()
        savePanel.title = "Export Clipboard History"
        savePanel.nameFieldStringValue = "clipboard_history.txt"
        savePanel.allowedContentTypes = [.plainText]
        
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try exportContent.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.toast("Exported \(textItems.count) items")
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.toast("Export failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    func importHistory() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Import Clipboard History"
        openPanel.allowedContentTypes = [.plainText]
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                do {
                    let fileContent = try String(contentsOf: url, encoding: .utf8)
                    DispatchQueue.main.async {
                        self.processImportedText(fileContent)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.toast("Import failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func processImportedText(_ text: String) {
        let entries = text.components(separatedBy: "\n---\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var importedItems: [ClipboardItem] = []
        
        for entry in entries {
            let isFavorite = entry.hasPrefix("[FAVORITE] ")
            let content = isFavorite ? String(entry.dropFirst(11)) : entry
            
            if !content.isEmpty {
                var item = ClipboardItem(content: content, isFavorite: isFavorite)
                if isFavorite {
                    item.favoritePosition = importedItems.filter { $0.isFavorite }.count
                }
                importedItems.append(item)
            }
        }
        
        for item in importedItems.reversed() {
            if !items.contains(where: { $0.content == item.content }) {
                if item.isFavorite {
                    let maxPosition = items.filter { $0.isFavorite }.compactMap { $0.favoritePosition }.max() ?? -1
                    var updatedItem = item
                    updatedItem.favoritePosition = maxPosition + 1
                    items.insert(updatedItem, at: 0)
                } else {
                    let favoriteCount = items.filter { $0.isFavorite }.count
                    items.insert(item, at: favoriteCount)
                }
            }
        }
        
        saveHistory()
        toast("Imported \(importedItems.count) items")
    }
    
    func toast(_ text: String) {
        toastText = text
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.showToast = false
        }
    }
    
    private func saveHistory() {
        do {
            if let data = try? JSONEncoder().encode(items) {
                UserDefaults.standard.set(data, forKey: historyKey)
                if UserDefaults.standard.data(forKey: historyKey) == nil {
                    throw NSError(domain: "CopyMac", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to save clipboard history"])
                }
                print("Saved clipboard history")
            }
        } catch {
            print("Failed to save history: \(error)")
            toast("Failed to save clipboard history")
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let savedItems = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = savedItems
            print("Loaded clipboard history: \(items.count) items")
        }
    }
    
    private func saveSettings() throws {
        let defaults = UserDefaults.standard
        if let shortcutData = try? JSONEncoder().encode(keyboardShortcuts) {
            defaults.set(shortcutData, forKey: "KeyboardShortcuts")
            if defaults.data(forKey: "KeyboardShortcuts") == nil {
                throw NSError(domain: "CopyMac", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to save keyboard shortcuts"])
            }
        }
        if let themeData = try? JSONEncoder().encode(theme) {
            defaults.set(themeData, forKey: "AppTheme")
            if defaults.data(forKey: "AppTheme") == nil {
                throw NSError(domain: "CopyMac", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to save theme settings"])
            }
        }
        defaults.set(useMenuBarMode, forKey: "UseMenuBarMode")
        print("Saved settings: \(keyboardShortcuts.count) shortcuts, theme: \(theme.rawValue), menuBar: \(useMenuBarMode)")
    }
    
    private func loadSettings() {
        if let shortcutData = UserDefaults.standard.data(forKey: "KeyboardShortcuts"),
           let savedShortcuts = try? JSONDecoder().decode([KeyboardShortcut].self, from: shortcutData) {
            keyboardShortcuts = savedShortcuts
            print("Loaded \(keyboardShortcuts.count) shortcuts")
        }
        
        if let themeData = UserDefaults.standard.data(forKey: "AppTheme"),
           let savedTheme = try? JSONDecoder().decode(Theme.self, from: themeData) {
            theme = savedTheme
            print("Loaded theme: \(theme.rawValue)")
        }
        
        useMenuBarMode = UserDefaults.standard.bool(forKey: "UseMenuBarMode")
        if useMenuBarMode {
            updateAppMode()
        }
    }
}

// MARK: - Main View
@available(macOS 12.0, *)
struct ClipboardAppView: View {
    @StateObject var vm = ClipboardViewModel.shared
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var menuBarManager = MenuBarManager.shared
    @State private var newShortcut: String = ""
    @State private var selectedHotkey: String = "Command (⌘)"
    @State private var manualText: String = ""
    @State private var addToFavorites: Bool = false
    
    private let availableHotkeys = [
        "Command (⌘)",
        "Option (⌥)",
        "Control (⌃)",
        "Shift (⇧)",
        "Caps Lock (⇪)",
        "Tab (⇥)",
        "Space",
        "Up Arrow (↑)",
        "Down Arrow (↓)",
        "Left Arrow (←)",
        "Right Arrow (→)"
    ]
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                mainContent
            }
            .preferredColorScheme(vm.theme.colorScheme)
            .frame(
                minWidth: vm.currentDimensions.width,
                maxWidth: .infinity,
                minHeight: vm.currentDimensions.height,
                maxHeight: .infinity
            )
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !vm.keyboardShortcuts.isEmpty && hotkeyManager.hasAccessibilityPermission() {
                        vm.updateGlobalHotkeys()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                if !vm.keyboardShortcuts.isEmpty && hotkeyManager.hasAccessibilityPermission() && !hotkeyManager.isRegistered {
                    vm.updateGlobalHotkeys()
                }
            }
            
            if vm.showSettings { settingsPanel }
            if vm.showPreview { previewPanel }
            
            if vm.showToast {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(vm.toastText)
                            .padding(8)
                            .background(Color.black.opacity(0.85))
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        Spacer()
                    }
                    Spacer()
                }
                .padding()
                .allowsHitTesting(false)
            }
        }
    }
    
    var header: some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text("CopyMac")
                    .font(.headline)
            }
            
            Spacer()
            
            Button(action: {
                NotificationCenter.default.post(name: NSNotification.Name("ScrollToTop"), object: nil)
            }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(
                            colors: [Color.blue, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 18, height: 18)
                    
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Return to Top")
            
            Button(action: { vm.showSettings.toggle() }) {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }
    
    var mainContent: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if vm.filteredItems.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "doc.on.clipboard")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                
                                if vm.searchText.isEmpty {
                                    Text("Copy some text to get started!")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                } else {
                                    Text("No matching items found")
                                        .font(.headline)
                                        .foregroundColor(.gray)
                                    Text("Try a different search term")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.top, 60)
                            .id("topAnchor")
                        } else {
                            Color.clear
                                .frame(height: 1)
                                .id("topAnchor")
                            
                            ForEach(Array(vm.filteredItems.enumerated()), id: \.1.id) { index, item in
                                itemRow(item: item, index: index)
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToTop"))) { _ in
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("topAnchor", anchor: .top)
                    }
                }
            }
            
            searchBar
        }
    }
    
    func itemRow(item: ClipboardItem, index: Int) -> some View {
        HStack(spacing: 2) {
            Text(String(format: "%d.", index + 1))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
            
            if item.isImage {
                imageContent(item: item)
            } else {
                textContent(item: item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.top, 0)
        .padding(.bottom, 24)
        .background(rowBackground(item: item, index: index))
        .cornerRadius(3)
        .padding(.horizontal, 1)
        .onTapGesture {
            vm.handleItemTap(item)
        }
        .contextMenu {
            contextMenuContent(item: item)
        }
    }
    
    func imageContent(item: ClipboardItem) -> some View {
        HStack {
            Text("Image")
                .font(.system(size: 10))
                .foregroundColor(.primary)
            
            if let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo")
                    .foregroundColor(.blue)
                    .frame(width: 20, height: 15)
            }
            
            Spacer()
            
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            }
        }
    }
    
    func textContent(item: ClipboardItem) -> some View {
        HStack {
            let displayText = item.content.count > 500 ?
                String(item.content.prefix(500)) + "..." :
                item.content
            
            Text(displayText.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
            }
        }
    }
    
    func rowBackground(item: ClipboardItem, index: Int) -> Color {
        if vm.selectedItem?.id == item.id {
            return Color.blue.opacity(0.5)
        } else if vm.highlightedItem?.id == item.id {
            return Color.blue.opacity(0.25)
        } else if index % 2 == 0 {
            return vm.theme == .dark ?
                Color(red: 0.08, green: 0.08, blue: 0.08) :
                Color(red: 0.82, green: 0.82, blue: 0.82)
        } else {
            return vm.theme == .dark ?
                Color(red: 0.12, green: 0.12, blue: 0.12) :
                Color(red: 0.88, green: 0.88, blue: 0.88)
        }
    }
    
    @ViewBuilder
    func contextMenuContent(item: ClipboardItem) -> some View {
        Button("Preview") {
            vm.showPreviewFor(item)
        }
        Button("Copy") {
            vm.copy(item)
        }
        
        Divider()
        
        if item.isFavorite {
            Button("Move Up") {
                vm.moveFavoriteUp(item)
            }
            .disabled(vm.items.filter { $0.isFavorite }.first?.id == item.id)
            
            Button("Move Down") {
                vm.moveFavoriteDown(item)
            }
            .disabled(vm.items.filter { $0.isFavorite }.last?.id == item.id)
            
            Divider()
            
            Button("Remove from Favorites") {
                vm.toggleFavorite(item)
            }
        } else {
            Button("Add to Favorites") {
                vm.toggleFavorite(item)
            }
        }
        
        Divider()
        
        Button("Delete") {
            vm.delete(item)
        }
    }
    
    var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search Clipboard Items", text: $vm.searchText)
                .textFieldStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .disabled(vm.showSettings)
            if !vm.searchText.isEmpty {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        .padding(.top, 3)
    }
    
    var settingsPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                HStack {
                    Text("Settings").font(.headline)
                    Spacer()
                    Button {
                        vm.showSettings = false
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 18, height: 18)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Settings")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color(.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Access Mode Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Access Mode")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            // Menu Bar Mode
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                        Text("Menu Bar Mode")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text("(No permission needed)")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                    }
                                    Text("Click menu bar icon to open")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Toggle("", isOn: $vm.useMenuBarMode)
                                    .labelsHidden()
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add Manual Entry")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 8) {
                            TextField("Type your text here", text: $manualText)
                                .textFieldStyle(.plain)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(manualText.isEmpty ? Color.clear : Color.blue, lineWidth: 2)
                                )
                            
                            Button("Add") {
                                if !manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    vm.insert(content: manualText, isFavorite: addToFavorites, showToast: true)
                                    manualText = ""
                                    addToFavorites = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        
                        Toggle("Add to favorites", isOn: $addToFavorites)
                            .font(.caption)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Global Shortcuts")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(hotkeyManager.isRegistered ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(hotkeyManager.isRegistered ? "Active" : "Inactive")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if !hotkeyManager.permissionGranted {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Accessibility permission required for shortcuts")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    
                                    HStack {
                                        Button("Open System Settings") {
                                            hotkeyManager.openAccessibilitySettings()
                                            hotkeyManager.requestAccessibilityPermission()
                                        }
                                        .font(.caption)
                                        .buttonStyle(.borderedProminent)
                                        
                                        Button("Check Permission") {
                                            if hotkeyManager.hasAccessibilityPermission() {
                                                vm.updateGlobalHotkeys()
                                                vm.toast("Permission granted - shortcuts activated")
                                            } else {
                                                vm.toast("Permission not granted - please enable in System Settings")
                                            }
                                        }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        } else if !hotkeyManager.isRegistered && !vm.keyboardShortcuts.isEmpty {
                            HStack {
                                Text("Permission granted but shortcuts not active")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                
                                Button("Activate Shortcuts") {
                                    vm.updateGlobalHotkeys()
                                }
                                .font(.caption)
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        ForEach(vm.keyboardShortcuts) { shortcut in
                            HStack {
                                Text(shortcut.combo)
                                    .font(.system(size: 13, design: .monospaced))
                                    .padding(6)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                
                                Spacer()
                                
                                Button {
                                    vm.removeShortcut(shortcut.combo)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add New Shortcut")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("e.g., ` or §", text: $newShortcut)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                
                                Picker("", selection: $selectedHotkey) {
                                    ForEach(availableHotkeys, id: \.self) { hotkey in
                                        Text(hotkey).tag(hotkey)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 150)
                            }
                            
                            Button("Add") {
                                if !newShortcut.isEmpty {
                                    vm.addShortcut(key: newShortcut, modifier: selectedHotkey)
                                    newShortcut = ""
                                    selectedHotkey = "Command (⌘)"
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newShortcut.isEmpty)
                        }
                        .padding(.top, 8)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        ThemeToggle(theme: $vm.theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import/Export")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        HStack(spacing: 12) {
                            Button("Export History") {
                                vm.exportHistory()
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Import History") {
                                vm.importHistory()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clear History")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        
                        Button("Clear") {
                            vm.showClearConfirm = true
                        }
                        .foregroundColor(.red)
                        
                        if vm.showClearConfirm {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Clear all clipboard items (excluding favorites)?")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Button("Cancel") {
                                        vm.showClearConfirm = false
                                    }
                                    Button("Confirm") {
                                        vm.clearNonFavorites()
                                        vm.showClearConfirm = false
                                    }
                                    .foregroundColor(.red)
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                    
                    Text("Version v1.6.3")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                    
                    Spacer()
                        .frame(height: 2)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
        .focusable(false)
        .allowsHitTesting(true)
    }
    
    var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                Button {
                    vm.hidePreview()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 18, height: 18)
                        
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Preview")
            }
            
            if let item = vm.previewItem {
                if item.isImage, let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                    VStack(spacing: 8) {
                        Text("Image Preview")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: vm.currentDimensions.width * 0.8, maxHeight: vm.currentDimensions.height * 0.4)
                            .border(Color.gray.opacity(0.3), width: 1)
                        
                        Text("Size: \(Int(nsImage.size.width)) × \(Int(nsImage.size.height))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text Preview")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(item.content.count) characters")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(item.content.components(separatedBy: .newlines).count) lines")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        ScrollView {
                            if item.content.count > 50000 {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(0..<min(50, item.content.count / 1000), id: \.self) { chunkIndex in
                                        let startIndex = chunkIndex * 1000
                                        let endIndex = min(startIndex + 1000, item.content.count)
                                        let chunk = String(item.content[item.content.index(item.content.startIndex, offsetBy: startIndex)..<item.content.index(item.content.startIndex, offsetBy: endIndex)])
                                        
                                        Text(chunk)
                                            .font(.system(size: 13, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            } else {
                                Text(item.content)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(6)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxHeight: vm.currentDimensions.height * 0.5)
                        
                        HStack {
                            Button("Copy") {
                                vm.copyFromPreview(item)
                                vm.hidePreview()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button("Close") {
                                vm.hidePreview()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: vm.currentDimensions.width * 0.95, height: vm.currentDimensions.height * 0.85)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 8)
        .padding(8)
    }
}

// MARK: - Entry Point
@available(macOS 12.0, *)
struct CopyMacApp: App {
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var menuBarManager = MenuBarManager.shared
    
    var body: some Scene {
        WindowGroup {
            ClipboardAppView()
                .onAppear {
                    print("CopyMac app started")
                    if let window = NSApp.windows.first {
                        window.positionWindowAtMouse(animated: true)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Clipboard") {
                Button("Toggle Clipboard") {
                    hotkeyManager.toggleAppVisibility()
                }
                .keyboardShortcut("`", modifiers: [])
            }
        }
    }
}

// Manual entry point - only use if @main doesn't work
CopyMacApp.main()
