import Foundation

/// Watches a plain-text file and reports its contents whenever it changes, so
/// external tools (scripts, companion apps, automations) can drive the prompter
/// text live without stealing focus.
///
/// The path is read from the `NOTCH_PROMPTER_FILE` (or `HELM_PROMPT_FILE`)
/// environment variable, defaulting to `~/.helm/prompter.txt`.
final class PrompterFileWatcher {

    static func resolvedPath() -> String {
        let env = ProcessInfo.processInfo.environment
        let raw = env["NOTCH_PROMPTER_FILE"] ?? env["HELM_PROMPT_FILE"] ?? "~/.helm/prompter.txt"
        return (raw as NSString).expandingTildeInPath
    }

    private let path: String
    private let onChange: (String) -> Void
    private var timer: Timer?
    private var lastModified: Date?

    init(onChange: @escaping (String) -> Void) {
        self.path = PrompterFileWatcher.resolvedPath()
        self.onChange = onChange
    }

    func start() {
        // Make sure the directory exists so an external writer can create the file.
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Poll the file's modification date. Robust against atomic writes (rename),
        // which can defeat a single-fd DispatchSource watcher.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date else { return }
        if let last = lastModified, modified <= last { return }
        lastModified = modified
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        DispatchQueue.main.async { self.onChange(content) }
    }
}
