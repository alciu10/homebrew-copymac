import SwiftUI
import AppKit
import Carbon
import Foundation
import QuartzCore
import UniformTypeIdentifiers

// MARK: - Screen helper
extension NSScreen {
    static func screenContaining(point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}

// MARK: - Window positioning
extension NSWindow {
    func positionWindowAtMouse(size: AppSize = .small, animated: Bool = true) {
        let mouseLocation = NSEvent.mouseLocation
        let currentScreen = NSScreen.screenContaining(point: mouseLocation) ?? NSScreen.main!

        let windowWidth: CGFloat = size.dimensions.width
        let windowHeight: CGFloat = size.dimensions.height

        var windowX = mouseLocation.x - windowWidth/2
        var windowY = mouseLocation.y - windowHeight/2

        let screenFrame = currentScreen.visibleFrame

        if windowX < screenFrame.minX { windowX = screenFrame.minX + 20 }
        if windowX + windowWidth > screenFrame.maxX { windowX = screenFrame.maxX - windowWidth - 20 }
        if windowY < screenFrame.minY { windowY = screenFrame.minY + 20 }
        if windowY + windowHeight > screenFrame.maxY { windowY = screenFrame.maxY - windowHeight - 20 }

        let newFrame = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
        self.minSize = NSSize(width: 300, height: 300)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(newFrame, display: true)
            }
        } else {
            self.setFrame(newFrame, display: true)
        }
        self.makeKeyAndOrderFront(nil)
    }
}

// MARK: - FourChar helper
extension String {
    var fourCharCode: FourCharCode {
        var result: FourCharCode = 0
        for char in self.utf16.prefix(4) { result = (result << 8) + FourCharCode(char) }
        return result
    }
}

// MARK: - Menu bar (placeholder)
final class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    func createMenuBarIcon() {}
    func removeMenuBarIcon() {
        if let s = statusItem {
            NSStatusBar.system.removeStatusItem(s)
            statusItem = nil
        }
    }
    @objc private func menuBarClicked() {
        DispatchQueue.main.async { GlobalHotkeyManager.shared.toggleAppVisibility() }
    }
}

