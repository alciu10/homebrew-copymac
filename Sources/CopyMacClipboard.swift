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

// MARK: - Menu Bar Manager (Simplified)
class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    
    func createMenuBarIcon() {
        return
    }
    
    func removeMenuBarIcon() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
    
    @objc private func menuBarClicked() {
        DispatchQueue.main.async {
            GlobalHotkeyManager.shared.toggleAppVisibility()
        }
    }
}

// MARK: - Global Hotkey Manager (Simplified)
class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()
    private var hotkeyRefs: [String: EventHotKeyRef] = [:]
    private var isAppVisible = false
    @Published var isRegistered = false
    private var eventHandler: EventHandlerRef?

    private init() {
        setupEventHandler()
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
            
            // Clear any selected/highlighted items when hiding the app
            NotificationCenter.default.post(name: NSNotification.Name("AppWillHide"), object: nil)
        }
    }
    
    func registerHotkey(_ keyCombo: String) -> Bool {
        guard checkAccessibilityPermission() else {
            print("Hotkey registration failed: Accessibility permission denied")
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
            print("Hotkey registration failed: \(keyCombo) is already registered")
            return false
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
        }
        isRegistered = !hotkeyRefs.isEmpty
    }
    
    func unregisterAllHotkeys() {
        for (_, ref) in hotkeyRefs {
            UnregisterEventHotKey(ref)
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
        if keyChar.range(of: "🌐") != nil || keyChar.range(of: "fn") != nil {
            print("Fn key is not supported for hotkey registration")
            return nil
        }
        
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
    
    func checkAccessibilityPermission() -> Bool {
        let options: [String: Any] = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "CopyMac Clipboard needs accessibility access to register global hotkeys. Please enable it in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                openAccessibilitySettings()
            }
        }
        return trusted
    }
    
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
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
    @Published var items: [ClipboardItem] = []
    @Published var theme: Theme = .light {
        didSet {
            saveSettings()
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
        updateGlobalHotkeys()
        
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AppWillHide"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearSelectionStates()
        }
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
        // SIMPLE LOGIC - NO COMPLEX SORTING
        let searchLowercased = searchText.lowercased()
        
        if searchText.isEmpty {
            // Return ALL items, favorites first
            let favorites = items.filter { $0.isFavorite }.sorted { (a, b) in
                (a.favoritePosition ?? 0) < (b.favoritePosition ?? 0)
            }
            let nonFavorites = items.filter { !$0.isFavorite }.sorted { $0.timestamp > $1.timestamp }
            return favorites + nonFavorites
        } else {
            // Filter by search
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
            // Check if this content already exists
            if items.contains(where: { $0.content == content }) {
                return // Don't add duplicates
            }
            insert(content: content, showToast: false)
        } else if imageData != nil {
            // Check if this image already exists
            if items.contains(where: { $0.isImage && $0.imageData == imageData }) {
                return // Don't add duplicates
            }
            insert(imageData: imageData, showToast: false)
        }
    }
    
    func insert(content: String = "", imageData: Data? = nil, isFavorite: Bool = false, showToast: Bool = true) {
        // DEAD SIMPLE INSERT LOGIC
        let newItem = ClipboardItem(content: content, imageData: imageData, isFavorite: isFavorite)
        
        // Just add to beginning of array - simple!
        items.insert(newItem, at: 0)
        
        if showToast {
            toast(isFavorite ? "Favorite Added" : "Item Added")
        }
        
        saveHistory()
        
        // Force UI update
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
        
        // Move copied item to top (under favorites) if it's not a favorite
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
        
        // Move copied item to top (under favorites) if it's not a favorite
        if !item.isFavorite {
            moveItemToTop(item)
        }
        
        // Don't close the app when copying from preview
    }
    
    private func moveItemToTop(_ item: ClipboardItem) {
        // Find and remove the item from its current position
        if let currentIndex = items.firstIndex(where: { $0.id == item.id }) {
            let itemToMove = items[currentIndex]
            items.remove(at: currentIndex)
            
            // Insert after all favorites (at the top of non-favorites)
            let favoriteCount = items.filter { $0.isFavorite }.count
            var updatedItem = itemToMove
            updatedItem.timestamp = Date() // Update timestamp to mark as recently used
            items.insert(updatedItem, at: favoriteCount)
            
            // Save the updated order
            saveHistory()
        }
    }
    
    func showPreviewFor(_ item: ClipboardItem) {
        // Use async to prevent UI blocking
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
                // Insert after all favorites
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
        
        let fullCombo = modifier == "None" ? key : (modifierMap[modifier] ?? "") + key
        if keyboardShortcuts.contains(where: { $0.combo == fullCombo }) {
            toast("Shortcut already exists")
            return
        }
        
        if GlobalHotkeyManager.shared.registerHotkey(fullCombo) {
            keyboardShortcuts.append(KeyboardShortcut(combo: fullCombo))
            saveSettings()
            toast("Shortcut added")
        } else {
            toast("Invalid or reserved shortcut")
        }
    }
    
    func removeShortcut(_ shortcut: String) {
        keyboardShortcuts.removeAll { $0.combo == shortcut }
        GlobalHotkeyManager.shared.unregisterHotkey(shortcut)
        saveSettings()
        toast("Shortcut removed")
    }
    
    func updateGlobalHotkeys() {
        GlobalHotkeyManager.shared.unregisterAllHotkeys()
        for shortcut in keyboardShortcuts {
            _ = GlobalHotkeyManager.shared.registerHotkey(shortcut.combo)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.showToast = false
        }
    }
    
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let savedItems = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = savedItems
        }
    }
    
    private func saveSettings() {
        if let shortcutData = try? JSONEncoder().encode(keyboardShortcuts) {
            UserDefaults.standard.set(shortcutData, forKey: "KeyboardShortcuts")
        }
        if let themeData = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(themeData, forKey: "AppTheme")
        }
    }
    
    private func loadSettings() {
        if let shortcutData = UserDefaults.standard.data(forKey: "KeyboardShortcuts"),
           let savedShortcuts = try? JSONDecoder().decode([KeyboardShortcut].self, from: shortcutData) {
            keyboardShortcuts = savedShortcuts
        }
        
        if let themeData = UserDefaults.standard.data(forKey: "AppTheme"),
           let savedTheme = try? JSONDecoder().decode(Theme.self, from: themeData) {
            theme = savedTheme
        }
    }
}

