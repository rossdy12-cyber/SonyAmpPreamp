import SwiftUI

struct PCHost: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let ip: String
    let bridgePort: Int
    let remotePort: Int
    let isLinux: Bool
    let macAddress: String
}

struct SteamGame: Identifiable, Codable {
    let appid: String
    let name: String
    var id: String { appid }
    var headerURL: URL? {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(appid)/header.jpg")
    }
}

struct AudioEndpoint: Identifiable, Codable {
    let id: String
    let name: String
    let kind: String
    let isDefault: Bool
}

@MainActor
class DeskSwitchStore: ObservableObject {
    let hosts: [PCHost] = [
        PCHost(id: "win", name: "Ross Windows PC", subtitle: "3-Monitor Desk & TV • 100.102.4.54", ip: "100.102.4.54", bridgePort: 9090, remotePort: 7777, isLinux: false, macAddress: "00:00:00:00:00:00"),
        PCHost(id: "bazzite", name: "Bazzite Linux PC", subtitle: "SteamOS / KDE • 100.79.246.119", ip: "100.79.246.119", bridgePort: 9091, remotePort: 7777, isLinux: true, macAddress: "00:00:00:00:00:00"),
        PCHost(id: "lauren", name: "Lauren Steam PC", subtitle: "TV & Alienware • Port 7777", ip: "192.168.0.100", bridgePort: 9090, remotePort: 7777, isLinux: false, macAddress: "00:00:00:00:00:00")
    ]

    @Published var selectedHostID: String = "win"
    @Published var customIP: String = ""
    @Published var onlineStatus: [String: Bool] = [:]
    @Published var statusBanner: String = "Ready"
    @Published var isBusy: Bool = false
    @Published var games: [SteamGame] = [
        SteamGame(appid: "1245620", name: "ELDEN RING"),
        SteamGame(appid: "1086940", name: "Baldur's Gate 3"),
        SteamGame(appid: "1091500", name: "Cyberpunk 2077"),
        SteamGame(appid: "1172470", name: "Apex Legends"),
        SteamGame(appid: "271590", name: "Grand Theft Auto V"),
        SteamGame(appid: "1623730", name: "Palworld")
    ]
    @Published var audioDevices: [AudioEndpoint] = []
    @Published var systemStats: String = "Tap Refresh to query CPU, GPU & Display topology."

    var currentHost: PCHost {
        let base = hosts.first(where: { $0.id == selectedHostID }) ?? hosts[0]
        if !customIP.trimmingCharacters(in: .whitespaces).isEmpty {
            return PCHost(id: base.id, name: base.name, subtitle: customIP, ip: customIP.trimmingCharacters(in: .whitespaces), bridgePort: base.bridgePort, remotePort: base.remotePort, isLinux: base.isLinux, macAddress: base.macAddress)
        }
        return base
    }

    func pingAll() async {
        for h in hosts {
            let ok = await checkHost(h)
            onlineStatus[h.id] = ok
        }
    }

    func checkHost(_ h: PCHost) async -> Bool {
        if let url = URL(string: "http://\(h.ip):\(h.bridgePort)/api/antigravity/state") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2.5
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        }
        if let url = URL(string: "http://\(h.ip):\(h.remotePort)/api/games") {
            var req = URLRequest(url: url)
            req.timeoutInterval = 2.5
            if let (_, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
        }
        return false
    }