// MARK: - Hotkeys (no Accessibility needed)
final class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()

    private var hotkeyRefs: [String: EventHotKeyRef] = [:]
    private var comboToID: [String: UInt32] = [:]
    private var idToCombo: [UInt32: String] = [:]
    private var nextID: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var isAppVisible = false
    @Published var isRegistered = false

    private init() { setupEventHandler() }

    private func setupEventHandler() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event = event, let userData = userData else { return noErr }
                return GlobalHotkeyManager.staticHandler(event: event, userData: userData)
            },
            1, &type, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        if status != noErr { print("InstallEventHandler failed: \(status)") }
    }

    private static func staticHandler(event: EventRef, userData: UnsafeMutableRawPointer) -> OSStatus {
        let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        var hkID = EventHotKeyID()
        let ok = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil, &hkID)
        if ok == noErr, manager.idToCombo[hkID.id] != nil {
            manager.toggleAppVisibility()
        }
        return noErr
    }

    // Visibility
    func toggleAppVisibility() {
        DispatchQueue.main.async { self.isAppVisible ? self.hideApp() : self.showAppAtMouse() }
    }
    func showAppAtMouse() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.positionWindowAtMouse(animated: true)
            self.isAppVisible = true
        }
    }
    func hideApp() {
        NSApp.windows.forEach { $0.orderOut(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            NSApp.setActivationPolicy(.accessory)
            self.isAppVisible = false
            NotificationCenter.default.post(name: NSNotification.Name("AppWillHide"), object: nil)
        }
    }

    // Registration
    func registerHotkey(_ combo: String) -> Bool {
        guard let (keyCode, modifiers) = parseKeyCombo(combo) else {
            print("Invalid combo: \(combo)"); return false
        }
        if modifiers == 0 {
            print("At least one modifier is required"); return false
        }
        let reserved = ["⌘C","⌘V","⌘X","⌘Z","⌘Q","⌘W","⌘H","⌘A","⌘N","⌘O","⌘P","⌘T","⌘,"]
        if reserved.contains(where: { combo.hasPrefix($0) }) { return false }
        guard hotkeyRefs[combo] == nil else { return false }

        var ref: EventHotKeyRef?
        let id = nextAvailableID()
        let hkID = EventHotKeyID(signature: "CMAC".fourCharCode, id: id)
        let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            hotkeyRefs[combo] = ref
            comboToID[combo] = id
            idToCombo[id] = combo
            isRegistered = !hotkeyRefs.isEmpty
            print("Registered: \(combo)")
            return true
        }
        print("RegisterEventHotKey failed: \(status)")
        return false
    }

    func unregisterHotkey(_ combo: String) {
        if let ref = hotkeyRefs[combo] { UnregisterEventHotKey(ref) }
        hotkeyRefs.removeValue(forKey: combo)
        if let id = comboToID.removeValue(forKey: combo) { idToCombo.removeValue(forKey: id) }
        isRegistered = !hotkeyRefs.isEmpty
    }

    func unregisterAllHotkeys() {
        for (_, ref) in hotkeyRefs { UnregisterEventHotKey(ref) }
        hotkeyRefs.removeAll()
        comboToID.removeAll()
        idToCombo.removeAll()
        isRegistered = false
    }

    private func nextAvailableID() -> UInt32 {
        while idToCombo[nextID] != nil { nextID &+= 1 }
        return nextID
    }

    // Parsing
    func parseKeyCombo(_ combo: String) -> (keyCode: CGKeyCode, modifiers: UInt32)? {
        var mods: UInt32 = 0
        if combo.contains("⌘") { mods |= UInt32(cmdKey) }
        if combo.contains("⇧") { mods |= UInt32(shiftKey) }
        if combo.contains("⌃") { mods |= UInt32(controlKey) }
        if combo.contains("⌥") { mods |= UInt32(optionKey) }
        if combo.contains("⇪") { mods |= 0x10000 } // Caps Lock

        var base = combo
        ["⌘","⇧","⌃","⌥","⇪","+"].forEach { base = base.replacingOccurrences(of: $0, with: "") }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return nil }

        let canonical: String = {
            switch base {
            case "↑": return "UP"
            case "↓": return "DOWN"
            case "←": return "LEFT"
            case "→": return "RIGHT"
            case "⇥": return "TAB"
            case "⎋": return "ESCAPE"
            case "⏎", "↩︎": return "RETURN"
            case " ": return "SPACE"
            default:
                let up = base.uppercased()
                if up.hasPrefix("F"), let n = Int(up.dropFirst()), (1...19).contains(n) { return "F\(n)" }
                return up
            }
        }()

        guard let code = charToKeyCode(canonical) else { return nil }
        return (code, mods)
    }

    private func charToKeyCode(_ k: String) -> CGKeyCode? {
        let map: [String: CGKeyCode] = [
            "A":0,"S":1,"D":2,"F":3,"H":4,"G":5,"Z":6,"X":7,"C":8,"V":9,"§":10,"B":11,"Q":12,"W":13,"E":14,"R":15,"Y":16,"T":17,
            "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"O":31,"U":32,"[":33,"I":34,"P":35,
            "RETURN":36,"L":37,"J":38,"'":39,"K":40,";":41,"\\":42,",":43,"/":44,"N":45,"M":46,".":47,"TAB":48,"SPACE":49,"`":50,"DELETE":51,"ESCAPE":53,
            "LEFT":123,"RIGHT":124,"DOWN":125,"UP":126,
            "F1":122,"F2":120,"F3":99,"F4":118,"F5":96,"F6":97,"F7":98,"F8":100,"F9":101,"F10":109,"F11":103,"F12":111,"F13":105,"F14":107,"F15":113,"F16":106,"F17":64,"F18":79,"F19":80
        ]
        return map[k]
    }

    deinit { if let h = eventHandler { RemoveEventHandler(h) } }
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

    init(content: String = "", imageData: Data? = nil, isFavorite: Bool = false) {
        self.id = UUID()
        self.content = content
        self.lowercaseContent = content.lowercased()
        self.imageData = imageData
        self.timestamp = Date()
        self.isFavorite = isFavorite
        self.favoritePosition = nil
    }

    var isImage: Bool { imageData != nil }
}