// MARK: - Main View
@available(macOS 12.0, *)
struct ClipboardAppView: View {
    @StateObject var vm = ClipboardViewModel()
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var menuBarManager = MenuBarManager()
    @State private var newShortcut: String = ""
    @State private var selectedHotkey: String = "None"
    @State private var manualText: String = ""
    @State private var addToFavorites: Bool = false
    
    private let availableHotkeys = [
        "None",
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
                
                if hotkeyManager.checkAccessibilityPermission() && !vm.keyboardShortcuts.isEmpty {
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
            
            // Return to Top Button with app icon styling (smaller)
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
                            // Top anchor for scrolling
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
            // Optimize long text display in list by truncating for display only
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
            // Sticky Header
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
            
            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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
                                    selectedHotkey = "None"
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newShortcut.isEmpty)
                        }
                        .padding(.top, 8)
                        
                        if !hotkeyManager.isRegistered && !AXIsProcessTrusted() {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Accessibility permission required")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    
                                    Button("Open System Settings") {
                                        hotkeyManager.openAccessibilitySettings()
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
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
                    
                    Text("Version v1.5.0")
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
                        
                        // Optimized text display with chunking for very long content
                        ScrollView {
                            if item.content.count > 50000 {
                                // For very long text, use chunked loading
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
                                // For normal text, use regular display
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
@main
struct CopyMacApp: App {
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var menuBarManager = MenuBarManager()
    
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
