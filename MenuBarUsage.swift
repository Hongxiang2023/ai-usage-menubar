import AppKit

let dir = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
let script = ProcessInfo.processInfo.environment["USAGE_COLLECTOR"]
    ?? Bundle.main.path(forResource: "collect", ofType: "py") ?? dir + "/collect.py"
let intervals: [(String, Int)] = [("1 minute", 1), ("5 minutes", 5), ("10 minutes", 10), ("30 minutes", 30), ("1 hour", 60)]

func fmtTok(_ n: Double) -> String { n >= 1e6 ? String(format: "%.1fM", n/1e6) : n >= 1e3 ? "\(Int(n/1e3))K" : "\(Int(n))" }
func fmtLeft(_ ts: Double?) -> String {
    guard let ts = ts else { return "—" }
    let m = max(0, Int((ts - Date().timeIntervalSince1970) / 60))
    return m >= 1440 ? "\(m/1440)d\(m%1440/60)h" : m >= 60 ? "\(m/60)h\(m%60)m" : "\(m)m"
}

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.title = "Claude … Codex …"
        refresh()
        schedule()
    }
    var minutes: Int {
        let m = UserDefaults.standard.integer(forKey: "refreshMinutes"); return m > 0 ? m : 10
    }
    var timer: Timer?
    func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: true) { _ in self.refresh() }
    }
    @objc func setInterval(_ s: NSMenuItem) {
        UserDefaults.standard.set(s.tag, forKey: "refreshMinutes"); schedule(); refresh()
    }
    @objc func refresh() {
        DispatchQueue.global().async {
            let p = Process(); let out = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = [script]; p.standardOutput = out
            try? p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            DispatchQueue.main.async { self.render(j) }
        }
    }
    func render(_ j: [String: Any]?) {
        let menu = NSMenu()
        guard let j = j else { item.button?.title = "usage: error"; menu.addItem(withTitle: "collect.py failed", action: nil, keyEquivalent: ""); finish(menu); return }
        let c = j["claude"] as? [String: Any] ?? [:]
        let x = (j["codex"] as? [String: Any])?["primary"] as? [String: Any]
        let blk = c["block_tokens"] as? Double ?? 0
        let off = c["official"] as? [String: Any]
        let cw = off?["seven_day"] as? [String: Any]
        let c5 = off?["five_hour"] as? [String: Any]
        let pct = (x?["used_percent"] as? Double).map { max(0, 100 - $0) }
        let cpct = (cw?["used_percent"] as? Double).map { max(0, 100 - $0) }
        item.button?.title = "Claude \(cpct.map { "\(Int($0))%" } ?? fmtTok(blk)) · Codex \(pct.map { "\(Int($0))%" } ?? "—")"
        func line(_ s: String, bold: Bool = false) {
            let m = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            if bold { m.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]) }
            menu.addItem(m)
        }
        line("Claude Code", bold: true)
        if let cw = cw, let p = cw["used_percent"] as? Double {
            line("  Weekly left: \(Int(max(0, 100 - p)))%, resets in \(fmtLeft(cw["resets_at"] as? Double))")
            if let c5 = c5, let p5 = c5["used_percent"] as? Double { line("  5h session left: \(Int(max(0, 100 - p5)))%, resets in \(fmtLeft(c5["resets_at"] as? Double))") }
        } else {
            line("  (official usage unavailable, showing local tokens)")
            line("  5h window: \(fmtTok(blk)) tokens, resets in \(fmtLeft(c["block_resets_at"] as? Double))")
        }
        menu.addItem(.separator())
        line("Codex", bold: true)
        if let x = x, let p = pct {
            let mins = x["window_minutes"] as? Double ?? 0
            line("  \(mins >= 10080 ? "Weekly" : "\(Int(mins/60))h") left: \(Int(max(0, 100 - p)))%, resets in \(fmtLeft(x["resets_at"] as? Double))")
        } else { line("  no data") }
        menu.addItem(.separator()); finish(menu)
    }
    func finish(_ menu: NSMenu) {
        let r = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r"); r.target = self; menu.addItem(r)
        let sub = NSMenu(); let parent = NSMenuItem(title: "Refresh every", action: nil, keyEquivalent: "")
        for (name, m) in intervals {
            let i = NSMenuItem(title: name, action: #selector(setInterval(_:)), keyEquivalent: "")
            i.target = self; i.tag = m; i.state = m == minutes ? .on : .off; sub.addItem(i)
        }
        parent.submenu = sub; menu.addItem(parent)
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }
}
let app = NSApplication.shared
let delegate = App(); app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
