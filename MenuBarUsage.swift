import AppKit
import WebKit

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

let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"
let usageJS = """
const r = await fetch('/api/organizations', {credentials: 'include'});
if (r.status === 401 || r.status === 403) return {signedOut: true};
if (!r.ok) return {error: 'claude.ai HTTP ' + r.status};
const orgs = await r.json();
const t = w => (w && w.utilization != null) ? {used_percent: w.utilization, resets_at: w.resets_at ? Date.parse(w.resets_at) / 1000 : 0} : null;
for (const o of orgs) {
  try {
    const u = await fetch('/api/organizations/' + o.uuid + '/usage', {credentials: 'include'});
    if (!u.ok) continue;
    const j = await u.json();
    if (j.seven_day || j.five_hour) {
      const out = {};
      const a = t(j.five_hour), b = t(j.seven_day);
      if (a) out.five_hour = a;
      if (b) out.seven_day = b;
      return out;
    }
  } catch (e) {}
}
return {error: 'no usage data on claude.ai'};
"""

/// Reads Claude usage through the app's own claude.ai sign-in (same data as Settings > Usage).
/// The sign-in lives in this app's private WebKit store; nothing is read from Claude Code or the browser.
final class ClaudeWeb: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    let hidden = WKWebView(frame: .zero)
    var pending: (([String: Any]) -> Void)?
    var gen = 0
    var loginWindow: NSWindow?, loginView: WKWebView?, poll: Timer?
    var popups: [WKWebView: NSWindow] = [:]
    var onSignedIn: (() -> Void)?

    override init() {
        super.init()
        hidden.customUserAgent = safariUA
        hidden.navigationDelegate = self
    }
    func run(_ view: WKWebView, _ done: @escaping ([String: Any]) -> Void) {
        view.callAsyncJavaScript(usageJS, arguments: [:], in: nil, in: .page) { res in
            switch res {
            case .success(let v): done(v as? [String: Any] ?? ["error": "claude.ai: unexpected reply"])
            case .failure(let e): done(["error": "claude.ai: \(e.localizedDescription)"])
            }
        }
    }
    /// Loads a small claude.ai page in the hidden view, then asks it for the usage numbers.
    func fetch(_ done: @escaping ([String: Any]) -> Void) {
        gen += 1; let g = gen
        pending = done
        hidden.load(URLRequest(url: URL(string: "https://claude.ai/api/organizations")!, timeoutInterval: 20))
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { if self.gen == g { self.finish(["error": "claude.ai timed out"]) } }
    }
    func finish(_ r: [String: Any]) { let p = pending; pending = nil; p?(r) }
    func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
        guard v === hidden, pending != nil else { return }
        run(hidden) { self.finish($0) }
    }
    func webView(_ v: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        if v === hidden { finish(["error": "claude.ai: \(e.localizedDescription)"]) }
    }
    func webView(_ v: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        if v === hidden { finish(["error": "claude.ai: \(e.localizedDescription)"]) }
    }

    func showLogin() {
        if let w = loginWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let v = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 760))
        v.customUserAgent = safariUA; v.uiDelegate = self
        let w = NSWindow(contentRect: v.frame, styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Sign in to claude.ai"; w.contentView = v; w.isReleasedWhenClosed = false; w.delegate = self; w.center()
        loginWindow = w; loginView = v
        v.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil)
        // close the window by itself once the session works
        poll = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            guard let v = self.loginView, v.url?.host == "claude.ai" else { return }
            self.run(v) { r in
                if r["signedOut"] == nil && r["error"] == nil { self.loginWindow?.close() }
            }
        }
    }
    func windowWillClose(_ n: Notification) {
        guard (n.object as? NSWindow) === loginWindow else { return }
        poll?.invalidate(); poll = nil; loginWindow = nil; loginView = nil
        for (_, w) in popups { w.close() }; popups = [:]
        onSignedIn?()
    }
    // sign-in providers open a pop-up window
    func webView(_ v: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures f: WKWindowFeatures) -> WKWebView? {
        let p = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 680), configuration: c)
        p.customUserAgent = safariUA; p.uiDelegate = self
        let w = NSWindow(contentRect: p.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Sign in"; w.contentView = p; w.isReleasedWhenClosed = false; w.center()
        popups[p] = w; w.makeKeyAndOrderFront(nil)
        return p
    }
    func webViewDidClose(_ v: WKWebView) { popups[v]?.close(); popups[v] = nil }
    func signOut(_ done: @escaping () -> Void) {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast, completionHandler: done)
    }
}