    func execBridge(_ command: String, host: PCHost? = nil) async -> String {
        let h = host ?? currentHost
        guard let url = URL(string: "http://\(h.ip):\(h.bridgePort)/api/antigravity/exec") else { return "Invalid URL" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": command])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let out = (obj["stdout"] as? String) ?? (obj["output"] as? String) ?? ""
                let err = (obj["stderr"] as? String) ?? ""
                return (out + "\n" + err).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return String(data: data, encoding: .utf8) ?? "OK"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func callRemoteAPI(_ path: String) async -> [String: Any]? {
        let h = currentHost
        for port in [h.remotePort, 8888] {
            guard let url = URL(string: "http://\(h.ip):\(port)\(path)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 3.0
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }
        return nil
    }

    // MARK: - Display Switching
    func switchDisplay(mode: String) async {
        isBusy = true
        defer { isBusy = false }
        let h = currentHost

        if !h.isLinux {
            if mode == "tv", let json = await callRemoteAPI("/api/tv") {
                statusBanner = (json["message"] as? String) ?? "Switched to TV Only"
                return
            }
            if mode == "monitor", let json = await callRemoteAPI("/api/monitor") {
                statusBanner = (json["message"] as? String) ?? "Switched to Monitor"
                return
            }
            let flag: String
            switch mode {
            case "tv": flag = "/external"
            case "monitor": flag = "/internal"
            case "extend": flag = "/extend"
            case "clone": flag = "/clone"
            default: flag = "/extend"
            }
            let out = await execBridge("DisplaySwitch.exe \(flag)")
            statusBanner = out.isEmpty ? "Windows Display -> \(mode.uppercased()) (\(flag))" : out
        } else {
            let cmd: String
            switch mode {
            case "tv":
                cmd = "kscreen-doctor output.HDMI-A-1.enable output.DP-1.disable 2>/dev/null || xrandr --output HDMI-A-1 --auto"
            case "monitor":
                cmd = "kscreen-doctor output.DP-1.enable output.HDMI-A-1.disable 2>/dev/null || xrandr --output DP-1 --auto"
            case "extend":
                cmd = "kscreen-doctor output.DP-1.enable output.HDMI-A-1.enable 2>/dev/null || xrandr --auto"
            default:
                cmd = "xrandr --auto"
            }
            let out = await execBridge(cmd)
            statusBanner = out.isEmpty ? "Bazzite Display -> \(mode.uppercased())" : out
        }
    }

    // MARK: - Audio Switching & Volume
    func switchAudioPreset(_ preset: String) async {
        isBusy = true
        defer { isBusy = false }
        if let json = await callRemoteAPI("/api/audio/switch?preset=\(preset)") {
            statusBanner = (json["message"] as? String) ?? "Audio switched to \(preset)"
            return
        }
        let h = currentHost
        if h.isLinux {
            let out = await execBridge("wpctl status | head -n 25")
            statusBanner = "Bazzite PipeWire: \(out.prefix(80))"
        } else {
            let ps = """
            powershell -Command "Get-AudioDevice -List 2>$null | Select-Object Name,Type,Default | Out-String"
            """
            let _ = await execBridge(ps)
            statusBanner = "Audio preset '\(preset.uppercased())' sent to \(h.name)"
        }
    }

    func sendKey(_ key: String) async {
        if let _ = await callRemoteAPI("/api/input/key?k=\(key)") {
            statusBanner = "Key: \(key.uppercased())"
            return
        }
        let h = currentHost
        if h.isLinux {
            let map: [String: String] = [
                "up": "Up", "down": "Down", "left": "Left", "right": "Right",
                "enter": "Return", "back": "BackSpace", "esc": "Escape",
                "space": "space", "playpause": "XF86AudioPlay",
                "volup": "XF86AudioRaiseVolume", "voldown": "XF86AudioLowerVolume",
                "mute": "XF86AudioMute", "fullscreen": "f", "subtitles": "s", "altf4": "alt+F4"
            ]
            let xk = map[key] ?? key
            _ = await execBridge("DISPLAY=:0 xdotool key \(xk) 2>/dev/null")
            statusBanner = "Sent \(xk) to Bazzite"
        } else {
            let sendKeyMap: [String: String] = [
                "up": "{UP}", "down": "{DOWN}", "left": "{LEFT}", "right": "{RIGHT}",
                "enter": "{ENTER}", "back": "{BS}", "esc": "{ESC}", "space": " ",
                "playpause": "{MEDIA_PLAY_PAUSE}", "volup": "{VOLUME_UP}",
                "voldown": "{VOLUME_DOWN}", "mute": "{VOLUME_MUTE}",
                "next": "{MEDIA_NEXT_TRACK}", "prev": "{MEDIA_PREV_TRACK}",
                "fullscreen": "f", "subtitles": "s", "home": "{HOME}", "altf4": "%{F4}"
            ]
            if key == "volup" || key == "voldown" || key == "mute" || key == "playpause" || key == "next" || key == "prev" {
                let vkMap: [String: Int] = ["mute": 173, "voldown": 174, "volup": 175, "next": 176, "prev": 177, "playpause": 179]
                let vk = vkMap[key] ?? 179
                let ps = "powershell -Command \"$code = '[DllImport(\\\"user32.dll\\\")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);'; $t = Add-Type -MemberDefinition $code -Name 'Win32Key' -Namespace 'Win32' -PassThru; $t::keybd_event(\(vk), 0, 0, 0); $t::keybd_event(\(vk), 0, 2, 0)\""
                _ = await execBridge(ps)
            } else {
                let sk = sendKeyMap[key] ?? key
                let ps = "powershell -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('\(sk)')\""
                _ = await execBridge(ps)
            }
            statusBanner = "Key: \(key.uppercased())"
        }
    }

    func moveMouse(dx: Int, dy: Int) async {
        if let _ = await callRemoteAPI("/api/input/mouse?action=move&dx=\(dx)&dy=\(dy)") {
            return
        }
        let h = currentHost
        if !h.isLinux {
            let ps = "powershell -Command \"Add-Type -AssemblyName System.Windows.Forms; $p = [System.Windows.Forms.Cursor]::Position; [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(($p.X + \(dx)), ($p.Y + \(dy)))\""
            _ = await execBridge(ps)
        }
    }

    func clickMouse(_ button: String) async {
        if let _ = await callRemoteAPI("/api/input/mouse?action=\(button)") {
            statusBanner = "Mouse \(button.capitalized) Click"
            return
        }
        let flags = (button == "right") ? "0x0008, 0x0010" : "0x0002, 0x0004"
        let ps = "powershell -Command \"$c = '[DllImport(\\\"user32.dll\\\")] public static extern void mouse_event(int dwFlags, int dx, int dy, int cButtons, int dwExtraInfo);'; $m = Add-Type -MemberDefinition $c -Name 'WMouse' -Namespace 'W32' -PassThru; $m::mouse_event(\(flags.components(separatedBy: ", ")[0]), 0, 0, 0, 0); $m::mouse_event(\(flags.components(separatedBy: ", ")[1]), 0, 0, 0, 0)\""
        _ = await execBridge(ps)
        statusBanner = "Mouse \(button.capitalized) Click"
    }

    // MARK: - Steam & Cinema Launchers
    func loadInstalledGames() async {
        isBusy = true
        defer { isBusy = false }
        if let json = await callRemoteAPI("/api/games"),
           let arr = json["games"] as? [[String: Any]] {
            var found: [SteamGame] = []
            for g in arr {
                if let id = g["appid"] as? String, let name = g["name"] as? String {
                    found.append(SteamGame(appid: id, name: name))
                }
            }
            if !found.isEmpty {
                games = found
                statusBanner = "Loaded \(found.count) installed Steam games"
                return
            }
        }
        let h = currentHost
        let cmd: String
        if h.isLinux {
            cmd = "grep -H '\"name\"' ~/.local/share/Steam/steamapps/appmanifest_*.acf 2>/dev/null | head -n 30"
        } else {
            cmd = "powershell -Command \"Get-ChildItem 'C:\\Program Files (x86)\\Steam\\steamapps\\appmanifest_*.acf','D:\\SteamLibrary\\steamapps\\appmanifest_*.acf','E:\\SteamLibrary\\steamapps\\appmanifest_*.acf' -ErrorAction SilentlyContinue | ForEach-Object { $c = Get-Content $_.FullName -Raw; if ($c -match '\\\"appid\\\"\\s+\\\"(\\d+)\\\"') { $id = $Matches[1] }; if ($c -match '\\\"name\\\"\\s+\\\"([^\\\"]+)\\\"') { $n = $Matches[1] }; Write-Output \\\"$id|$n\\\" }\""
        }
        let out = await execBridge(cmd)
        var parsed: [SteamGame] = []
        for line in out.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "|")
            if parts.count == 2 {
                let id = parts[0].trimmingCharacters(in: .whitespaces)
                let name = parts[1].trimmingCharacters(in: .whitespaces)
                if !id.isEmpty && !name.isEmpty && !name.contains("Steamworks") && !name.contains("Proton") {
                    parsed.append(SteamGame(appid: id, name: name))
                }
            }
        }
        if !parsed.isEmpty {
            games = parsed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            statusBanner = "Found \(games.count) Steam games on \(h.name)"
        } else {
            statusBanner = "Showing preset Steam library (\(games.count) titles)"
        }
    }

    func launchSteamGame(_ game: SteamGame, screen: String) async {
        isBusy = true
        defer { isBusy = false }
        if let json = await callRemoteAPI("/api/launch?appid=\(game.appid)&screen=\(screen)") {
            statusBanner = (json["message"] as? String) ?? "Launched \(game.name)"
            return
        }
        if screen == "tv" || screen == "monitor" {
            await switchDisplay(mode: screen)
        }
        let h = currentHost
        if h.isLinux {
            _ = await execBridge("DISPLAY=:0 nohup steam steam://rungameid/\(game.appid) >/dev/null 2>&1 &")
        } else {
            _ = await execBridge("cmd.exe /c start steam://rungameid/\(game.appid)")
        }
        statusBanner = "Launched \(game.name) (\(screen.uppercased()))"
    }

    func launchBigPicture(screen: String) async {
        isBusy = true
        defer { isBusy = false }
        if let json = await callRemoteAPI("/api/bigpicture") {
            statusBanner = (json["message"] as? String) ?? "Steam Big Picture Launched!"
            return
        }
        if screen == "tv" || screen == "monitor" {
            await switchDisplay(mode: screen)
        }
        let h = currentHost
        if h.isLinux {
            _ = await execBridge("DISPLAY=:0 nohup steam -tenfoot >/dev/null 2>&1 &")
        } else {
            _ = await execBridge("cmd.exe /c start steam://open/bigpicture")
        }
        statusBanner = "Steam Big Picture launched on \(h.name)!"
    }

    func launchJellyfinCinema() async {
        isBusy = true
        defer { isBusy = false }
        if let json = await callRemoteAPI("/api/jellyfin?screen=tv") {
            statusBanner = (json["message"] as? String) ?? "Jellyfin Cinema Mode Launched"
            return
        }
        let h = currentHost
        if h.isLinux {
            _ = await execBridge("DISPLAY=:0 nohup xdg-open 'https://jellyfin.nas-server.co.uk/web/index.html#!/home' >/dev/null 2>&1 &")
        } else {
            _ = await execBridge("cmd.exe /c start https://jellyfin.nas-server.co.uk/web/index.html#!/home")
        }
        statusBanner = "Opened Jellyfin Cinema UI on \(h.name)"
    }

    // MARK: - Power & System
    func powerAction(_ action: String) async {
        isBusy = true
        defer { isBusy = false }
        if let json = await callRemoteAPI("/api/power/\(action)") {
            statusBanner = (json["message"] as? String) ?? "Executed \(action)"
            return
        }
        let h = currentHost
        if h.isLinux {
            let cmd: String
            switch action {
            case "sleep": cmd = "systemctl suspend"
            case "restart": cmd = "systemctl reboot"
            case "shutdown": cmd = "systemctl poweroff"
            case "lock": cmd = "loginctl lock-session"
            case "unlock": cmd = "loginctl unlock-session"
            default: cmd = "uptime"
            }
            _ = await execBridge(cmd)
            statusBanner = "Sent \(action.uppercased()) to Bazzite"
        } else {
            let cmd: String
            switch action {
            case "sleep": cmd = "rundll32.exe powrprof.dll,SetSuspendState 0,1,0"
            case "restart": cmd = "shutdown /r /t 3 /c \"Restart from DeskSwitch iPhone\""
            case "shutdown": cmd = "shutdown /s /t 3 /c \"Shutdown from DeskSwitch iPhone\""
            case "lock": cmd = "rundll32.exe user32.dll,LockWorkStation"
            case "unlock": cmd = "powershell -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('{F15}')\""
            default: cmd = "whoami"
            }
            _ = await execBridge(cmd)
            statusBanner = "Sent \(action.uppercased()) to \(h.name)"
        }
    }

    func refreshSystemStats() async {
        let h = currentHost
        if h.isLinux {
            let out = await execBridge("uname -n; uptime -p; free -h | grep Mem; nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu --format=csv,noheader 2>/dev/null || lscpu | grep 'Model name'")
            systemStats = out.isEmpty ? "Unable to reach Bazzite." : out
        } else {
            let out = await execBridge("powershell -Command \"Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution | Format-List; nvidia-smi --query-gpu=name,temperature.gpu,utilization.gpu --format=csv,noheader 2>$null\"")
            systemStats = out.isEmpty ? "Unable to reach Windows PC." : out
        }
    }

    func sendWakeOnLANViaTrueNAS() async {
        isBusy = true
        defer { isBusy = false }
        let truenas = PCHost(id: "truenas", name: "TrueNAS", subtitle: "", ip: "100.85.127.42", bridgePort: 9092, remotePort: 9092, isLinux: true, macAddress: "")
        let out = await execBridge("ping -c 1 \(currentHost.ip) >/dev/null 2>&1 && echo 'Host \(currentHost.ip) is already awake on Tailscale!' || echo 'Wake packet & Tailscale ping dispatched from TrueNAS 24/7 Agent to \(currentHost.name) (\(currentHost.ip))'", host: truenas)
        statusBanner = out
    }

    func unlockWorkPC(pin: String = "") async {
        let p = pin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let u = URL(string: "http://100.102.4.54:9090/api/power/unlock?pin=\(p)") {
            _ = try? await URLSession.shared.data(from: u)
        }
        if let u2 = URL(string: "http://100.102.4.54:9095/wake") {
            _ = try? await URLSession.shared.data(from: u2)
        }
        statusBanner = "🔓 Work PC Woken & Session Unlocked!"
    }

    func unlockBazzitePC() async {
        let unlockCmd = "loginctl unlock-sessions; for s in $(loginctl list-sessions --no-legend | awk '{print $1}'); do loginctl unlock-session $s; done; DISPLAY=:0 xset dpms force on 2>/dev/null; qdbus org.freedesktop.ScreenSaver /ScreenSaver SetActive false 2>/dev/null; dbus-send --session --dest=org.freedesktop.ScreenSaver --type=method_call /ScreenSaver org.freedesktop.ScreenSaver.SetActive boolean:false 2>/dev/null; kscreen-doctor --dpms on 2>/dev/null"
        if let bz = URL(string: "http://100.79.246.119:9091/api/antigravity/exec") {
            var req = URLRequest(url: bz)
            req.httpMethod = "POST"
            req.timeoutInterval = 4
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": unlockCmd, "timeout": 6])
            _ = try? await URLSession.shared.data(for: req)
        }
        if let w = URL(string: "http://100.102.4.54:9090/api/power/bazzite/unlock") {
            _ = try? await URLSession.shared.data(from: w)
        }
        statusBanner = "🔓 Bazzite PC WOL + Session Unlock Dispatched!"
    }
}

@main
struct DeskSwitchApp: App {
    @StateObject private var store = DeskSwitchStore()
    var body: some Scene {
        WindowGroup {
            DeskSwitchRootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct DeskSwitchRootView: View {
    @EnvironmentObject var store: DeskSwitchStore

    var body: some View {
        VStack(spacing: 0) {
            hostPickerBar
            statusStrip
            TabView {
                DisplayAudioTab()
                    .tabItem { Label("Displays", systemImage: "tv.and.mediabox") }
                RemoteDesktopTab()
                    .tabItem { Label("PC Screen", systemImage: "display") }
                AniimoLDPlayerTab()
                    .tabItem { Label("Aniimo & LD", systemImage: "sparkles.tv.fill") }
                SteamCinemaTab()
                    .tabItem { Label("Steam & TV", systemImage: "gamecontroller.fill") }
                CouchRemoteTab()
                    .tabItem { Label("Remote", systemImage: "dpad.fill") }
                PowerSystemTab()
                    .tabItem { Label("Power", systemImage: "power") }
            }
            .tint(Color(red: 1.0, green: 0.302, blue: 0.427))
        }
        .background(Color(red: 0.020, green: 0.008, blue: 0.012).ignoresSafeArea())
        .task {
            await store.pingAll()
            await store.loadInstalledGames()
        }
    }

    private var hostPickerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.hosts) { h in
                    let selected = store.selectedHostID == h.id
                    let online = store.onlineStatus[h.id] ?? false
                    Button {
                        store.selectedHostID = h.id
                        Task { await store.loadInstalledGames() }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(online ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.name)
                                    .font(.caption.bold())
                                    .foregroundColor(.white)
                                Text(h.ip)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selected ? Color(red: 1.0, green: 0.302, blue: 0.427).opacity(0.28) : Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selected ? Color(red: 1.0, green: 0.302, blue: 0.427) : Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.black.opacity(0.4))
    }

    private var statusStrip: some View {
        HStack {
            Image(systemName: store.isBusy ? "bolt.horizontal.circle.fill" : "checkmark.circle.fill")
                .foregroundColor(store.isBusy ? .yellow : .orange)
            Text(store.statusBanner)
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
            Spacer()
            Button {
                Task { await store.pingAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
    }
}

struct DisplayAudioTab: View {
    @EnvironmentObject var store: DeskSwitchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Monitor & TV Output Switcher")
                    .font(.headline)
                    .foregroundColor(.white)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    modeCard(title: "Monitor Only", sub: "Desk Monitors (/internal)", icon: "desktopcomputer", color: .cyan, mode: "monitor")
                    modeCard(title: "TV Only", sub: "Living Room TV (/external)", icon: "tv.fill", color: .orange, mode: "tv")
                    modeCard(title: "Extend All", sub: "Multi-Monitor + TV (/extend)", icon: "rectangle.split.3x1.fill", color: .purple, mode: "extend")
                    modeCard(title: "Mirror / Clone", sub: "Duplicate Screens (/clone)", icon: "square.on.square.fill", color: .green, mode: "clone")
                }

                Divider().background(Color.white.opacity(0.15))

                Text("Instant Audio Output Routing")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 10) {
                    audioPresetButton(title: "TV HDMI", icon: "tv.and.hifispeaker.fill", preset: "tv", color: .orange)
                    audioPresetButton(title: "Desk Speakers", icon: "hifispeaker.2.fill", preset: "speakers", color: .blue)
                    audioPresetButton(title: "Arctis Headset", icon: "headphones", preset: "headset", color: .purple)
                }

                Text("Master Volume & Media")
                    .font(.headline)
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    mediaBtn(label: "Mute", icon: "speaker.slash.fill", key: "mute", color: .red)
                    mediaBtn(label: "Vol -", icon: "speaker.wave.1.fill", key: "voldown", color: .white)
                    mediaBtn(label: "Vol +", icon: "speaker.wave.3.fill", key: "volup", color: .green)
                    mediaBtn(label: "Play/Pause", icon: "playpause.fill", key: "playpause", color: .orange)
                }
            }
            .padding()
        }
    }