// MARK: - UI state
enum Theme: String, CaseIterable, Codable { case light, dark
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}
enum AppSize: String, CaseIterable, Codable {
    case small = "Small", large = "Large"
    var dimensions: (width: CGFloat, height: CGFloat) { self == .small ? (340,340) : (340,460) }
}
struct KeyboardShortcut: Codable, Identifiable {
    let id: UUID
    let combo: String
    init(combo: String) { self.id = UUID(); self.combo = combo }
}

// MARK: - ViewModel
final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var theme: Theme = .light { didSet { saveSettings() } }
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
    @Published var searchText: String = "" { didSet { debounceSearch() } }

    private var changeCount = NSPasteboard.general.changeCount
    private let historyKey = "ClipboardHistory"
    private var searchWorkItem: DispatchWorkItem?

    var currentDimensions: (width: CGFloat, height: CGFloat) { appSize.dimensions }

    init() {
        loadSettings()
        loadHistory()
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.pollClipboard() }
        updateGlobalHotkeys()

        NotificationCenter.default.addObserver(forName: NSNotification.Name("AppWillHide"), object: nil, queue: .main) { [weak self] _ in
            self?.clearSelectionStates()
        }
    }

    // MARK: – Filtering
    var filteredItems: [ClipboardItem] {
        let q = searchText.lowercased()
        if q.isEmpty {
            let fav = items.filter { $0.isFavorite }.sorted { ($0.favoritePosition ?? 0) < ($1.favoritePosition ?? 0) }
            let rest = items.filter { !$0.isFavorite }.sorted { $0.timestamp > $1.timestamp }
            return fav + rest
        } else {
            return items.filter { $0.lowercaseContent.contains(q) }
        }
    }

    private func debounceSearch() {
        searchWorkItem?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.objectWillChange.send() }
        searchWorkItem = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    private func clearSelectionStates() {
        selectedItem = nil
        highlightedItem = nil
        clickCount.removeAll()
    }

    // MARK: – Clipboard poll
    func pollClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != changeCount else { return }
        changeCount = pb.changeCount

        if let str = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
            handleNewClipboardContent(content: str)
        } else if let imageData = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            handleNewClipboardContent(imageData: imageData)
        }
    }

    func handleNewClipboardContent(content: String = "", imageData: Data? = nil) {
        if !content.isEmpty {
            guard !items.contains(where: { $0.content == content }) else { return }
            insert(content: content, showToast: false)
        } else if let data = imageData {
            guard !items.contains(where: { $0.isImage && $0.imageData == data }) else { return }
            insert(imageData: data, showToast: false)
        }
    }

    func insert(content: String = "", imageData: Data? = nil, isFavorite: Bool = false, showToast: Bool = true) {
        let newItem = ClipboardItem(content: content, imageData: imageData, isFavorite: isFavorite)
        items.insert(newItem, at: 0)
        if showToast { toast(isFavorite ? "Favorite Added" : "Item Added") }
        saveHistory()
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    func copy(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        if item.isImage, let data = item.imageData {
            NSPasteboard.general.setData(data, forType: .png)
        } else {
            NSPasteboard.general.setString(item.content, forType: .string)
        }
        selectedItem = item
        toast("Copied")
        if !item.isFavorite { moveItemToTop(item) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { GlobalHotkeyManager.shared.hideApp() }
    }

    func copyFromPreview(_ item: ClipboardItem) {
        NSPasteboard.general.clearContents()
        if item.isImage, let data = item.imageData {
            NSPasteboard.general.setData(data, forType: .png)
        } else {
            NSPasteboard.general.setString(item.content, forType: .string)
        }
        selectedItem = item
        toast("Copied")
        if !item.isFavorite { moveItemToTop(item) }
    }

    private func moveItemToTop(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var moved = items.remove(at: idx)
        let favCount = items.filter { $0.isFavorite }.count
        moved.timestamp = Date()
        items.insert(moved, at: favCount)
        saveHistory()
    }

    func showPreviewFor(_ item: ClipboardItem) { previewItem = item; showPreview = true }
    func hidePreview() { showPreview = false; previewItem = nil }

    func handleItemTap(_ item: ClipboardItem) {
        highlightedItem = item
        clickCount[item.id, default: 0] += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.clickCount[item.id] = 0 }
        if clickCount[item.id] == 2 {
            copy(item)
            clickCount[item.id] = 0
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if self.clickCount[item.id] == 0 { self.highlightedItem = nil }
            }
        }
    }

    func toggleFavorite(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        var updated = items[idx]
        updated.isFavorite.toggle()
        items.remove(at: idx)

        if updated.isFavorite {
            let maxPos = items.filter { $0.isFavorite }.compactMap { $0.favoritePosition }.max() ?? -1
            updated.favoritePosition = maxPos + 1
            items.insert(updated, at: 0)
        } else {
            updated.favoritePosition = nil
            let favCount = items.filter { $0.isFavorite }.count
            items.insert(updated, at: favCount)
        }
        saveHistory()
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
        guard item.isFavorite, let cur = items.firstIndex(of: item) else { return }
        let favsBefore = items[..<cur].filter { $0.isFavorite }
        guard let targetItem = favsBefore.last, let targetIndex = items.firstIndex(of: targetItem) else { return }
        items.swapAt(cur, targetIndex)
        updateFavoritePositions()
        saveHistory()
        toast("Moved up")
    }

    func moveFavoriteDown(_ item: ClipboardItem) {
        guard item.isFavorite, let cur = items.firstIndex(of: item) else { return }
        let favsAfter = items[(cur+1)...].filter { $0.isFavorite }
        guard let targetItem = favsAfter.first, let targetIndex = items.firstIndex(of: targetItem) else { return }
        items.swapAt(cur, targetIndex)
        updateFavoritePositions()
        saveHistory()
        toast("Moved down")
    }

    private func updateFavoritePositions() {
        let favs = items.filter { $0.isFavorite }
        for (i, fav) in favs.enumerated() {
            if let idx = items.firstIndex(where: { $0.id == fav.id }) {
                items[idx].favoritePosition = i
            }
        }
    }

    // MARK: – Shortcuts
    func addShortcut(key: String, modifier: String) {
        let modMap = ["Command (⌘)":"⌘","Option (⌥)":"⌥","Control (⌃)":"⌃","Shift (⇧)":"⇧"]
        guard modifier != "None" else { toast("נדרש מודיפייר אחד לפחות"); return }
        let combo = (modMap[modifier] ?? "") + key
        guard !keyboardShortcuts.contains(where: { $0.combo == combo }) else { toast("Shortcut already exists"); return }
        if GlobalHotkeyManager.shared.registerHotkey(combo) {
            keyboardShortcuts.append(KeyboardShortcut(combo: combo))
            saveSettings()
            toast("Shortcut added")
        } else {
            toast("Invalid or reserved shortcut")
        }
    }

    func removeShortcut(_ combo: String) {
        keyboardShortcuts.removeAll { $0.combo == combo }
        GlobalHotkeyManager.shared.unregisterHotkey(combo)
        saveSettings()
        toast("Shortcut removed")
    }

    func updateGlobalHotkeys() {
        GlobalHotkeyManager.shared.unregisterAllHotkeys()
        for s in keyboardShortcuts { _ = GlobalHotkeyManager.shared.registerHotkey(s.combo) }
    }

    // MARK: – Import/Export
    func exportHistory() {
        let textItems = items.compactMap { it -> String? in
            if it.isImage { return nil }
            let prefix = it.isFavorite ? "[FAVORITE] " : ""
            return prefix + it.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        let content = textItems.joined(separator: "\n---\n")
        let panel = NSSavePanel()
        panel.title = "Export Clipboard History"
        panel.nameFieldStringValue = "clipboard_history.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    DispatchQueue.main.async { self.toast("Exported \(textItems.count) items") }
                } catch {
                    DispatchQueue.main.async { self.toast("Export failed: \(error.localizedDescription)") }
                }
            }
        }
    }

    func importHistory() {
        let open = NSOpenPanel()
        open.title = "Import Clipboard History"
        open.allowedContentTypes = [.plainText]
        open.allowsMultipleSelection = false
        open.begin { response in
            if response == .OK, let url = open.url {
                do {
                    let fileContent = try String(contentsOf: url, encoding: .utf8)
                    DispatchQueue.main.async { self.processImportedText(fileContent) }
                } catch {
                    DispatchQueue.main.async { self.toast("Import failed: \(error.localizedDescription)") }
                }
            }
        }
    }

    private func processImportedText(_ text: String) {
        let entries = text.components(separatedBy: "\n---\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var imported: [ClipboardItem] = []
        for e in entries {
            let isFav = e.hasPrefix("[FAVORITE] ")
            let content = isFav ? String(e.dropFirst(11)) : e
            guard !content.isEmpty else { continue }
            var item = ClipboardItem(content: content, isFavorite: isFav)
            if isFav { item.favoritePosition = imported.filter { $0.isFavorite }.count }
            imported.append(item)
        }

        for item in imported.reversed() {
            if !items.contains(where: { $0.content == item.content }) {
                if item.isFavorite {
                    let maxPos = items.filter { $0.isFavorite }.compactMap { $0.favoritePosition }.max() ?? -1
                    var upd = item; upd.favoritePosition = maxPos + 1
                    items.insert(upd, at: 0)
                } else {
                    let favCount = items.filter { $0.isFavorite }.count
                    items.insert(item, at: favCount)
                }
            }
        }
        saveHistory()
        toast("Imported \(imported.count) items")
    }

    // MARK: – Persistence & toast
    private func saveHistory() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = saved
        }
    }
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(keyboardShortcuts) {
            UserDefaults.standard.set(data, forKey: "KeyboardShortcuts")
        }
        if let themeData = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(themeData, forKey: "AppTheme")
        }
    }
    private func loadSettings() {
        if let d = UserDefaults.standard.data(forKey: "KeyboardShortcuts"),
           let saved = try? JSONDecoder().decode([KeyboardShortcut].self, from: d) {
            keyboardShortcuts = saved
        }
        if let td = UserDefaults.standard.data(forKey: "AppTheme"),
           let t = try? JSONDecoder().decode(Theme.self, from: td) {
            theme = t
        }
    }

    func toast(_ text: String) {
        toastText = text
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.showToast = false }
    }
}