final class App: NSObject, NSApplicationDelegate {
    let claudeWeb = ClaudeWeb()
    var web: [String: Any] = [:]
    var webSignedIn: Bool {
        get { UserDefaults.standard.bool(forKey: "webSignedIn") }
        set { UserDefaults.standard.set(newValue, forKey: "webSignedIn") }
    }
    @objc func signIn() { claudeWeb.showLogin() }
    @objc func signOut() { claudeWeb.signOut { self.webSignedIn = false; self.refresh() } }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.title = "Claude … Codex …"
        let main = NSMenu(), editItem = NSMenuItem(), edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem); NSApp.mainMenu = main
        claudeWeb.onSignedIn = { self.refresh() }
        refresh()
        schedule()
        // the token usually expires while the Mac sleeps: refresh shortly after wake, once the network is back
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            self.retries = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self.refresh() }
        }
    }
    var retries = 0
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
    var refreshing = false
    @objc func refresh() {
        if refreshing { return }
        refreshing = true
        claudeWeb.fetch { r in
            self.web = r
            if r["seven_day"] != nil || r["five_hour"] != nil {
                self.webSignedIn = true
                var c = r; c["cached_at"] = Date().timeIntervalSince1970
                let dir = NSHomeDirectory() + "/.config/ai-usage-menubar"
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                if let d = try? JSONSerialization.data(withJSONObject: c) { try? d.write(to: URL(fileURLWithPath: dir + "/claude_cache.json")) }
            } else if r["signedOut"] != nil { self.webSignedIn = false }
            self.collect()
        }
    }
    func collect() {
        let useWeb = webSignedIn
        DispatchQueue.global().async {
            let p = Process(); let out = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            var env = ProcessInfo.processInfo.environment
            if useWeb { env["USAGE_CLAUDE_WEB"] = "1" }
            p.environment = env
            p.arguments = [script]; p.standardOutput = out
            try? p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            DispatchQueue.main.async { self.refreshing = false; self.render(j) }
        }
    }
    func render(_ j: [String: Any]?) {
        let menu = NSMenu()
        guard let j = j else { item.button?.title = "usage: error"; menu.addItem(withTitle: "collect.py failed", action: nil, keyEquivalent: ""); finish(menu); return }
        let c = j["claude"] as? [String: Any] ?? [:]
        let x = (j["codex"] as? [String: Any])?["primary"] as? [String: Any]
        let blk = c["block_tokens"] as? Double ?? 0
        var off = c["official"] as? [String: Any]
        let viaWeb = web["seven_day"] != nil || web["five_hour"] != nil
        if viaWeb { off = web }
        let cw = off?["seven_day"] as? [String: Any]
        let c5 = off?["five_hour"] as? [String: Any]
        // failed or served from cache: retry soon instead of waiting a full interval
        let failed = off == nil || off?["error"] != nil
        if !failed { retries = 0 } else if retries < 6 {
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(min(retries, 5)) * 60) { self.refresh() }
        }
        let stale = (cw != nil && failed) ? "~" : ""
        let pct = (x?["used_percent"] as? Double).map { max(0, 100 - $0) }
        let cpct = (cw?["used_percent"] as? Double).map { max(0, 100 - $0) }
        item.button?.title = "Claude \(cpct.map { "\(stale)\(Int($0))%" } ?? fmtTok(blk)) · Codex \(pct.map { "\(Int($0))%" } ?? "—")"
        func line(_ s: String, bold: Bool = false) {
            let m = NSMenuItem(title: s, action: nil, keyEquivalent: "")
            if bold { m.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]) }
            menu.addItem(m)
        }
        line("Claude Code", bold: true)
        if let cw = cw, let p = cw["used_percent"] as? Double {
            line("  Weekly left: \(Int(max(0, 100 - p)))%, resets in \(fmtLeft(cw["resets_at"] as? Double))")
            if failed, let at = off?["cached_at"] as? Double {
                let f = DateFormatter(); f.dateFormat = "MMM d HH:mm"
                line("  (last known value from \(f.string(from: Date(timeIntervalSince1970: at))): \(off?["error"] as? String ?? "offline"))")
            }
            if let le = off?["login_expires_at"] as? Double, le - Date().timeIntervalSince1970 < 3 * 86400 {
                line("  ⚠️ Claude login expires in \(fmtLeft(le)): run `claude` then /login")
            }
            if let c5 = c5, let p5 = c5["used_percent"] as? Double { line("  5h session left: \(Int(max(0, 100 - p5)))%, resets in \(fmtLeft(c5["resets_at"] as? Double))") }
        } else {
            line("  (\(off?["error"] as? String ?? "official usage unavailable"); showing local tokens)")
            line("  5h window: \(fmtTok(blk)) tokens, resets in \(fmtLeft(c["block_resets_at"] as? Double))")
        }
        let s = NSMenuItem(title: webSignedIn ? "  Signed in to claude.ai ✓  (sign in again…)" : "  Sign in to claude.ai… (recommended)", action: #selector(signIn), keyEquivalent: "")
        s.target = self; menu.addItem(s)
        if webSignedIn {
            let o = NSMenuItem(title: "  Sign out of claude.ai", action: #selector(signOut), keyEquivalent: ""); o.target = self; menu.addItem(o)
        }
        menu.addItem(.separator())
        line("Codex", bold: true)
        if let x = x, let p = pct {
            let mins = x["window_minutes"] as? Double ?? 0
            let name = mins >= 10080 ? "Weekly" : "\(Int(mins/60))h"
            if x["idle"] as? Bool == true {
                line("  \(name) left: \(Int(p))%, window starts at first use")
            } else {
                line("  \(name) left: \(Int(p))%, resets in \(fmtLeft(x["resets_at"] as? Double))")
            }
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