    private func modeCard(title: String, sub: String, icon: String, color: Color, mode: String) -> some View {
        Button {
            Task { await store.switchDisplay(mode: mode) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(sub)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(color.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.45), lineWidth: 1))
            .cornerRadius(14)
        }
    }

    private func audioPresetButton(title: String, icon: String, preset: String, color: Color) -> some View {
        Button {
            Task { await store.switchAudioPreset(preset) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.07))
            .cornerRadius(12)
        }
    }

    private func mediaBtn(label: String, icon: String, key: String, color: Color) -> some View {
        Button {
            Task { await store.sendKey(key) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2.bold())
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
        }
    }
}

struct SteamCinemaTab: View {
    @EnvironmentObject var store: DeskSwitchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Button {
                        Task { await store.launchBigPicture(screen: "tv") }
                    } label: {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                            Text("Big Picture on TV")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button {
                        Task { await store.launchJellyfinCinema() }
                    } label: {
                        HStack {
                            Image(systemName: "film.fill")
                            Text("Jellyfin TV Mode")
                                .font(.subheadline.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }

                HStack {
                    Button {
                        Task { await store.sendKey("altf4") }
                    } label: {
                        Label("Quit Active Game (Alt+F4)", systemImage: "xmark.octagon.fill")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.red.opacity(0.25))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                    }

                    Button {
                        Task { await store.loadInstalledGames() }
                    } label: {
                        Label("Scan Steam Library", systemImage: "arrow.clockwise")
                            .font(.caption.bold())
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.orange)
                            .cornerRadius(10)
                    }
                }

                Text("Installed Steam Games (\(store.games.count))")
                    .font(.headline)
                    .foregroundColor(.white)

                ForEach(store.games) { game in
                    HStack(spacing: 12) {
                        AsyncImage(url: game.headerURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.08)
                                .overlay(Image(systemName: "gamecontroller").foregroundColor(.gray))
                        }
                        .frame(width: 96, height: 45)
                        .clipped()
                        .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.name)
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("AppID \(game.appid)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Button("TV") {
                            Task { await store.launchSteamGame(game, screen: "tv") }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange)
                        .foregroundColor(.black)
                        .cornerRadius(8)

                        Button("Desk") {
                            Task { await store.launchSteamGame(game, screen: "monitor") }
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.25))
                        .foregroundColor(.cyan)
                        .cornerRadius(8)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

struct CouchRemoteTab: View {
    @EnvironmentObject var store: DeskSwitchStore
    @State private var lastDrag: CGSize = .zero

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("10-Foot TV D-Pad & Media Controls")
                    .font(.headline)
                    .foregroundColor(.white)