// MARK: - ThemeToggle
struct ThemeToggle: View {
    @Binding var theme: Theme
    var body: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                Button(action: { withAnimation(.easeInOut(duration: 0.3)) { theme = .light } }) {
                    ZStack {
                        Circle().fill(theme == .light ? Color.orange.opacity(0.1) : Color.gray.opacity(0.05))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(theme == .light ? Color.orange.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1))
                        Image(systemName: "sun.max.fill").font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme == .light ? Color.orange : Color.gray.opacity(0.6))
                    }
                }.buttonStyle(.plain)
                Text("Light").font(.caption2)
                    .foregroundColor(theme == .light ? .primary : .gray)
            }
            VStack(spacing: 6) {
                Button(action: { withAnimation(.easeInOut(duration: 0.3)) { theme = .dark } }) {
                    ZStack {
                        Circle().fill(theme == .dark ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(theme == .dark ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1))
                        Image(systemName: "moon.fill").font(.system(size: 16, weight: .medium))
                            .foregroundColor(theme == .dark ? Color.blue : Color.gray.opacity(0.6))
                    }
                }.buttonStyle(.plain)
                Text("Dark").font(.caption2)
                    .foregroundColor(theme == .dark ? .primary : .gray)
            }
        }
        .accessibilityLabel("Theme Selection")
    }
}

