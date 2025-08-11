import SwiftUI
import AppKit
import Cocoa
import Carbon

// MARK: - Extensions for Mouse Position
extension NSScreen {
    static func screenContaining(point: NSPoint) -> NSScreen? {
        return NSScreen.screens.first { screen in
            return screen.frame.contains(point)
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
        GlobalHotkeyManager.shared.showAppAtMouse()
    }
}

// MARK: - Global Hotkey Manager
class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var isAppVisible = true
    
    @Published var isRegistered = false
    
    private init() {}
    
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
            let mouseLocation = NSEvent.mouseLocation
            
            if let currentScreen = NSScreen.screenContaining(point: mouseLocation) {
                let windowWidth: CGFloat = 350
                let windowHeight: CGFloat = 600
                
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
                
                let newFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
                window.setFrame(newFrame, display: true)
            }
            
            window.makeKeyAndOrderFront(nil)
        }
        
        isAppVisible = true
    }
    
    func hideApp() {
        for window in NSApp.windows {
            window.orderOut(nil)
        }
        
        NSApp.setActivationPolicy(.accessory)
        isAppVisible = false
    }
    
    func registerHotkey(_ keyCombo: String) {
        let hasPermission = AXIsProcessTrusted()
        
        if !hasPermission {
            return
        }
        
        unregisterHotkey()
        
        guard let (keyCode, modifiers) = parseKeyCombo(keyCombo) else {
            return
        }
        
        let hotKeyID = EventHotKeyID(signature: OSType(0x68747472), id: 1)
        
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            isRegistered = true
            installEventHandler()
        } else {
            isRegistered = false
        }
    }
    
    func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            isRegistered = false
        }
    }
    
    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                DispatchQueue.main.async {
                    GlobalHotkeyManager.shared.handleHotkeyPress()
                }
                return noErr
            },
            1,
            &eventSpec,
            nil,
            nil
        )
    }
    
    private func handleHotkeyPress() {
        DispatchQueue.main.async {
            if self.isAppVisible {
                self.hideApp()
            } else {
                self.showAppAtMouse()
            }
        }
    }
    
    private func parseKeyCombo(_ combo: String) -> (keyCode: CGKeyCode, modifiers: UInt32)? {
        var modifiers: UInt32 = 0
        var keyChar = ""
        
        let lowerCombo = combo.lowercased()
        
        if combo.contains("⌘") || lowerCombo.contains("cmd") || lowerCombo.contains("command") {
            modifiers |= UInt32(cmdKey)
        }
        if combo.contains("⇧") || lowerCombo.contains("shift") {
            modifiers |= UInt32(shiftKey)
        }
        if combo.contains("⌃") || lowerCombo.contains("ctrl") || lowerCombo.contains("control") {
            modifiers |= UInt32(controlKey)
        }
        if combo.contains("⌥") || lowerCombo.contains("alt") || lowerCombo.contains("opt") || lowerCombo.contains("option") {
            modifiers |= UInt32(optionKey)
        }
        
        var cleanCombo = combo.uppercased()
        let modifierSymbols = ["⌘", "⇧", "⌃", "⌥", "CMD", "SHIFT", "CTRL", "ALT", "OPT", "CONTROL", "OPTION", "COMMAND"]
        let separators = ["+", " ", "-", "_"]
        
        for symbol in modifierSymbols {
            cleanCombo = cleanCombo.replacingOccurrences(of: symbol, with: "")
        }
        
        for separator in separators {
            cleanCombo = cleanCombo.replacingOccurrences(of: separator, with: "")
        }
        
        keyChar = cleanCombo.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let keyCode = charToKeyCode(keyChar) else {
            return nil
        }
        
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
            "M": 46, ".": 47, "`": 50, "SPACE": 49, "RETURN": 36, "TAB": 48,
            "DELETE": 51, "ESCAPE": 53, "F1": 122, "F2": 120, "F3": 99,
            "F4": 118, "F5": 96, "F6": 97, "F7": 98, "F8": 100, "F9": 101,
            "F10": 109, "F11": 103, "F12": 111, "ESC": 53, "ENTER": 36,
            "BACKSPACE": 51, "UP": 126, "DOWN": 125, "LEFT": 123, "RIGHT": 124
        ]
        
        return keyMap[char]
    }
    
    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Please enable accessibility access in System Preferences > Security & Privacy > Privacy > Accessibility"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Cancel")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                } else {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
                }
            }
        }
        return trusted
    }
    
    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:"
        ]
        
        for urlString in urls {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                break
            }
        }
    }
}