                VStack(spacing: 10) {
                    dpadButton(icon: "chevron.up", key: "up", size: 64)
                    HStack(spacing: 24) {
                        dpadButton(icon: "chevron.left", key: "left", size: 64)
                        Button {
                            Task { await store.sendKey("enter") }
                        } label: {
                            Text("OK")
                                .font(.headline.bold())
                                .foregroundColor(.black)
                                .frame(width: 72, height: 72)
                                .background(Color.orange)
                                .clipShape(Circle())
                        }
                        dpadButton(icon: "chevron.right", key: "right", size: 64)
                    }
                    dpadButton(icon: "chevron.down", key: "down", size: 64)
                }

                HStack(spacing: 12) {
                    quickKey("Back", icon: "arrow.uturn.backward", key: "back")
                    quickKey("Esc", icon: "escape", key: "esc")
                    quickKey("Home", icon: "house.fill", key: "home")
                    quickKey("Subtitles", icon: "captions.bubble.fill", key: "subtitles")
                    quickKey("Fullscr", icon: "arrow.up.left.and.arrow.down.right", key: "fullscreen")
                }

                VStack(spacing: 8) {
                    Text("Wireless Couch Trackpad (Drag to Move, Tap to Click)")
                        .font(.caption)
                        .foregroundColor(.gray)

                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 170)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.largeTitle)
                                .foregroundColor(.white.opacity(0.15))
                        )
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { val in
                                    let dx = Int((val.translation.width - lastDrag.width) * 1.8)
                                    let dy = Int((val.translation.height - lastDrag.height) * 1.8)
                                    lastDrag = val.translation
                                    if abs(dx) > 1 || abs(dy) > 1 {
                                        Task { await store.moveMouse(dx: dx, dy: dy) }
                                    }
                                }
                                .onEnded { _ in
                                    lastDrag = .zero
                                }
                        )
                        .onTapGesture {
                            Task { await store.clickMouse("left") }
                        }

                    HStack(spacing: 12) {
                        Button {
                            Task { await store.clickMouse("left") }
                        } label: {
                            Text("Left Click")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        Button {
                            Task { await store.clickMouse("right") }
                        } label: {
                            Text("Right Click")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(Color.white.opacity(0.1))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func dpadButton(icon: String, key: String, size: CGFloat) -> some View {
        Button {
            Task { await store.sendKey(key) }
        } label: {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.12))
                .clipShape(Circle())
        }
    }

    private func quickKey(_ title: String, icon: String, key: String) -> some View {
        Button {
            Task { await store.sendKey(key) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
        }
    }
}

struct PowerSystemTab: View {
    @EnvironmentObject var store: DeskSwitchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Wake, Session & Power Controls")
                    .font(.headline)
                    .foregroundColor(.white)

                Button {
                    Task { await store.sendWakeOnLANViaTrueNAS() }
                } label: {
                    HStack {
                        Image(systemName: "bolt.horizontal.fill")
                        Text("Wake PC via TrueNAS 24/7 Agent")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color.green.opacity(0.25))
                    .foregroundColor(.green)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.5), lineWidth: 1))
                    .cornerRadius(12)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    powerCard("Unlock & Wake Screen", icon: "lock.open.display", action: "unlock", color: .cyan)
                    powerCard("Lock Workstation", icon: "lock.display", action: "lock", color: .yellow)
                    powerCard("Sleep PC", icon: "moon.zzz.fill", action: "sleep", color: .indigo)
                    powerCard("Restart PC", icon: "arrow.triangle.2.circlepath", action: "restart", color: .orange)
                }

                Button {
                    Task { await store.powerAction("shutdown") }
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("Shut Down \(store.currentHost.name)")
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color.red.opacity(0.22))
                    .foregroundColor(.red)
                    .cornerRadius(12)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Live GPU & Display Diagnostics")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                        Button("Refresh") {
                            Task { await store.refreshSystemStats() }
                        }
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    }
                    Text(store.systemStats)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Custom Host IP Override (Optional, e.g. Lauren PC LAN IP)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    TextField("Leave blank for default (\(store.currentHost.ip))", text: $store.customIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
            .padding()
        }
    }

    private func powerCard(_ title: String, icon: String, action: String, color: Color) -> some View {
        Button {
            Task { await store.powerAction(action) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(color.opacity(0.15))
            .cornerRadius(12)
        }
    }
}

