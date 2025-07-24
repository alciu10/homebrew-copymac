// MARK: - Updated Entry Point with Theme Support
@available(macOS 12.0, *)
@main
struct CopyMacApp: App {
    @StateObject private var hotkeyManager = GlobalHotkeyManager.shared
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var themeManager = ThemeManager()
    
    var body: some Scene {
        WindowGroup {
            ClipboardAppView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.colorScheme)
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
                
                Button("Toggle Theme") {
                    themeManager.toggleTheme()
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
        }
    }
}
