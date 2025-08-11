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
            withAnimation(.easeInOut(duration: 0.3)) {
                self.setFrame(newFrame, display: true)
                self.minSize = NSSize(width: 250, height: 400)
                self.makeKeyAndOrderFront(nil)
            }
        } else {
            self.setFrame(newFrame, display: true)
            self.minSize = NSSize(width: 250, height: 400)
            self.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Menu Bar Manager
class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    
    func createMenuBarIcon() {
        guard statusItem == nil else { return }
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "CopyMac Clipboard")
            image?.size = NSSize(width: 16, height: 16)
            button.image = image
            button.toolTip = "CopyMac Clipboard - Click to open"
            button.action = #selector(menuBarClicked)
            button.target = self
        }
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

// MARK: - Global Hotkey Manager
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
            for (combo, ref) in manager.hotkeyRefs {
                let refID = EventHotKeyID(signature: "CMAC".fourCharCode, id: UInt32(combo.hashValue & 0xFFFF))
                if hotKeyID.id == refID.id && ref != nil {
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
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = NSApp.windows.first {
            window.positionWindowAtMouse(animated: false)
            window.makeKeyAndOrderFront(nil)
        }
        
        isAppVisible = true
    }
    
    func hideApp() {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.orderOut(nil)
            }
            
            NSApp.setActivationPolicy(.accessory)
            self.isAppVisible = false
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
        var keyChar = combo
        
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
            return (350, 600)
        case .large:
            return (450, 750)
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
        Button(action: {
            theme = theme == .light ? .dark : .light
        }) {
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 25)
                    .fill(theme == .dark ?
                          Color(red: 0.15, green: 0.15, blue: 0.45) :
                          Color(red: 0.3, green: 0.65, blue: 0.95)
                    )
                    .frame(width: 80, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 2)
                    )
                
                // Icons layer - always show both sides
                HStack(spacing: 0) {
                    // Left side - Dark mode icons
                    HStack(spacing: 0) {
                        VStack(spacing: 2) {
                            HStack(spacing: 2) {
                                Star(size: 1.5)
                                    .offset(x: 2, y: 2)
                                Spacer()
                            }
                            HStack(spacing: 2) {
                                Spacer()
                                Star(size: 1)
                                    .offset(x: -2, y: 1)
                            }
                            HStack(spacing: 2) {
                                Star(size: 1)
                                    .offset(x: 3, y: -2)
                                Spacer()
                                Star(size: 1.5)
                                    .offset(x: -3, y: 0)
                            }
                        }
                        .frame(width: 20, height: 30)
                        .padding(.leading, 2)
                        
                        CrescentMoon()
                            .padding(.leading, 4)
                    }
                    .frame(width: 40, height: 40)
                    
                    // Right side - Light mode icons
                    ZStack {
                        Sun()
                            .offset(x: 4, y: -3)
                        Cloud()
                            .offset(x: -2, y: 3)
                    }
                    .frame(width: 40, height: 40)
                }
                
                // Circle that covers inactive side
                HStack {
                    if theme == .light {
                        // Light mode - circle on left to cover dark icons
                        Circle()
                            .fill(Color.white)
                            .frame(width: 32, height: 32)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: 1, y: 1)
                            .padding(.leading, 4)
                        Spacer()
                    } else {
                        // Dark mode - circle on right to cover light icons
                        Spacer()
                        Circle()
                            .fill(Color.white)
                            .frame(width: 32, height: 32)
                            .shadow(color: .black.opacity(0.2), radius: 2, x: -1, y: 1)
                            .padding(.trailing, 4)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme == .dark ? "Switch to Light Mode" : "Switch to Dark Mode")
    }
}

struct Star: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 1, height: size * 2)
            Rectangle()
                .fill(Color.white)
                .frame(width: size * 2, height: 1)
        }
        .frame(width: size * 2, height: size * 2)
    }
}

struct CrescentMoon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow)
                .frame(width: 14, height: 14)
            Circle()
                .fill(Color(red: 0.2, green: 0.2, blue: 0.6))
                .frame(width: 14, height: 14)
                .offset(x: 3, y: 0)
        }
        .clipShape(Circle())
        .frame(width: 14, height: 14)
    }
}

struct Sun: View {
    var body: some View {
        ZStack {
            // Sun rays
            ForEach(0..<8) { index in
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 1.5, height: 3)
                    .offset(y: -6)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
            
            // Sun body
            Circle()
                .fill(Color.yellow)
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
    }
}

struct Cloud: View {
    var body: some View {
        HStack(spacing: -1) {
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .offset(y: -1)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
        }
        .frame(width: 14, height: 8)
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
    
    private var changeCount = NSPasteboard.general.changeCount
    private let historyKey = "ClipboardHistory"
    private let maxHistorySize = 100
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
        let filtered = searchText.isEmpty ? items : items.filter { item in
            item.lowercaseContent.contains(searchLowercased)
        }
        return filtered.sorted { first, second in
            if first.isFavorite != second.isFavorite {
                return first.isFavorite
            }
            if first.isFavorite && second.isFavorite {
                return (first.favoritePosition ?? Int.max) < (second.favoritePosition ?? Int.max)
            }
            return first.timestamp > second.timestamp
        }
    }
    
