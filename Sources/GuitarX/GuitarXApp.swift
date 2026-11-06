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
                .frame(minWidth: 1100, minHeight: 680)
                .onAppear { appDelegate.state = state }
        }
        .defaultSize(width: 1480, height: 860)
        .commands {
            NavigatorCommands(state: state)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Global navigation keys. Handled here (not as menu shortcuts) so that typing
        // in a text field — e.g. the progression box — still gets Space and arrow keys.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let state = self.state else { return event }
            return self.handle(event, state: state) ? nil : event
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func handle(_ event: NSEvent, state: AppState) -> Bool {
        if NSApp.keyWindow?.firstResponder is NSTextView { return false }
        let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let none: NSEvent.ModifierFlags = []
        switch event.keyCode {
        case 49 where mods == none:                 // Space
            state.playSelection()
        case 123 where mods == .command:            // ⌘←
            state.shiftKey(-1)
        case 124 where mods == .command:            // ⌘→
            state.shiftKey(1)
        case 126 where mods == .command:            // ⌘↑
            state.shiftKey(7)
        case 125 where mods == .command:            // ⌘↓
            state.shiftKey(5)
        case 123 where mods == .option:             // ⌥←
            state.step(-1)
        case 124 where mods == .option:             // ⌥→
            state.step(1)
        default:
            return false
        }
        return true
    }
}

struct NavigatorCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Play / Stop   (Space)") { state.playSelection() }
                .keyboardShortcut(.return, modifiers: .command)
            Divider()
            Button("Scale Mode") { state.mode = .scale }
                .keyboardShortcut("1", modifiers: .command)
            Button("Chord Mode") { state.mode = .chord }
                .keyboardShortcut("2", modifiers: .command)
            Button("Progression Mode") { state.mode = .progression }
                .keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Next Key   (⌘→)") { state.shiftKey(1) }
            Button("Previous Key   (⌘←)") { state.shiftKey(-1) }
            Button("Up a Fifth   (⌘↑)") { state.shiftKey(7) }
            Button("Down a Fifth   (⌘↓)") { state.shiftKey(5) }
            Divider()
            Button("Next Position / Voicing / Chord   (⌥→)") { state.step(1) }
            Button("Previous Position / Voicing / Chord   (⌥←)") { state.step(-1) }
            Button("Next Inversion") { state.nextInversion() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("CAGED Positions") {
                if state.mode == .chord { state.chordDisplay = .caged } else { state.mode = .scale; state.positionSystem = .caged }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("Labels: Notes") { state.labelMode = .notes }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Labels: Intervals") { state.labelMode = .intervals }
                .keyboardShortcut("t", modifiers: [.command, .shift])
        }
    }
}
