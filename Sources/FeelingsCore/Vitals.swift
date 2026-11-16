import Foundation

/// Everything the Mac knows about how its body is doing right now.
public struct Vitals: Sendable, Equatable {
    /// CPU load across all cores, 0–100, averaged over the last few samples.
    public var cpuPercent: Double
    public var thermal: Thermal
    /// `nil` on Macs without a battery.
    public var battery: Battery?
    /// RAM in use (app + wired + compressed), 0–100.
    public var memoryUsedPercent: Double
    public var memoryPressure: MemoryPressure
    public var swapUsedGB: Double
    /// Free space on the startup disk, 0–100.
    public var diskFreePercent: Double
    /// Open tabs across running browsers. `nil` when tab counting is off or nothing answered.
    public var browserTabs: Int?
    /// Regular (Dock) apps that are running.
    public var openApps: Int
    public var frontApp: String?
    /// How long `frontApp` has been in front without a switch.
    public var frontAppMinutes: Double
    /// Minutes of activity since the user last stepped away for 5+ minutes.
    public var workMinutes: Double
    /// Seconds since the last keyboard, mouse or trackpad input.
    public var idleSeconds: Double
    /// Days since the last restart.
    public var uptimeDays: Double
    /// Local hour, 0–23.
    public var hour: Int

    public init(
        cpuPercent: Double = 10,
        thermal: Thermal = .nominal,
        battery: Battery? = Battery(percent: 80, onAC: true, charging: false),
        memoryUsedPercent: Double = 50,
        memoryPressure: MemoryPressure = .normal,
        swapUsedGB: Double = 0,
        diskFreePercent: Double = 40,
        browserTabs: Int? = 5,
        openApps: Int = 5,
        frontApp: String? = "Finder",
        frontAppMinutes: Double = 3,
        workMinutes: Double = 20,
        idleSeconds: Double = 2,
        uptimeDays: Double = 1,
        hour: Int = 14
    ) {
        self.cpuPercent = cpuPercent
        self.thermal = thermal
        self.battery = battery
        self.memoryUsedPercent = memoryUsedPercent
        self.memoryPressure = memoryPressure
        self.swapUsedGB = swapUsedGB
        self.diskFreePercent = diskFreePercent
        self.browserTabs = browserTabs
        self.openApps = openApps
        self.frontApp = frontApp
        self.frontAppMinutes = frontAppMinutes
        self.workMinutes = workMinutes
        self.idleSeconds = idleSeconds
        self.uptimeDays = uptimeDays
        self.hour = hour
    }

    /// A relaxed afternoon: the baseline the tests and previews start from.
    public static let calm = Vitals()
}

public enum Thermal: Int, Sendable, Comparable, CaseIterable {
    case nominal, fair, serious, critical

    public static func < (a: Thermal, b: Thermal) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .nominal: "cool"
        case .fair: "warm"
        case .serious: "hot"
        case .critical: "on fire"
        }
    }
}

public struct Battery: Sendable, Equatable {
    public var percent: Int
    public var onAC: Bool
    public var charging: Bool

    public init(percent: Int, onAC: Bool, charging: Bool) {
        self.percent = percent
        self.onAC = onAC
        self.charging = charging
    }
}

public enum MemoryPressure: Int, Sendable, Comparable {
    case normal, warning, critical

    public static func < (a: MemoryPressure, b: MemoryPressure) -> Bool { a.rawValue < b.rawValue }
}

extension Vitals {
    /// Plain-English facts, one per line, for the LLM prompt and the popover.
    public var facts: [String] {
        var out: [String] = []
        out.append("CPU load: \(Int(cpuPercent.rounded()))%")
        out.append("temperature: \(thermal.label)")
        if let b = battery {
            let state = b.charging ? "charging" : (b.onAC ? "plugged in" : "on battery")
            out.append("battery: \(b.percent)%, \(state)")
        }
        out.append("memory used: \(Int(memoryUsedPercent.rounded()))%")
        if swapUsedGB >= 0.5 { out.append(String(format: "swap used: %.1f GB", swapUsedGB)) }
        out.append("free disk space: \(Int(diskFreePercent.rounded()))%")
        if let t = browserTabs { out.append("open browser tabs: \(t)") }
        out.append("open apps: \(openApps)")
        if let app = frontApp {
            out.append("the human is using \(app) (for \(TimeWords.words(minutes: frontAppMinutes)))")
        }
        out.append("the human has worked without a break for \(TimeWords.words(minutes: workMinutes))")
        out.append("days since my last restart: \(String(format: "%.1f", uptimeDays))")
        out.append("local time: \(Clock.words(hour: hour))")
        return out
    }
}

public enum TimeWords {
    /// "4 minutes", "1 hour 20 minutes", "3 hours".
    public static func words(minutes: Double) -> String {
        let m = max(0, Int(minutes.rounded()))
        if m < 60 { return m == 1 ? "1 minute" : "\(m) minutes" }
        let h = m / 60, r = m % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        return r < 5 ? hours : "\(hours) \(r) minutes"
    }
}

public enum Clock {
    /// "3 AM", "12 PM".
    public static func words(hour: Int) -> String {
        let h = ((hour % 24) + 24) % 24
        let twelve = h % 12 == 0 ? 12 : h % 12
        return "\(twelve) \(h < 12 ? "AM" : "PM")"
    }
}