    func pollClipboard() {
        let pb = NSPasteboard.general
        if pb.changeCount != changeCount {
            changeCount = pb.changeCount
            
            if let imageData = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
                handleNewClipboardContent(imageData: imageData)
            } else if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !str.isEmpty {
                handleNewClipboardContent(content: str)
            }
        }
    }
    
    func handleNewClipboardContent(content: String = "", imageData: Data? = nil) {
        if !content.isEmpty {
            if let existingIndex = items.firstIndex(where: { $0.content == content }) {
                let existingItem = items[existingIndex]
                if !existingItem.isFavorite {
                    items.remove(at: existingIndex)
                    var updatedItem = existingItem
                    updatedItem.timestamp = Date()
                    updatedItem.lowercaseContent = content.lowercased()
                    let insertionIndex = items.firstIndex(where: { !$0.isFavorite }) ?? items.count
                    items.insert(updatedItem, at: insertionIndex)
                }
                return
            }
        } else if let imageData = imageData {
            if let existingIndex = items.firstIndex(where: { $0.isImage && $0.imageData == imageData }) {
                let existingItem = items[existingIndex]
                if !existingItem.isFavorite {
                    items.remove(at: existingIndex)
                    var updatedItem = existingItem
                    updatedItem.timestamp = Date()
                    let insertionIndex = items.firstIndex(where: { !$0.isFavorite }) ?? items.count
                    items.insert(updatedItem, at: insertionIndex)
                }
                return
            }
        }
        
        if !content.isEmpty {
            insert(content: content, showToast: false)
        } else if imageData != nil {
            insert(imageData: imageData, showToast: false)
        }
        
        while items.count > maxHistorySize {
            if let lastNonFavoriteIndex = items.lastIndex(where: { !$0.isFavorite }) {
                items.remove(at: lastNonFavoriteIndex)
            } else {
                break
            }
        }
    }
    
    func insert(content: String = "", imageData: Data? = nil, showToast: Bool = true) {
        let insertionIndex = items.firstIndex(where: { !$0.isFavorite }) ?? items.count
        items.insert(ClipboardItem(content: content, imageData: imageData), at: insertionIndex)
        
        if showToast {
            toast("Added")
        }
        saveHistory()
    }
    
    func copy(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        
        if item.isImage, let imageData = item.imageData {
            NSPasteboard.general.setData(imageData, forType: .png)
        } else {
            NSPasteboard.general.setString(item.content, forType: .string)
        }
        
        selectedItem = item
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.selectedItem = nil
        }
        
        toast("Copied")
    }
    
    func showPreviewFor(_ item: ClipboardItem) {
        previewItem = item
        showPreview = true
    }
    
    func hidePreview() {
        showPreview = false
        previewItem = nil
    }
    
    func handleItemTap(_ item: ClipboardItem) {
        highlightedItem = item
        
        let currentCount = clickCount[item.id] ?? 0
        clickCount[item.id] = currentCount + 1
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.clickCount[item.id] = 0
        }
        
        if clickCount[item.id] == 2 {
            copy(item)
            clickCount[item.id] = 0
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
                let insertionIndex = items.firstIndex(where: { !$0.isFavorite }) ?? items.count
                items.insert(updatedItem, at: insertionIndex)
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
                    let insertionIndex = items.firstIndex(where: { !$0.isFavorite }) ?? items.count
                    items.insert(item, at: insertionIndex)
                }
            }
        }
        
        while items.count > maxHistorySize {
            if let lastNonFavoriteIndex = items.lastIndex(where: { !$0.isFavorite }) {
                items.remove(at: lastNonFavoriteIndex)
            } else {
                break
            }
        }
        
        saveHistory()
        toast("Imported \(importedItems.count) items")
    }
    
    private func toast(_ text: String) {
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
        if let appSizeData = try? JSONEncoder().encode(appSize) {
            UserDefaults.standard.set(appSizeData, forKey: "AppSize")
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
        
        if let appSizeData = UserDefaults.standard.data(forKey: "AppSize"),
           let savedAppSize = try? JSONDecoder().decode(AppSize.self, from: appSizeData) {
            appSize = savedAppSize
        }
        
        if let themeData = UserDefaults.standard.data(forKey: "AppTheme"),
           let savedTheme = try? JSONDecoder().decode(Theme.self, from: themeData) {
            theme = savedTheme
        }
    }
}

