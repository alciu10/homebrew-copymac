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

// MARK: - Simple Accessibility Manager
class AccessibilityManager: ObservableObject {
    @Published var hasPermission: Bool = false
    @Published var showingPermissionAlert: Bool = false
    
    init() {
        checkPermission()
    }
    
    func checkPermission() {
        hasPermission = AXIsProcessTrusted()
    }
    
    func requestPermission() {
        if !hasPermission {
            showingPermissionAlert = true
        }
    }
    
    func openSystemSettings() {
        showingPermissionAlert = false
        
        // Open System Settings to Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        
        // Start checking for permission every second
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            self.checkPermission()
            if self.hasPermission {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Simplified Global Hotkey Manager
class GlobalHotkeyManager: ObservableObject {
    static let shared = GlobalHotkeyManager()
    private var isAppVisible = false
    @Published var isEnabled = false
    
    private init() {}
    
    func toggleAppVisibility() {
        DispatchQueue.main.async {
            if self.isAppVisible {
                self.hideApp()
            } else {
                self.showApp()
            }
        }
    }
    
    func showApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        if let window = NSApp.windows.first {
            window.positionWindowAtMouse(animated: true)
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
    
    func setupHotkey() {
        // Simplified: just enable/disable flag for now
        isEnabled = AXIsProcessTrusted()
    }
}

// MARK: - Model
struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    var content: String
    var imageData: Data?
    var timestamp: Date
    var isFavorite: Bool
    
    init(content: String = "", imageData: Data? = nil, isFavorite: Bool = false) {
        self.id = UUID()
        self.content = content
        self.imageData = imageData
        self.timestamp = Date()
        self.isFavorite = isFavorite
    }
    
    var isImage: Bool {
        return imageData != nil
    }
}

// MARK: - Theme
enum Theme: String, CaseIterable, Codable {
    case light, dark, system
    
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - App Size Setting
enum AppSize: String, CaseIterable, Codable {
    case small = "Small"
    case large = "Large"
    
    var dimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .small: return (380, 420)
        case .large: return (450, 580)
        }
    }
}

// MARK: - ViewModel
class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var theme: Theme = .system
    @Published var appSize: AppSize = .small
    @Published var showSettings = false
    @Published var showToast = false
    @Published var toastText = ""
    @Published var showPreview = false
    @Published var previewItem: ClipboardItem?
    @Published var searchText: String = ""
    @Published var showClearConfirm = false
    
    private var changeCount = NSPasteboard.general.changeCount
    private let maxItems = 100
    
    var currentDimensions: (width: CGFloat, height: CGFloat) {
        return appSize.dimensions
    }
    
    var filteredItems: [ClipboardItem] {
        if searchText.isEmpty {
            let favorites = items.filter { $0.isFavorite }.sorted { $0.timestamp > $1.timestamp }
            let nonFavorites = items.filter { !$0.isFavorite }.sorted { $0.timestamp > $1.timestamp }
            return favorites + nonFavorites
        } else {
            return items.filter { $0.content.lowercased().contains(searchText.lowercased()) }
                        .sorted { $0.timestamp > $1.timestamp }
        }
    }
    
    init() {
        loadData()
        startClipboardMonitoring()
    }
    
    private func startClipboardMonitoring() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        if pasteboard.changeCount != changeCount {
            changeCount = pasteboard.changeCount
            
            if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                addItem(content: string)
            } else if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
                addItem(imageData: imageData)
            }
        }
    }
    
    private func addItem(content: String = "", imageData: Data? = nil) {
        // Don't add if it's the same as the most recent item
        if let lastItem = items.first {
            if !content.isEmpty && lastItem.content == content {
                return
            }
            if imageData != nil && lastItem.imageData == imageData {
                return
            }
        }
        
        let newItem = ClipboardItem(content: content, imageData: imageData)
        items.insert(newItem, at: 0)
        
        // Keep only the most recent items
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        saveData()
    }
    
    func copyItem(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        if item.isImage, let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .png)
        } else {
            pasteboard.setString(item.content, forType: .string)
        }
        
        toast("Copied!")
        
        // Hide app after copying
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            GlobalHotkeyManager.shared.hideApp()
        }
    }
    
    func toggleFavorite(_ item: ClipboardItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isFavorite.toggle()
            saveData()
            toast(items[index].isFavorite ? "Added to favorites" : "Removed from favorites")
        }
    }
    
    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        saveData()
        toast("Item deleted")
    }
    
    func clearNonFavorites() {
        let favoritesCount = items.filter { $0.isFavorite }.count
        items.removeAll { !$0.isFavorite }
        saveData()
        toast("Cleared \(items.count - favoritesCount) items")
        showClearConfirm = false
    }
    
    func showPreviewFor(_ item: ClipboardItem) {
        previewItem = item
        showPreview = true
    }
    
    func hidePreview() {
        showPreview = false
        previewItem = nil
    }
    
    func toast(_ message: String) {
        toastText = message
        showToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showToast = false
        }
    }
    
    private func saveData() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "ClipboardItems")
        }
        
        if let themeData = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(themeData, forKey: "AppTheme")
        }
        
        if let sizeData = try? JSONEncoder().encode(appSize) {
            UserDefaults.standard.set(sizeData, forKey: "AppSize")
        }
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: "ClipboardItems"),
           let savedItems = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = savedItems
        }
        
        if let themeData = UserDefaults.standard.data(forKey: "AppTheme"),
           let savedTheme = try? JSONDecoder().decode(Theme.self, from: themeData) {
            theme = savedTheme
        }
        
        if let sizeData = UserDefaults.standard.data(forKey: "AppSize"),
           let savedSize = try? JSONDecoder().decode(AppSize.self, from: sizeData) {
            appSize = savedSize
        }
    }
}