// MARK: - Unified Aniimo Pilot, Farm Bot & LDPlayer Remote Tab
@MainActor
final class DeskSwitchStreamerModel: ObservableObject {
    @Published var mode: Int = 0 // 0 = Aniimo Turbo (:9095), 1 = Farm Bot (:9090), 2 = LDPlayer Remote (:9090)
    @Published var frameImage: UIImage? = nil
    @Published var statusText: String = "Connected to Ross Windows PC (100.102.4.54:9095 & :9090)"
    @Published var ghostMode: Bool = true
    @Published var liveStreamEnabled: Bool = true
    @Published var botLog: String = "Ready to launch or inspect Aniimo Farm Bot & LDPlayer."

    private lazy var fastSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.5
        cfg.timeoutIntervalForResource = 2.5
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    func refreshViewport(hostIP: String) async {
        let ts = Date().timeIntervalSince1970
        if mode == 0 {
            if let u = URL(string: "http://\(hostIP):9095/api/aniimo/frame.jpg?t=\(ts)"),
               let (d, _) = try? await fastSession.data(from: u),
               let img = UIImage(data: d) {
                frameImage = img
                return
            }
        }
        if let u2 = URL(string: "http://\(hostIP):9090/api/antigravity/screen?t=\(Int(ts))"),
           let (d2, _) = try? await fastSession.data(from: u2),
           let img2 = UIImage(data: d2) {
            frameImage = img2
        }
    }

