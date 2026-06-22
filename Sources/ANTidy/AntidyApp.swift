import SwiftUI

@main
struct ANTidyApp: App {
    @State private var store = CleanupStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Run Scan") {
                    store.runScan()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(store.isScanning)

                Button("Cancel Scan") {
                    store.cancelScan()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!store.isScanning)
            }
        }
    }
}