// MARK: - Main View
@available(macOS 12.0, *)
struct ClipboardAppView: View {
    @StateObject private var viewModel = ClipboardViewModel()
    @StateObject private var accessibilityManager = AccessibilityManager()
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    
    var body: some View {
        ZStack {
            mainView
            
            if viewModel.showSettings {
                settingsOverlay
            }
            
            if viewModel.showPreview {
                previewOverlay
            }
            
            if viewModel.showToast {
                toastOverlay
            }
            
            if accessibilityManager.showingPermissionAlert {
                permissionAlert
            }
        }
        .preferredColorScheme(viewModel.theme.colorScheme)
        .frame(
            width: viewModel.currentDimensions.width,
            height: viewModel.currentDimensions.height
        )
        .onAppear {
            accessibilityManager.checkPermission()
            hotkeyManager.setupHotkey()
        }
    }
    
    var mainView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        
                        Text("CopyMac")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    if !accessibilityManager.hasPermission {
                        Text("Global shortcuts disabled")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: { viewModel.showSettings.toggle() }) {
                        Image(systemName: "gear")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    
                    Button(action: { GlobalHotkeyManager.shared.hideApp() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search clipboard history...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Content
            if viewModel.filteredItems.isEmpty {
                emptyStateView
            } else {
                clipboardList
            }
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            
            if viewModel.searchText.isEmpty {
                Text("No clipboard history yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text("Copy some text or images to get started")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No results found")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                
                Text("Try a different search term")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var clipboardList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                    ClipboardItemRow(
                        item: item,
                        index: index + 1,
                        onCopy: { viewModel.copyItem(item) },
                        onPreview: { viewModel.showPreviewFor(item) },
                        onToggleFavorite: { viewModel.toggleFavorite(item) },
                        onDelete: { viewModel.deleteItem(item) }
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { viewModel.showSettings = false }
            
            SettingsView(
                viewModel: viewModel,
                accessibilityManager: accessibilityManager,
                onClose: { viewModel.showSettings = false }
            )
        }
    }
    
    var previewOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { viewModel.hidePreview() }
            
            if let item = viewModel.previewItem {
                PreviewView(
                    item: item,
                    onCopy: {
                        viewModel.copyItem(item)
                        viewModel.hidePreview()
                    },
                    onClose: { viewModel.hidePreview() }
                )
            }
        }
    }
    
    var toastOverlay: some View {
        VStack {
            Spacer()
            
            HStack {
                Spacer()
                
                Text(viewModel.toastText)
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(20)
                
                Spacer()
            }
            .padding(.bottom, 20)
        }
        .allowsHitTesting(false)
    }
    
    var permissionAlert: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Accessibility Permission Required")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text("CopyMac needs accessibility permission to enable global keyboard shortcuts. This allows you to quickly access your clipboard from anywhere.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Button("Not Now") {
                        accessibilityManager.showingPermissionAlert = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Open Settings") {
                        accessibilityManager.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
            .shadow(radius: 20)
            .frame(maxWidth: 320)
        }
    }
}

