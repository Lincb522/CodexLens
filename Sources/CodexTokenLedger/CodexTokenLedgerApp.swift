import AppKit
import SwiftUI

@main
struct CodexTokenLedgerApp: App {
    @NSApplicationDelegateAdaptor(CodexTokenLedgerAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