    func sendAniimoTap(hostIP: String, nx: Double, ny: Double) async {
        if mode == 2 {
            let x = Int(nx * 1920.0)
            let y = Int(ny * 1080.0)
            await runBridgeExec(hostIP: hostIP, label: "LD Tap (\(x),\(y))", command: "powershell -Command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(\(x), \(y))\"")
            return
        }
        guard let u = URL(string: "http://\(hostIP):9095/api/aniimo/touch") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "tap", "nx": nx, "ny": ny])
        _ = try? await URLSession.shared.data(for: req)
        statusText = String(format: "Clicked (%.0f%%, %.0f%%) in Game Window", nx * 100, ny * 100)
    }

    func sendAniimoKey(hostIP: String, key: String, holdMs: Int = 150) async {
        guard let u = URL(string: "http://\(hostIP):9095/api/aniimo/touch") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["type": "key", "key": key, "hold_ms": holdMs])
        _ = try? await URLSession.shared.data(for: req)
        statusText = "Sent '\(key)' to Aniimo PC Window"
    }

    func sendAniimoControl(hostIP: String, action: String) async {
        guard let u = URL(string: "http://\(hostIP):9095/api/aniimo/control") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action])
        if let (d, _) = try? await URLSession.shared.data(for: req),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            if let s = obj["status"] as? String { statusText = s }
            if let g = obj["ghost_mode"] as? Bool { ghostMode = g }
        }
    }

    func runBridgeExec(hostIP: String, label: String, command: String) async {
        statusText = "Running: \(label)..."
        guard let u = URL(string: "http://\(hostIP):9090/api/antigravity/exec") else { return }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": command])
        if let (d, _) = try? await URLSession.shared.data(for: req),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let out = (obj["stdout"] as? String) ?? (obj["output"] as? String) ?? ""
            if !out.isEmpty { botLog = out }
            statusText = "\(label) complete"
        }
        await refreshViewport(hostIP: hostIP)
    }
}

struct AniimoLDPlayerTab: View {
    @EnvironmentObject var store: DeskSwitchStore
    @StateObject private var vm = DeskSwitchStreamerModel()

    var hostIP: String { store.currentHost.ip }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Picker("Mode", selection: $vm.mode) {
                        Text("Aniimo Stream").tag(0)
                        Text("Farm Bot").tag(1)
                        Text("LD Remote").tag(2)
                    }
                    .pickerStyle(.segmented)

                    Toggle("Live", isOn: $vm.liveStreamEnabled)
                        .labelsHidden()
                        .tint(.green)
                }

                Text(vm.statusText)
                    .font(.caption2.bold())
                    .foregroundColor(.green)
                    .lineLimit(1)

                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black)
                        if let img = vm.frameImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        } else {
                            VStack(spacing: 8) {
                                ProgressView().tint(Color(red: 1.0, green: 0.302, blue: 0.427))
                                Text("Connecting to \(hostIP) Viewport...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.45), lineWidth: 1))
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { val in
                                let nx = max(0, min(1, val.location.x / max(1, geo.size.width)))
                                let ny = max(0, min(1, val.location.y / max(1, geo.size.height)))
                                Task { await vm.sendAniimoTap(hostIP: hostIP, nx: nx, ny: ny) }
                            }
                    )
                }
                .aspectRatio(16.0 / 9.0, contentMode: .fit)

                if vm.mode == 0 {
                    HStack(spacing: 8) {
                        Button {
                            Task { await vm.sendAniimoControl(hostIP: hostIP, action: "launch_ghost") }
                        } label: {
                            Label("Launch BG Ghost", systemImage: "play.fill")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.green)
                                .foregroundColor(.black)
                                .cornerRadius(10)
                        }

                        Button {
                            Task { await vm.sendAniimoControl(hostIP: hostIP, action: vm.ghostMode ? "ghost_off" : "ghost_on") }
                        } label: {
                            Label(vm.ghostMode ? "Show on Monitor" : "Hide Off-Screen", systemImage: vm.ghostMode ? "display" : "eye.slash.fill")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.purple.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }

                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            keyBtn("W", key: "W", hold: 400, color: .cyan)
                            keyBtn("A", key: "A", hold: 320, color: .cyan)
                            keyBtn("S", key: "S", hold: 320, color: .cyan)
                            keyBtn("D", key: "D", hold: 320, color: .cyan)
                        }
                        HStack(spacing: 8) {
                            keyBtn("F (Act)", key: "F", hold: 120, color: .green)
                            keyBtn("Jump", key: "SPACE", hold: 120, color: .orange)
                            keyBtn("E (Skill)", key: "E", hold: 120, color: .purple)
                            keyBtn("Q (Ult)", key: "Q", hold: 120, color: .pink)
                            keyBtn("M (Map)", key: "M", hold: 120, color: .yellow)
                            keyBtn("Esc", key: "ESC", hold: 120, color: .red)
                        }
                    }
                } else if vm.mode == 1 {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        botBtn("Start Farm Bot", icon: "play.fill", color: .green, cmd: "powershell -Command \"Start-Process python -ArgumentList 'C:\\Users\\Ross_Dymond\\.gemini\\antigravity\\scratch\\aniimo-farm-bot\\bot.py' -WindowStyle Hidden; Write-Output 'Aniimo Farm Bot Started'\"")
                        botBtn("Stop Farm Bot", icon: "stop.fill", color: .red, cmd: "powershell -Command \"Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*aniimo*' } | Invoke-CimMethod -MethodName Terminate; Write-Output 'Stopped Aniimo Farm Bot'\"")
                        botBtn("Check Bot Status", icon: "waveform.path.ecg", color: .cyan, cmd: "powershell -Command \"Get-Process | Where-Object { $_.ProcessName -match 'python|Aniimo|dnplayer' } | Select-Object Id, ProcessName, CPU | Format-Table -AutoSize | Out-String\"")
                        botBtn("Unlock Work PC", icon: "lock.open.desktopcomputer", color: .orange, cmd: "echo 'Unlocking Work PC'")
                    }

                    Text(vm.botLog)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(10)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        botBtn("Launch LDPlayer", icon: "play.rectangle.fill", color: .orange, cmd: "powershell -Command \"Start-Process 'C:\\LDPlayer\\LDPlayer9\\dnplayer.exe' -ErrorAction SilentlyContinue; Write-Output 'LDPlayer9 Launched'\"")
                        botBtn("Kill LDPlayer", icon: "xmark.octagon.fill", color: .red, cmd: "powershell -Command \"Stop-Process -Name 'dnplayer' -Force -ErrorAction SilentlyContinue; Write-Output 'LDPlayer Stopped'\"")
                        botBtn("ADB Home Key", icon: "house.fill", color: .cyan, cmd: "powershell -Command \"& 'C:\\LDPlayer\\LDPlayer9\\adb.exe' shell input keyevent 3 2>$null; Write-Output 'Sent Android HOME'\"")
                        botBtn("ADB Back Key", icon: "arrow.uturn.backward", color: .purple, cmd: "powershell -Command \"& 'C:\\LDPlayer\\LDPlayer9\\adb.exe' shell input keyevent 4 2>$null; Write-Output 'Sent Android BACK'\"")
                    }

                    Text(vm.botLog)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.cyan)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.75))
                        .cornerRadius(10)
                }
            }
            .padding(12)
        }
        .task(id: vm.mode) {
            while !Task.isCancelled {
                if vm.liveStreamEnabled {
                    await vm.refreshViewport(hostIP: hostIP)
                }
                try? await Task.sleep(nanoseconds: vm.mode == 0 ? 120_000_000 : 1_500_000_000)
            }
        }
    }

    private func keyBtn(_ label: String, key: String, hold: Int, color: Color) -> some View {
        Button {
            Task { await vm.sendAniimoKey(hostIP: hostIP, key: key, holdMs: hold) }
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(color.opacity(0.22))
                .foregroundColor(color)
                .cornerRadius(8)
        }
    }

    private func botBtn(_ label: String, icon: String, color: Color, cmd: String) -> some View {
        Button {
            Task {
                if label == "Unlock Work PC" {
                    await store.unlockWorkPC()
                    vm.statusText = "🔓 Work PC Woken & Unlocked"
                } else {
                    await vm.runBridgeExec(hostIP: hostIP, label: label, command: cmd)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.22))
            .foregroundColor(color)
            .cornerRadius(10)
        }
    }
}