// MARK: - Main View
struct ClipboardAppView: View {
    @StateObject var vm = ClipboardViewModel()
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var menuBarManager = MenuBarManager()
    @State private var newShortcut: String = ""
    @State private var selectedHotkey: String = "None"
    
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
                contentList
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
                menuBarManager.createMenuBarIcon()
                
                if hotkeyManager.checkAccessibilityPermission() && !vm.keyboardShortcuts.isEmpty {
                    vm.updateGlobalHotkeys()
                }
            }
            .onChange(of: vm.appSize) { _ in
                if let window = NSApp.windows.first {
                    window.positionWindowAtMouse(size: vm.appSize)
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
                
                Text("CopyMac Clipboard")
                    .font(.headline)
            }
            
            Spacer()
            
            Button(action: { vm.showSettings.toggle() }) {
                Image(systemName: "ellipsis")
                    .font(.title2)
                    .padding(20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }
    
    var contentList: some View {
        VStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if vm.filteredItems.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text(vm.searchText.isEmpty ? "Boost your productivity!" : "No matching items found")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(Array(vm.filteredItems.enumerated()), id: \.1.id) { index, item in
                            HStack(spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .frame(width: 25, alignment: .trailing)
                                
                                if item.isImage {
                                    HStack {
                                        if let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                                            Image(nsImage: nsImage)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 24, height: 18)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        } else {
                                            Image(systemName: "photo")
                                                .foregroundColor(.blue)
                                                .frame(width: 24, height: 18)
                                        }
                                        Text("Image")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                } else {
                                    HStack(spacing: 0) {
                                        Text(item.content.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))
                                            .font(.system(size: 14))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .layoutPriority(1)
                                        
                                        HStack(spacing: 4) {
                                            Button {
                                                vm.toggleFavorite(item)
                                            } label: {
                                                Image(systemName: item.isFavorite ? "star.fill" : "star")
                                                    .foregroundColor(item.isFavorite ? .yellow : .gray)
                                                    .frame(width: 16, height: 16)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel(item.isFavorite ? "Unfavorite" : "Favorite")
                                            
                                            Button {
                                                vm.delete(item)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.gray)
                                                    .frame(width: 16, height: 16)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityLabel("Delete")
                                        }
                                        .frame(width: 44)
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                vm.selectedItem?.id == item.id ? Color.blue.opacity(0.3) :
                                vm.highlightedItem?.id == item.id ? Color.blue.opacity(0.15) :
                                Color(NSColor.controlBackgroundColor)
                            )
                            .cornerRadius(6)
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                            .onTapGesture {
                                vm.handleItemTap(item)
                            }
                            .contextMenu {
                                Button("Preview") {
                                    vm.showPreviewFor(item)
                                }
                                Button("Copy") {
                                    vm.copy(item)
                                }
                                if item.isFavorite {
                                    Button("Remove from Favorites") {
                                        vm.toggleFavorite(item)
                                    }
                                } else {
                                    Button("Add to Favorites") {
                                        vm.toggleFavorite(item)
                                    }
                                }
                                Button("Delete") {
                                    vm.delete(item)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }
            
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search clipboard items", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 6)
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
            .padding(.bottom, 8)
        }
    }
    
    var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button {
                    vm.showSettings = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Settings")
            }
            
            Divider()
            
            // Theme Toggle Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Theme")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
                
                HStack {
                    ThemeToggle(theme: $vm.theme)
                    Spacer()
                }
                
                Text("Choose between light and dark appearance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("App Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: $vm.appSize) {
                    Text("Small").tag(AppSize.small)
                    Text("Large").tag(AppSize.large)
                }
                .pickerStyle(.segmented)
                
                let currentSize = vm.currentDimensions
                Text("Current: \(Int(currentSize.width))×\(Int(currentSize.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Global Shortcuts")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
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
                Text("Import/Export")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
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
                    .fontWeight(.medium)
                
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
            
            Spacer()
        }
        .padding(16)
        .frame(width: vm.currentDimensions.width * 0.9)
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
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
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
                            .frame(maxWidth: vm.currentDimensions.width * 0.7, maxHeight: vm.currentDimensions.height * 0.25)
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
                            Text("\(item.content.count) characters")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ScrollView {
                            Text(item.content)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        .frame(maxHeight: vm.currentDimensions.height * 0.25)
                        
                        HStack {
                            Button("Copy") {
                                vm.copy(item)
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
            
            Spacer()
        }
        .padding(12)
        .frame(width: vm.currentDimensions.width * 0.85)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 8)
        .padding()
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
                    menuBarManager.createMenuBarIcon()
                    if let window = NSApp.windows.first {
                        window.positionWindowAtMouse(animated: false)
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