// MARK: - Clipboard Item Row
struct ClipboardItemRow: View {
    let item: ClipboardItem
    let index: Int
    let onCopy: () -> Void
    let onPreview: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Index
            Text("\(index)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                if item.isImage {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundStyle(.blue)
                        Text("Image")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    Text(item.content)
                        .font(.body)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                Text(formatTimestamp(item.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            // Favorite indicator
            if item.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .onTapGesture(count: 2) {
            onCopy()
        }
        .onTapGesture {
            onPreview()
        }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button("Preview", action: onPreview)
            Divider()
            Button(item.isFavorite ? "Remove from Favorites" : "Add to Favorites", action: onToggleFavorite)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: ClipboardViewModel
    @ObservedObject var accessibilityManager: AccessibilityManager
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Done", action: onClose)
                    .buttonStyle(.borderedProminent)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 24) {
                // Theme
                VStack(alignment: .leading, spacing: 8) {
                    Text("Appearance")
                        .font(.headline)
                    
                    Picker("Theme", selection: $viewModel.theme) {
                        ForEach(Theme.allCases, id: \.self) { theme in
                            Text(theme.rawValue.capitalized).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Window Size
                VStack(alignment: .leading, spacing: 8) {
                    Text("Window Size")
                        .font(.headline)
                    
                    Picker("Size", selection: $viewModel.appSize) {
                        ForEach(AppSize.allCases, id: \.self) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Global Shortcuts
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Global Shortcuts")
                            .font(.headline)
                        
                        Spacer()
                        
                        Circle()
                            .fill(accessibilityManager.hasPermission ? .green : .red)
                            .frame(width: 8, height: 8)
                    }
                    
                    if accessibilityManager.hasPermission {
                        Text("✓ Enabled - Press ⌘⇧V to open CopyMac from anywhere")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Enable Global Shortcuts") {
                            accessibilityManager.requestPermission()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                // Clear Data
                VStack(alignment: .leading, spacing: 8) {
                    Text("Data Management")
                        .font(.headline)
                    
                    if viewModel.showClearConfirm {
                        VStack(spacing: 8) {
                            Text("Are you sure you want to clear all non-favorite items?")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Button("Cancel") {
                                    viewModel.showClearConfirm = false
                                }
                                .buttonStyle(.bordered)
                                
                                Button("Clear") {
                                    viewModel.clearNonFavorites()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        Button("Clear Non-Favorites") {
                            viewModel.showClearConfirm = true
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            
            Spacer()
            
            // Version
            Text("CopyMac v2.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 400, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

// MARK: - Preview View
struct PreviewView: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Preview")
                    .font(.headline)
                
                Spacer()
                
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
            }
            
            // Content
            ScrollView {
                if item.isImage, let imageData = item.imageData, let nsImage = NSImage(data: imageData) {
                    VStack(spacing: 12) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        
                        Text("Image • \(Int(nsImage.size.width)) × \(Int(nsImage.size.height))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Text • \(item.content.count) characters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                        }
                        
                        Text(item.content)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 400)
            
            // Actions
            HStack {
                Spacer()
                
                Button("Copy", action: onCopy)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 20)
    }
}

// MARK: - App Entry Point
@available(macOS 12.0, *)
@main
struct CopyMacApp: App {
    var body: some Scene {
        WindowGroup {
            ClipboardAppView()
                .onAppear {
                    if let window = NSApp.windows.first {
                        window.positionWindowAtMouse(animated: true)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("CopyMac") {
                Button("Show Clipboard") {
                    GlobalHotkeyManager.shared.showApp()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}
