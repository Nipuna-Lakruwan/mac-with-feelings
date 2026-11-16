import Foundation

public enum Mood: String, CaseIterable, Sendable, Codable {
    case happy
    case content
    case overheated
    case starving
    case overwhelmed
    case bloated
    case sleepy
    case worried
    case cramped

    /// Shown in the menu bar.
    public var emoji: String {
        switch self {
        case .happy: "😄"
        case .content: "🙂"
        case .overheated: "🥵"
        case .starving: "🪫"
        case .overwhelmed: "🤯"
        case .bloated: "😵‍💫"
        case .sleepy: "😴"
        case .worried: "🥺"
        case .cramped: "😖"
        }
    }

    public var title: String {
        switch self {
        case .happy: "Thriving"
        case .content: "Chilling"
        case .overheated: "Sweating"
        case .starving: "Hangry"
        case .overwhelmed: "Overwhelmed"
        case .bloated: "Bloated"
        case .sleepy: "Sleepy"
        case .worried: "Worried about you"
        case .cramped: "Cramped"
        }
    }

    /// True for the moods that are a complaint.
    public var isUpset: Bool {
        switch self {
        case .happy, .content: false
        default: true
        }
    }
}

public struct MoodReading: Sendable, Equatable {
    public var mood: Mood
    /// 0–1. How strongly the Mac feels it.
    public var intensity: Double
    /// Why, in plain English ("62 browser tabs open").
    public var reason: String

    public init(mood: Mood, intensity: Double, reason: String) {
        self.mood = mood
        self.intensity = intensity
        self.reason = reason
    }
}

/// Turns raw vitals into feelings. Pure and deterministic, so it is easy to test.
public enum MoodEngine {
    /// Complaints weaker than this are ignored and the Mac stays calm.
    public static let threshold = 0.3

    /// Every feeling that applies, strongest first.
    public static func readings(for v: Vitals) -> [MoodReading] {
        var r: [MoodReading] = []
        func add(_ mood: Mood, _ intensity: Double, _ reason: String) {
            r.append(MoodReading(mood: mood, intensity: min(1, intensity), reason: reason))
        }

        // Heat. A fanless Air reports thermal pressure before anything else.
        switch v.thermal {
        case .critical: add(.overheated, 1.0, "thermal state is critical")
        case .serious: add(.overheated, 0.85, "thermal state is serious")
        case .fair: add(.overheated, 0.5, "running warm")
        case .nominal: break
        }
        if v.cpuPercent >= 85 {
            add(.overheated, 0.8, "CPU at \(Int(v.cpuPercent))%")
        } else if v.cpuPercent >= 60 {
            add(.overheated, 0.45, "CPU at \(Int(v.cpuPercent))%")
        }

        // Hunger.
        if let b = v.battery, !b.onAC {
            if b.percent <= 10 {
                add(.starving, 1.0, "battery at \(b.percent)%")
            } else if b.percent <= 20 {
                add(.starving, 0.8, "battery at \(b.percent)%")
            } else if b.percent <= 35 {
                add(.starving, 0.4, "battery at \(b.percent)%")
            }
        }

        // Too much going on.
        if let t = v.browserTabs {
            if t >= 100 {
                add(.overwhelmed, 1.0, "\(t) browser tabs open")
            } else if t >= 50 {
                add(.overwhelmed, 0.85, "\(t) browser tabs open")
            } else if t >= 25 {
                add(.overwhelmed, 0.6, "\(t) browser tabs open")
            } else if t >= 12 {
                add(.overwhelmed, 0.35, "\(t) browser tabs open")
            }
        }
        if v.openApps >= 20 {
            add(.overwhelmed, 0.6, "\(v.openApps) apps open")
        } else if v.openApps >= 14 {
            add(.overwhelmed, 0.4, "\(v.openApps) apps open")
        }

        // Memory.
        switch v.memoryPressure {
        case .critical: add(.bloated, 1.0, "memory pressure is critical")
        case .warning: add(.bloated, 0.7, "memory pressure is high")
        case .normal: break
        }
        if v.swapUsedGB >= 2 {
            add(.bloated, 0.6, String(format: "%.1f GB of swap in use", v.swapUsedGB))
        } else if v.swapUsedGB >= 1 {
            add(.bloated, 0.35, String(format: "%.1f GB of swap in use", v.swapUsedGB))
        }
        if v.memoryUsedPercent >= 92 {
            add(.bloated, 0.5, "\(Int(v.memoryUsedPercent))% of memory used")
        }

        // Tired.
        switch v.hour {
        case 1...4: add(.sleepy, 0.85, "it is \(Clock.words(hour: v.hour))")
        case 0, 5: add(.sleepy, 0.6, "it is \(Clock.words(hour: v.hour))")
        case 23: add(.sleepy, 0.4, "it is 11 PM")
        default: break
        }
        if v.uptimeDays >= 14 {
            add(.sleepy, 0.7, "no restart for \(Int(v.uptimeDays)) days")
        } else if v.uptimeDays >= 7 {
            add(.sleepy, 0.5, "no restart for \(Int(v.uptimeDays)) days")
        }

        // Caring about the human.
        if v.workMinutes >= 180 {
            add(.worried, 0.8, "no break for \(TimeWords.words(minutes: v.workMinutes))")
        } else if v.workMinutes >= 120 {
            add(.worried, 0.65, "no break for \(TimeWords.words(minutes: v.workMinutes))")
        } else if v.workMinutes >= 90 {
            add(.worried, 0.4, "no break for \(TimeWords.words(minutes: v.workMinutes))")
        }

        // Disk.
        if v.diskFreePercent <= 5 {
            add(.cramped, 0.9, "only \(Int(v.diskFreePercent.rounded()))% disk space left")
        } else if v.diskFreePercent <= 10 {
            add(.cramped, 0.6, "only \(Int(v.diskFreePercent.rounded()))% disk space left")
        }

        // Strongest first; ties go to the order above, which runs from most to least urgent.
        let ordered = r.enumerated().sorted {
            $0.element.intensity != $1.element.intensity
                ? $0.element.intensity > $1.element.intensity
                : $0.offset < $1.offset
        }.map(\.element)
        // Keep only the strongest reading per mood.
        var seen = Set<Mood>()
        return ordered.filter { seen.insert($0.mood).inserted }
    }

    /// The one feeling that wins right now.
    public static func mood(for v: Vitals) -> MoodReading {
        if let top = readings(for: v).first, top.intensity >= threshold {
            return top
        }
        let charged = v.battery.map { $0.onAC && $0.percent >= 95 } ?? false
        if v.cpuPercent < 25 && v.thermal == .nominal && (charged || v.battery == nil) {
            return MoodReading(mood: .happy, intensity: 0.5, reason: "cool, quiet and well fed")
        }
        return MoodReading(mood: .content, intensity: 0.3, reason: "nothing to complain about")
    }
}