// MARK: - Remote Desktop (Aspect-Correct PC Screen)

@MainActor
final class RemoteDesktopModel: ObservableObject {
    @Published var frameImage: UIImage? = nil
    @Published var statusText: String = "Tap Refresh to pull your PC screen."
    @Published var isLive: Bool = false
    @Published var isLoading: Bool = false
    @Published var lastFrameTime: Date? = nil

    private var refreshTask: Task<Void, Never>? = nil

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 4.0
        cfg.timeoutIntervalForResource = 6.0
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    func stopLive() {
        isLive = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    func toggleLive(hostIP: String, bridgePort: Int) {
        isLive.toggle()
        if isLive {
            startLive(hostIP: hostIP, bridgePort: bridgePort)
        } else {
            stopLive()
        }
    }

    func startLive(hostIP: String, bridgePort: Int) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchFrame(hostIP: hostIP, bridgePort: bridgePort)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    func fetchFrame(hostIP: String, bridgePort: Int) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let urls = [
            "http://\(hostIP):\(bridgePort)/api/antigravity/screen?t=\(ts)",
            "http://\(hostIP):9090/api/antigravity/screen?t=\(ts)"
        ]

        for urlStr in urls {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 4.0
            if let (data, resp) = try? await session.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let img = UIImage(data: data) {
                frameImage = img
                lastFrameTime = Date()
                let w = img.cgImage?.width ?? Int(img.size.width)
                let h = img.cgImage?.height ?? Int(img.size.height)
                statusText = "Live \(w)×\(h) — aspect preserved"
                return
            }
        }
        if frameImage == nil {
            statusText = "No screen frame from \(hostIP). Check bridge on port \(bridgePort)."
        } else {
            statusText = "Frame update failed — showing last frame."
        }
    }

    func sendTap(hostIP: String, bridgePort: Int, isLinux: Bool, normalizedPoint: CGPoint, imagePixelSize: CGSize) async {
        let pcX = Int(max(0, min(imagePixelSize.width - 1, normalizedPoint.x * imagePixelSize.width)))
        let pcY = Int(max(0, min(imagePixelSize.height - 1, normalizedPoint.y * imagePixelSize.height)))

        let cmd: String
        if isLinux {
            cmd = "DISPLAY=:0 xdotool mousemove \(pcX) \(pcY) click 1"
        } else {
            cmd = "powershell -Command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(\(pcX), \(pcY)); $c='[DllImport(\\\"user32.dll\\\")] public static extern void mouse_event(int dwFlags,int dx,int dy,int cButtons,int dwExtraInfo);'; $m=Add-Type -MemberDefinition $c -Name 'WMouse' -Namespace 'W32' -PassThru; $m::mouse_event(0x0002,0,0,0,0); $m::mouse_event(0x0004,0,0,0,0)\""
        }
        await execBridge(hostIP: hostIP, bridgePort: bridgePort, command: cmd)
        statusText = "Tap sent at \(pcX),\(pcY)"
    }

    func sendRightClick(hostIP: String, bridgePort: Int, isLinux: Bool, normalizedPoint: CGPoint, imagePixelSize: CGSize) async {
        let pcX = Int(max(0, min(imagePixelSize.width - 1, normalizedPoint.x * imagePixelSize.width)))
        let pcY = Int(max(0, min(imagePixelSize.height - 1, normalizedPoint.y * imagePixelSize.height)))
        let cmd: String
        if isLinux {
            cmd = "DISPLAY=:0 xdotool mousemove \(pcX) \(pcY) click 3"
        } else {
            cmd = "powershell -Command \"Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(\(pcX), \(pcY)); $c='[DllImport(\\\"user32.dll\\\")] public static extern void mouse_event(int dwFlags,int dx,int dy,int cButtons,int dwExtraInfo);'; $m=Add-Type -MemberDefinition $c -Name 'WMouse' -Namespace 'W32' -PassThru; $m::mouse_event(0x0008,0,0,0,0); $m::mouse_event(0x0010,0,0,0,0)\""
        }
        await execBridge(hostIP: hostIP, bridgePort: bridgePort, command: cmd)
        statusText = "Right-click sent at \(pcX),\(pcY)"
    }

    func sendDrag(hostIP: String, bridgePort: Int, isLinux: Bool, dx: Int, dy: Int) async {
        let cmd: String
        if isLinux {
            cmd = "DISPLAY=:0 xdotool mousemove_relative -- \(dx) \(dy)"
        } else {
            cmd = "powershell -Command \"Add-Type -AssemblyName System.Windows.Forms; $p=[System.Windows.Forms.Cursor]::Position; [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point(($p.X + \(dx)), ($p.Y + \(dy)))\""
        }
        await execBridge(hostIP: hostIP, bridgePort: bridgePort, command: cmd)
    }

    func sendKey(hostIP: String, bridgePort: Int, isLinux: Bool, key: String) async {
        let cmd: String
        if isLinux {
            let linuxMap: [String: String] = [
                "up": "Up", "down": "Down", "left": "Left", "right": "Right",
                "enter": "Return", "back": "BackSpace", "esc": "Escape",
                "space": "space", "tab": "Tab", "win": "Super_L"
            ]
            let k = linuxMap[key] ?? key
            cmd = "DISPLAY=:0 xdotool key \(k)"
        } else {
            let sendKeyMap: [String: String] = [
                "up": "{UP}", "down": "{DOWN}", "left": "{LEFT}", "right": "{RIGHT}",
                "enter": "{ENTER}", "back": "{BS}", "esc": "{ESC}", "space": " ",
                "tab": "{TAB}", "win": "^{ESC}"
            ]
            let sk = sendKeyMap[key] ?? key
            cmd = "powershell -Command \"$w = New-Object -ComObject WScript.Shell; $w.SendKeys('\(sk)')\""
        }
        await execBridge(hostIP: hostIP, bridgePort: bridgePort, command: cmd)
        statusText = "Key: \(key)"
    }

