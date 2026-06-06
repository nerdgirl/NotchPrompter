import SwiftUI
import AppKit

@main
struct NotchPrompterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .onAppear(perform: {
                    NSApp.setActivationPolicy(.regular)
                })
                .onDisappear(perform: {
                    NSApp.setActivationPolicy(.accessory)
                })
        }

        MenuBarExtra {
            MenuContent(viewModel: appDelegate.viewModel)
        } label: {
            let image: NSImage = {
                $0.size.height = 12
                $0.size.width = 12
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = PrompterViewModel()
    private var prompterWindow: PrompterWindow!
    private var fileWatcher: PrompterFileWatcher?

    func applicationDidFinishLaunching(_ notification: Notification) {
        prompterWindow = PrompterWindow(viewModel: viewModel)
        NSApp.setActivationPolicy(.accessory)

        // Live external text source: when the watched file changes, swap the
        // prompter script. Payload may be plain text, or JSON {text, autoplay}.
        fileWatcher = PrompterFileWatcher { [weak self] raw in
            guard let self else { return }
            // JSON payload {text?, autoplay?, command?} — or plain text.
            if let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let cmd = obj["command"] as? String {
                    switch cmd {
                    case "pause": self.viewModel.pauseInPlace()
                    case "play", "resume": self.viewModel.resume()
                    case "toggle": self.viewModel.togglePlay()
                    case "reset": self.viewModel.reset()
                    default: break
                    }
                }
                if let t = obj["text"] as? String {
                    self.viewModel.text = t
                    if (obj["autoplay"] as? Bool) ?? false { self.viewModel.play() } else { self.viewModel.reset() }
                }
                return
            }
            self.viewModel.text = raw
            self.viewModel.reset()
        }
        fileWatcher?.start()
    }
}

struct MenuContent: View {
    @ObservedObject var viewModel: PrompterViewModel



    var body: some View {
        Button {
            viewModel.isPrompterVisible.toggle()
        } label: {
            Label(viewModel.isPrompterVisible ? "Hide Prompter" : "Show Prompter",
                  systemImage: viewModel.isPrompterVisible ? "eye.slash" : "eye")
        }
        .keyboardShortcut("h", modifiers: [.command, .option])

        Divider()

        Button("Play") {
               viewModel.play()
        }

        .disabled(viewModel.voiceActivation)
        .keyboardShortcut("p", modifiers: [.command, .option])

        Button {
            viewModel.reset()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }


        Divider()

        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }

        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button("Feedback") {
            if let url = URL(string: "mailto:jakub@jpomykala.com?subject=NotchPrompter%20feedback") {
                NSWorkspace.shared.open(url)
            }
        }

        Button("Project page") {
            if let url = URL(string: "https://notchprompter.com") {
                NSWorkspace.shared.open(url)
            }
        }

       Button("Help translate") {
           if let url = URL(string: "https://simplelocalize.io/suggestions/?id=f1f11f9305dc44a2872b6a154dea6edc") {
               NSWorkspace.shared.open(url)
           }
       }
    
        Divider()

        Button(role: .destructive) {
            NSApp.terminate(nil)
        } label: {
            Label("Exit", systemImage: "xmark.circle")
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