// MARK: - Main View
@available(macOS 12.0, *)
struct ClipboardAppView: View {
    @StateObject var vm = ClipboardViewModel()
    @StateObject private var hotkeys = GlobalHotkeyManager.shared
    @StateObject private var menuBar = MenuBarManager()

    @State private var newShortcut: String = ""
    @State private var selectedHotkey: String = "None"
    @State private var manualText: String = ""
    @State private var addToFavorites: Bool = false

    private let availableHotkeys = ["None","Command (⌘)","Option (⌥)","Control (⌃)","Shift (⇧)"]

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Divider()
                mainContent
            }
            .preferredColorScheme(vm.theme.colorScheme)
            .frame(minWidth: vm.currentDimensions.width, minHeight: vm.currentDimensions.height)
            .onAppear {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                vm.updateGlobalHotkeys() // no permissions required
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
                        .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                    Image(systemName: "doc.on.clipboard").font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                }
                Text("CopyMac").font(.headline)
            }
            Spacer()
            Button {
                NotificationCenter.default.post(name: NSNotification.Name("ScrollToTop"), object: nil)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 18, height: 18)
                    Image(systemName: "arrow.up").font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
                }
            }.buttonStyle(.plain)

            Button { vm.showSettings.toggle() } label: {
                Image(systemName: "ellipsis").font(.title2).padding(8)
            }.buttonStyle(.plain)
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
                                Image(systemName: "doc.on.clipboard").font(.system(size: 48)).foregroundColor(.gray)
                                if vm.searchText.isEmpty {
                                    Text("Copy some text to get started!").foregroundColor(.gray)
                                } else {
                                    Text("No matching items found").foregroundColor(.gray)
                                    Text("Try a different search term").font(.subheadline).foregroundColor(.gray)
                                }
                            }
                            .padding(.top, 60)
                            .id("topAnchor")
                        } else {
                            Color.clear.frame(height: 1).id("topAnchor")
                            ForEach(Array(vm.filteredItems.enumerated()), id: \.1.id) { index, item in
                                itemRow(item: item, index: index)
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToTop"))) { _ in
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("topAnchor", anchor: .top) }
                }
            }
            searchBar
        }
    }

    func itemRow(item: ClipboardItem, index: Int) -> some View {
        HStack(spacing: 2) {
            Text("\(index + 1).").font(.system(size: 10, design: .monospaced)).foregroundColor(.gray)
            if item.isImage {
                HStack {
                    Text("Image").font(.system(size: 10))
                    if let data = item.imageData, let img = NSImage(data: data) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 15).clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        Image(systemName: "photo").frame(width: 20, height: 15)
                    }
                    Spacer()
                    if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.yellow) }
                }
            } else {
                HStack {
                    let display = item.content.count > 500 ? String(item.content.prefix(500)) + "..." : item.content
                    Text(display.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " "))
                        .font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if item.isFavorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.yellow) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
        .background(rowBackground(item: item, index: index))
        .cornerRadius(3)
        .padding(.horizontal, 1)
        .onTapGesture { vm.handleItemTap(item) }
        .contextMenu { contextMenuContent(item: item) }
    }

    func rowBackground(item: ClipboardItem, index: Int) -> Color {
        if vm.selectedItem?.id == item.id { return Color.blue.opacity(0.5) }
        if vm.highlightedItem?.id == item.id { return Color.blue.opacity(0.25) }
        if index % 2 == 0 {
            return vm.theme == .dark ? Color(red:0.08, green:0.08, blue:0.08) : Color(red:0.82, green:0.82, blue:0.82)
        } else {
            return vm.theme == .dark ? Color(red:0.12, green:0.12, blue:0.12) : Color(red:0.88, green:0.88, blue:0.88)
        }
    }

    @ViewBuilder
    func contextMenuContent(item: ClipboardItem) -> some View {
        Button("Preview") { vm.showPreviewFor(item) }
        Button("Copy") { vm.copy(item) }
        Divider()
        if item.isFavorite {
            Button("Move Up") { vm.moveFavoriteUp(item) }
                .disabled(vm.items.filter { $0.isFavorite }.first?.id == item.id)
            Button("Move Down") { vm.moveFavoriteDown(item) }
                .disabled(vm.items.filter { $0.isFavorite }.last?.id == item.id)
            Divider()
            Button("Remove from Favorites") { vm.toggleFavorite(item) }
        } else {
            Button("Add to Favorites") { vm.toggleFavorite(item) }
        }
        Divider()
        Button("Delete") { vm.delete(item) }
    }

    var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Search Clipboard Items", text: $vm.searchText)
                .textFieldStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .disabled(vm.showSettings)
            if !vm.searchText.isEmpty {
                Button { vm.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }.buttonStyle(.plain)
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
                    Button { vm.showSettings = false } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 18, height: 18)
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
                        }
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .background(Color(.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Manual add
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add Manual Entry").font(.subheadline).fontWeight(.bold)
                        HStack(spacing: 8) {
                            TextField("Type your text here", text: $manualText)
                                .textFieldStyle(.plain)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(manualText.isEmpty ? .clear : .blue, lineWidth: 2))
                            Button("Add") {
                                let t = manualText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !t.isEmpty {
                                    vm.insert(content: t, isFavorite: addToFavorites, showToast: true)
                                    manualText = ""
                                    addToFavorites = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Toggle("Add to favorites", isOn: $addToFavorites).font(.caption)
                    }

                    Divider()

                    // Shortcuts
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Global Shortcuts").font(.subheadline).fontWeight(.bold)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle().fill(hotkeys.isRegistered ? Color.green : Color.red).frame(width: 6, height: 6)
                                Text(hotkeys.isRegistered ? "Active" : "Inactive").font(.caption2).foregroundColor(.secondary)
                            }
                        }

                        ForEach(vm.keyboardShortcuts) { s in
                            HStack {
                                Text(s.combo)
                                    .font(.system(size: 13, design: .monospaced))
                                    .padding(6)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                                Spacer()
                                Button { vm.removeShortcut(s.combo) } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red)
                                }.buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add New Shortcut").font(.caption).foregroundColor(.secondary)
                            HStack {
                                TextField("e.g., D or F12 or ↑", text: $newShortcut)
                                    .textFieldStyle(.plain)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(8)
                                Picker("", selection: $selectedHotkey) {
                                    ForEach(availableHotkeys, id: \.self) { Text($0).tag($0) }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
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
                    }

                    Divider()

                    // Theme
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Theme").font(.subheadline).fontWeight(.bold)
                        ThemeToggle(theme: $vm.theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    // Import/Export
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Import/Export").font(.subheadline).fontWeight(.bold)
                        HStack(spacing: 12) {
                            Button("Export History") { vm.exportHistory() }
                                .buttonStyle(.borderedProminent)
                            Button("Import History") { vm.importHistory() }
                                .buttonStyle(.borderedProminent)
                        }
                    }

                    Divider()

                    // Clear
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clear History").font(.subheadline).fontWeight(.bold)
                        Button("Clear") { vm.showClearConfirm = true }
                            .foregroundColor(.red)

                        if vm.showClearConfirm {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Clear all clipboard items (excluding favorites)?")
                                    .font(.caption).foregroundColor(.secondary)
                                HStack {
                                    Button("Cancel") { vm.showClearConfirm = false }
                                    Button("Confirm") {
                                        vm.clearNonFavorites()
                                        vm.showClearConfirm = false
                                    }.foregroundColor(.red)
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }

                    Text("Version v1.6.0")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer().frame(height: 2)
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
                            .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 18, height: 18)
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundColor(.white)
                    }
                }.buttonStyle(.plain)
            }

            if let item = vm.previewItem {
                if item.isImage, let data = item.imageData, let img = NSImage(data: data) {
                    VStack(spacing: 8) {
                        Text("Image Preview").font(.subheadline).fontWeight(.medium)
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: vm.currentDimensions.width * 0.8,
                                   maxHeight: vm.currentDimensions.height * 0.4)
                            .border(Color.gray.opacity(0.3), width: 1)
                        Text("Size: \(Int(img.size.width)) × \(Int(img.size.height))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text Preview").font(.subheadline).fontWeight(.medium)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(item.content.count) characters").font(.caption).foregroundColor(.secondary)
                                Text("\(item.content.components(separatedBy: .newlines).count) lines").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        ScrollView {
                            Text(item.content)
                                .font(.system(size: 13))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: vm.currentDimensions.height * 0.5)
                        HStack {
                            Button("Copy") { vm.copyFromPreview(item); vm.hidePreview() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Close") { vm.hidePreview() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: vm.currentDimensions.width * 0.95,
               height: vm.currentDimensions.height * 0.85)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
        .shadow(radius: 8)
        .padding(8)
    }
}

// MARK: - App entry
@available(macOS 12.0, *)
@main
struct CopyMacApp: App {
    @StateObject private var hotkeys = GlobalHotkeyManager.shared
    @StateObject private var menuBar = MenuBarManager()

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
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Clipboard") {
                Button("Toggle Clipboard") { hotkeys.toggleAppVisibility() }
                    .keyboardShortcut("`", modifiers: []) // מקומי בלבד
            }
        }
    }
}