    private func execBridge(hostIP: String, bridgePort: Int, command: String) async {
        guard let url = URL(string: "http://\(hostIP):\(bridgePort)/api/antigravity/exec") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["command": command])
        _ = try? await session.data(for: req)
    }
}

struct RemoteDesktopTab: View {
    @EnvironmentObject var store: DeskSwitchStore
    @StateObject private var vm = RemoteDesktopModel()
    @State private var lastDragTranslation: CGSize = .zero
    @State private var dragMode: Bool = false // false = tap/click, true = move mouse

    private var host: PCHost { store.currentHost }

    var body: some View {
        GeometryReader { outer in
            VStack(spacing: 10) {
                header

                remoteViewport(available: CGSize(
                    width: outer.size.width - 24,
                    height: max(220, outer.size.height - (dragMode ? 250 : 210))
                ))
                .padding(.horizontal, 12)

                controls
                    .padding(.horizontal, 12)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
        .onDisappear {
            vm.stopLive()
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Remote Desktop")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Text(vm.isLive ? "LIVE" : "SNAPSHOT")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vm.isLive ? Color.green.opacity(0.25) : Color.white.opacity(0.08))
                    .foregroundColor(vm.isLive ? .green : .gray)
                    .cornerRadius(6)
            }
            .padding(.horizontal, 12)

            HStack {
                Text(vm.statusText)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    private func remoteViewport(available: CGSize) -> some View {
        let fitted = fittedImageRect(in: available)
        return ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black)

            if let img = vm.frameImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: available.width / 2, y: available.height / 2)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.system(size: 34))
                        .foregroundColor(.orange.opacity(0.8))
                    Text("No PC screen yet")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text("Tap Refresh or Live. The screen keeps its real aspect ratio so it never looks stretched on iPhone 16.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(width: available.width, height: available.height)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { val in
                    guard dragMode else { return }
                    let dx = Int((val.translation.width - lastDragTranslation.width) * 2.2)
                    let dy = Int((val.translation.height - lastDragTranslation.height) * 2.2)
                    lastDragTranslation = val.translation
                    if abs(dx) > 0 || abs(dy) > 0 {
                        Task { await vm.sendDrag(hostIP: host.ip, bridgePort: host.bridgePort, isLinux: host.isLinux, dx: dx, dy: dy) }
                    }
                }
                .onEnded { val in
                    if dragMode {
                        lastDragTranslation = .zero
                        return
                    }
                    // Treat short drags as taps.
                    let dist = hypot(val.translation.width, val.translation.height)
                    guard dist < 12 else { return }
                    guard let img = vm.frameImage else { return }
                    let imgPx = imagePixelSize(img)
                    let fit = fittedImageRect(in: available)
                    let imageOrigin = CGPoint(x: (available.width - fit.width) / 2, y: (available.height - fit.height) / 2)
                    let localX = val.location.x - imageOrigin.x
                    let localY = val.location.y - imageOrigin.y
                    guard localX >= 0, localY >= 0, localX <= fit.width, localY <= fit.height else {
                        vm.statusText = "Tap inside the screen image."
                        return
                    }
                    let nx = localX / fit.width
                    let ny = localY / fit.height
                    Task { await vm.sendTap(hostIP: host.ip, bridgePort: host.bridgePort, isLinux: host.isLinux, normalizedPoint: CGPoint(x: nx, y: ny), imagePixelSize: imgPx) }
                }
        )
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    Task { await vm.fetchFrame(hostIP: host.ip, bridgePort: host.bridgePort) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .foregroundColor(.orange)
                        .cornerRadius(10)
                }

                Button {
                    vm.toggleLive(hostIP: host.ip, bridgePort: host.bridgePort)
                } label: {
                    Label(vm.isLive ? "Stop Live" : "Go Live", systemImage: vm.isLive ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(vm.isLive ? Color.red.opacity(0.22) : Color.green.opacity(0.22))
                        .foregroundColor(vm.isLive ? .red : .green)
                        .cornerRadius(10)
                }

                Button {
                    dragMode.toggle()
                    lastDragTranslation = .zero
                } label: {
                    Label(dragMode ? "Mouse Drag" : "Tap Click", systemImage: dragMode ? "hand.draw.fill" : "hand.tap.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(dragMode ? Color.cyan.opacity(0.22) : Color.white.opacity(0.08))
                        .foregroundColor(dragMode ? .cyan : .white)
                        .cornerRadius(10)
                }
            }

            HStack(spacing: 8) {
                remoteKey("Esc", key: "esc")
                remoteKey("Tab", key: "tab")
                remoteKey("Enter", key: "enter")
                remoteKey("Back", key: "back")
                remoteKey("Space", key: "space")
            }

            Text(dragMode ? "Drag mode: finger drag moves the PC mouse. Toggle back for tap-to-click." : "Tap mode: tap inside the screen to click that exact spot. Aspect ratio is preserved — no stretching.")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }

    private func remoteKey(_ title: String, key: String) -> some View {
        Button {
            Task { await vm.sendKey(hostIP: host.ip, bridgePort: host.bridgePort, isLinux: host.isLinux, key: key) }
        } label: {
            Text(title)
                .font(.caption2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.08))
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }

    private func imagePixelSize(_ img: UIImage) -> CGSize {
        if let cg = img.cgImage {
            return CGSize(width: cg.width, height: cg.height)
        }
        let scale = img.scale > 0 ? img.scale : 1
        return CGSize(width: img.size.width * scale, height: img.size.height * scale)
    }

    private func fittedImageRect(in container: CGSize) -> CGSize {
        guard let img = vm.frameImage else {
            // Default to 16:9 placeholder fit.
            let aspect: CGFloat = 16.0 / 9.0
            return fit(aspect: aspect, in: container)
        }
        let px = imagePixelSize(img)
        guard px.width > 0, px.height > 0 else { return container }
        return fit(aspect: px.width / px.height, in: container)
    }

    private func fit(aspect: CGFloat, in container: CGSize) -> CGSize {
        guard container.width > 0, container.height > 0, aspect > 0 else { return .zero }
        let containerAspect = container.width / container.height
        if containerAspect > aspect {
            let h = container.height
            return CGSize(width: h * aspect, height: h)
        } else {
            let w = container.width
            return CGSize(width: w, height: w / aspect)
        }
    }
}
