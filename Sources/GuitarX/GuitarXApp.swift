import SwiftUI
import AppKit

@main
struct GuitarXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("GuitarX") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 1100, minHeight: 640)
        }
        .defaultSize(width: 1480, height: 820)
        .commands {
            NavigatorCommands(state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct NavigatorCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Play") { state.playSelection() }
                .keyboardShortcut(.space, modifiers: [])
            Divider()
            Button("Scale Mode") { state.mode = .scale }
                .keyboardShortcut("1", modifiers: .command)
            Button("Chord Mode") { state.mode = .chord }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Button("Next Key (+1 semitone)") { state.shiftKey(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Key (−1 semitone)") { state.shiftKey(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Up a Fifth") { state.shiftKey(7) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Down a Fifth") { state.shiftKey(5) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Divider()
            Button("Next Position / Voicing") { state.step(1) }
                .keyboardShortcut(.rightArrow, modifiers: .option)
            Button("Previous Position / Voicing") { state.step(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .option)
            Button("Next Inversion") { state.nextInversion() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Labels: Notes") { state.labelMode = .notes }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Labels: Intervals") { state.labelMode = .intervals }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}