// MARK: - Model
struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    var content: String
    var imageData: Data?
    var timestamp: Date
    var isFavorite: Bool
    var favoritePosition: Int?
    
    init(content: String = "", imageData: Data? = nil, isFavorite: Bool = false) {
        self.id = UUID()
        self.content = content
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
    var colorScheme: ColorScheme? {
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

// MARK: - Window Delegate
class WindowDelegate: NSObject, NSWindowDelegate {
    weak var viewModel: ClipboardViewModel?
    
    init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
        super.init()
    }
    
    func windowDidResize(_ notification: Notification) {
        // No action needed - window size is fixed
    }
}

// MARK: - ViewModel
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var searchText = ""
    @Published var theme: Theme = .light
    @Published var appSize: AppSize = .small
    @Published var showSettings = false
    @Published var showToast = false
    @Published var toastText = ""
    @Published var keyboardShortcuts: [String] = ["⌘⇧V"]
    @Published var newContent = ""
    @Published var markFavorite = false
    @Published var showClearConfirm = false
    @Published var selectedItem: ClipboardItem?
    @Published var newShortcut = ""
    @Published var clickCount: [UUID: Int] = [:]
    @Published var showPreview = false
    @Published var previewItem: ClipboardItem?
    @Published var highlightedItem: ClipboardItem?
    
    // Keep a strong reference to the window delegate
    private var windowDelegate: WindowDelegate?
    
    private var changeCount = NSPasteboard.general.changeCount
    private let historyKey = "ClipboardHistory"
    
    var currentDimensions: (width: CGFloat, height: CGFloat) {
        return appSize.dimensions
    }
    
    init() {
        loadSettings()
        loadHistory()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.pollClipboard()
        }
    }
    
    func setupWindowDelegate() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                self.windowDelegate = WindowDelegate(viewModel: self)
                window.delegate = self.windowDelegate
                
                // Keep window resizable for programmatic changes but hide resize controls
                window.styleMask.insert(.resizable)
                window.standardWindowButton(.zoomButton)?.isHidden = true
                
                // Apply initial size
                let size = self.currentDimensions
                window.minSize = NSSize(width: size.width, height: size.height)
                window.maxSize = NSSize(width: size.width, height: size.height)
            }
        }
    }
    
    func updateCustomSizeFromWindow() {
        // No longer needed - sizes are fixed
    }
    
    // Apply the selected preset size
    func applyPresetSize() {
        print("applyPresetSize called for: \(appSize)")
        
        DispatchQueue.main.async {
            if let window = NSApp.windows.first {
                let newSize = self.currentDimensions
                
                print("Current window size: \(window.frame.size)")
                print("Target size: \(newSize)")
                
                // Update window constraints to allow the new size
                window.minSize = NSSize(width: newSize.width, height: newSize.height)
                window.maxSize = NSSize(width: newSize.width, height: newSize.height)
                
                // Get current window position (keep the window centered or maintain position)
                let currentFrame = window.frame
                let centerX = currentFrame.midX
                let centerY = currentFrame.midY
                
                // Create new frame centered on the same position
                let newFrame = NSRect(
                    x: centerX - (newSize.width / 2),
                    y: centerY - (newSize.height / 2),
                    width: newSize.width,
                    height: newSize.height
                )
                
                print("Setting frame to: \(newFrame)")
                
                // Apply the new frame with animation
                window.setFrame(newFrame, display: true, animate: true)
                
                self.saveSettings()
                
                // Verify the change after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    print("Final window size: \(window.frame.size)")
                }
            } else {
                print("No window found!")
            }
        }
    }
    
    func moveFavoriteToPosition(_ item: ClipboardItem, to newPosition: Int) {
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }),
              items[currentIndex].isFavorite else { return }
        
        var favorites = items.filter { $0.isFavorite }
            .sorted { ($0.favoritePosition ?? 0) < ($1.favoritePosition ?? 0) }
        
        let nonFavorites = items.filter { !$0.isFavorite }
        
        guard let movingItemIndex = favorites.firstIndex(where: { $0.id == item.id }) else { return }
        
        let movingItem = favorites.remove(at: movingItemIndex)
        let clampedPosition = max(0, min(newPosition, favorites.count))
        favorites.insert(movingItem, at: clampedPosition)
        
        for (index, _) in favorites.enumerated() {
            favorites[index].favoritePosition = index
        }
        
        items = favorites + nonFavorites
        
        saveHistory()
        toast("Favorite order updated")
    }
    
    var filteredItems: [ClipboardItem] {
        items
            .filter { searchText.isEmpty || $0.content.localizedCaseInsensitiveContains(searchText) }
            .sorted { first, second in
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
            }
            else if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !str.isEmpty {
                handleNewClipboardContent(content: str)
            }
        }
    }
    
    private func handleNewClipboardContent(content: String = "", imageData: Data? = nil) {
        if !content.isEmpty {
            if let existingIndex = items.firstIndex(where: { $0.content == content }) {
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
        saveHistory()
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
    
    func addManualItem() {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if let existingIndex = items.firstIndex(where: { $0.content == trimmed }) {
            let existingItem = items[existingIndex]
            if !existingItem.isFavorite || markFavorite {
                items.remove(at: existingIndex)
                var updatedItem = existingItem
                updatedItem.timestamp = Date()
                updatedItem.isFavorite = markFavorite
                
                if markFavorite {
                    let maxPosition = items.filter { $0.isFavorite }.compactMap { $0.favoritePosition }.max() ?? -1
                    updatedItem.favoritePosition = maxPosition + 1
                    items.insert(updatedItem, at: 0)
                } else {
                    updatedItem.favoritePosition = nil
                    let insertionIndex = items.firstIndex(where: { !$0.isFavorite }) ?? items.count
                    items.insert(updatedItem, at: insertionIndex)
                }
            }
        } else {
            let newItem = ClipboardItem(content: trimmed, isFavorite: markFavorite)
            
            if markFavorite {
                let maxPosition = items.filter { $0.isFavorite }.compactMap { $0.favoritePosition }.max() ?? -1
                var itemWithPosition = newItem
                itemWithPosition.favoritePosition = maxPosition + 1
                items.insert(itemWithPosition, at: 0)
            } else {
                let insertionIndex = items.firstIndex(where: { !$0.isFavorite }) ?? items.count
                items.insert(newItem, at: insertionIndex)
            }
        }
        
        newContent = ""
        markFavorite = false
        saveHistory()
    }
    
    func clearNonFavorites() {
        items.removeAll { !$0.isFavorite }
        saveHistory()
    }
    
    func clearAllData() {
        items.removeAll()
        saveHistory()
    }
    
    func addShortcut() {
        let trimmed = newShortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty && !keyboardShortcuts.contains(trimmed) else { return }
        keyboardShortcuts.append(trimmed)
        newShortcut = ""
        saveSettings()
        updateGlobalHotkey()
    }
    
    func removeShortcut(_ shortcut: String) {
        keyboardShortcuts.removeAll { $0 == shortcut }
        if keyboardShortcuts.isEmpty {
            keyboardShortcuts = ["⌘⇧V"]
        }
        saveSettings()
        updateGlobalHotkey()
    }
    
    func updateGlobalHotkey() {
        if let firstShortcut = keyboardShortcuts.first {
            GlobalHotkeyManager.shared.registerHotkey(firstShortcut)
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
    
    func saveSettings() {
        UserDefaults.standard.set(keyboardShortcuts, forKey: "KeyboardShortcuts")
        if let appSizeData = try? JSONEncoder().encode(appSize) {
            UserDefaults.standard.set(appSizeData, forKey: "AppSize")
        }
    }
    
    private func loadSettings() {
        if let savedShortcuts = UserDefaults.standard.array(forKey: "KeyboardShortcuts") as? [String],
           !savedShortcuts.isEmpty {
            keyboardShortcuts = savedShortcuts
        }
        
        if let appSizeData = UserDefaults.standard.data(forKey: "AppSize"),
           let savedAppSize = try? JSONDecoder().decode(AppSize.self, from: appSizeData) {
            appSize = savedAppSize
        }
    }
}

// MARK: - Array Uniquing
extension Array {
    func uniqued<T: Hashable>(by key: (Element) -> T) -> [Element] {
        var seen = Set<T>()
        return self.filter { seen.insert(key($0)).inserted }
    }
}

// MARK: - Main View
struct ClipboardAppView: View {
    @StateObject var vm = ClipboardViewModel()
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var menuBarManager = MenuBarManager()
    
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                contentList
                Divider()
                searchBar
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
                
                // Apply the saved size and set up window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    vm.setupWindowDelegate()
                    vm.applyPresetSize()
                }
                
                if hotkeyManager.checkAccessibilityPermission() {
                    if let firstShortcut = vm.keyboardShortcuts.first {
                        hotkeyManager.registerHotkey(firstShortcut)
                    }
                }
            }
            // Remove automatic resizing
            .modifier(OnChangeModifier(appSize: vm.appSize) {
                // No automatic actions
            })
            
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
        ScrollView {
            LazyVStack(spacing: 0) {
                if vm.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Boost your productivity!")
                            .font(.headline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 60)
                } else if vm.filteredItems.isEmpty && !vm.searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No items found")
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
                                        .font(.system(size: 13))
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
                                
                                Menu("Change Order") {
                                    Button("Move to Top") {
                                        vm.moveFavoriteToPosition(item, to: 0)
                                    }
                                    Button("Move Up") {
                                        let currentPos = item.favoritePosition ?? 0
                                        vm.moveFavoriteToPosition(item, to: max(0, currentPos - 1))
                                    }
                                    Button("Move Down") {
                                        let currentPos = item.favoritePosition ?? 0
                                        let maxPos = vm.items.filter { $0.isFavorite }.count - 1
                                        vm.moveFavoriteToPosition(item, to: min(maxPos, currentPos + 1))
                                    }
                                    Button("Move to Bottom") {
                                        let maxPos = vm.items.filter { $0.isFavorite }.count - 1
                                        vm.moveFavoriteToPosition(item, to: maxPos)
                                    }
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
    }
    
    var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search...", text: $vm.searchText)
                .textFieldStyle(.plain)
            if !vm.searchText.isEmpty {
                Button(action: { vm.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
    
    var settingsPanel: some View {
        let settingsContent = VStack(alignment: .leading, spacing: vm.appSize == .small ? 12 : 16) {
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
            
            VStack(alignment: .leading, spacing: vm.appSize == .small ? 6 : 8) {
                Text("Add Manual Entry")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("Enter text", text: $vm.newContent)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: vm.appSize == .small ? 12 : 13))
                Toggle("Add To Favorites", isOn: $vm.markFavorite)
                    .font(.system(size: vm.appSize == .small ? 12 : 13))
                Button("Add Entry") {
                    vm.addManualItem()
                }
                .font(.system(size: vm.appSize == .small ? 12 : 13))
                .disabled(vm.newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: vm.appSize == .small ? 6 : 8) {
                Text("App Size")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("", selection: $vm.appSize) {
                    Text("Small").tag(AppSize.small)
                    Text("Large").tag(AppSize.large)
                }
                .pickerStyle(SegmentedPickerStyle())
                .modifier(SizePickerModifier(appSize: vm.appSize, viewModel: vm))
                
                let currentSize = vm.currentDimensions
                Text("Current: \(Int(currentSize.width))×\(Int(currentSize.height))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: vm.appSize == .small ? 6 : 8) {
                Text("Theme")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Picker("", selection: $vm.theme) {
                    ForEach(Theme.allCases, id: \.self) { theme in
                        Text(theme.rawValue.capitalized)
                            .font(.system(size: vm.appSize == .small ? 12 : 13))
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: vm.appSize == .small ? 6 : 8) {
                HStack {
                    Text("Shortcuts")
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
                
                ForEach(vm.keyboardShortcuts, id: \.self) { shortcut in
                    HStack {
                        Text(shortcut)
                            .font(.system(size: vm.appSize == .small ? 11 : 13, design: .monospaced))
                            .padding(vm.appSize == .small ? 4 : 6)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        if vm.keyboardShortcuts.count > 1 {
                            Button {
                                vm.removeShortcut(shortcut)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: vm.appSize == .small ? 12 : 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                VStack(spacing: vm.appSize == .small ? 4 : 6) {
                    HStack {
                        TextField(vm.appSize == .small ? "⌃⌥C, ⌘K" : "Enter shortcut (e.g., ⌃⌥C, ⌘K)", text: $vm.newShortcut)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: vm.appSize == .small ? 11 : 13, design: .monospaced))
                            .onSubmit {
                                vm.addShortcut()
                            }
                        
                        Button("Add") {
                            vm.addShortcut()
                        }
                        .font(.system(size: vm.appSize == .small ? 11 : 13))
                        .disabled(vm.newShortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    if vm.appSize == .large {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Examples: ⌘⇧V, ⌃⌥C, ⌘K, F1")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if !hotkeyManager.isRegistered && !AXIsProcessTrusted() {
                                Text("⚠️ Accessibility permission required")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                
                                Button("Open System Preferences") {
                                    hotkeyManager.openAccessibilitySettings()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                
                Button("Apply Current Shortcut") {
                    vm.updateGlobalHotkey()
                }
                .font(.system(size: vm.appSize == .small ? 11 : 13))
                .buttonStyle(.borderedProminent)
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
                    .font(.system(size: vm.appSize == .small ? 11 : 13))
                    
                    Button("Import History") {
                        vm.importHistory()
                    }
                    .font(.system(size: vm.appSize == .small ? 11 : 13))
                }
                
                if vm.appSize == .large {
                    Text("Export/import .txt files to share between devices or backup your clipboard history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: vm.appSize == .small ? 6 : 8) {
                Text("Clear History")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Button("Clear") {
                    vm.showClearConfirm = true
                }
                .font(.system(size: vm.appSize == .small ? 11 : 13))
                .foregroundColor(.red)
                
                if vm.showClearConfirm {
                    VStack(alignment: .leading, spacing: vm.appSize == .small ? 6 : 8) {
                        Text(vm.appSize == .small ? "Clear non-favorites?" : "Clear all clipboard items (excluding favorites)?")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Button("Cancel") {
                                vm.showClearConfirm = false
                            }
                            .font(.system(size: vm.appSize == .small ? 11 : 13))
                            Button("Confirm") {
                                vm.clearNonFavorites()
                                vm.showClearConfirm = false
                            }
                            .font(.system(size: vm.appSize == .small ? 11 : 13))
                            .foregroundColor(.red)
                        }
                    }
                    .padding(vm.appSize == .small ? 6 : 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
            
            Spacer()
        }
        .padding(vm.appSize == .small ? 12 : 16)
        
        return Group {
            if vm.appSize == .small {
                ScrollView {
                    settingsContent
                }
                .frame(width: vm.currentDimensions.width * 0.95, height: vm.currentDimensions.height * 0.8)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(radius: 10)
                .padding(vm.appSize == .small ? 8 : 16)
            } else {
                settingsContent
                    .frame(width: vm.currentDimensions.width * 0.95)
                    .background(Color(.windowBackgroundColor))
                    .cornerRadius(12)
                    .shadow(radius: 10)
                    .padding(vm.appSize == .small ? 8 : 16)
            }
        }
    }
    
    var previewPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                    VStack(spacing: 12) {
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
                    VStack(alignment: .leading, spacing: 12) {
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
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        }
                        .frame(maxHeight: vm.currentDimensions.height * 0.4)
                        
                        HStack {
                            Button("Copy") {
                                vm.copy(item)
                                vm.hidePreview()
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button("Close") {
                                vm.hidePreview()
                            }
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: vm.currentDimensions.width * 0.9)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding()
    }
}

// MARK: - Custom Modifier for onChange compatibility
struct OnChangeModifier: ViewModifier {
    let appSize: AppSize
    let action: () -> Void
    
    func body(content: Content) -> some View {
        // Remove automatic resizing - let user control the window
        content
    }
}

// MARK: - Size Picker Modifier for compatibility
struct SizePickerModifier: ViewModifier {
    let appSize: AppSize
    let viewModel: ClipboardViewModel
    @State private var previousSize: AppSize? = nil
    
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .onChange(of: appSize) { oldValue, newValue in
                    // Immediately resize window when picker changes
                    if oldValue != newValue {
                        print("🔄 Size picker changed from \(oldValue) to \(newValue)")
                        // Use a small delay to ensure the UI update completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            viewModel.applyPresetSize()
                        }
                    }
                }
        } else {
            content
                .onAppear {
                    previousSize = appSize
                }
                .onReceive(viewModel.$appSize) { newSize in
                    // For older macOS versions
                    if let prev = previousSize, newSize != prev {
                        print("🔄 Size picker changed from \(prev) to \(newSize)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            viewModel.applyPresetSize()
                        }
                    }
                    previousSize = newSize
                }
        }
    }
}

// MARK: - Entry Point with Mouse Positioning
@main
struct CopyMacApp: App {
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    
    var body: some Scene {
        WindowGroup {
            ClipboardAppView()
                .onAppear {
                    positionWindowAtMouse()
                    
                    if hotkeyManager.checkAccessibilityPermission() {
                        hotkeyManager.registerHotkey("⌘⇧V")
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
    
    private func positionWindowAtMouse() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first else { return }
            
            let mouseLocation = NSEvent.mouseLocation
            
            guard let currentScreen = NSScreen.screenContaining(point: mouseLocation) else {
                return
            }
            
            let windowWidth: CGFloat = AppSize.small.dimensions.width
            let windowHeight: CGFloat = AppSize.small.dimensions.height
            
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
            
            window.setFrame(newFrame, display: true)
            window.minSize = NSSize(width: 250, height: 400)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
