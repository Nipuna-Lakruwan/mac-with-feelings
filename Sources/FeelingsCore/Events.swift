import Foundation

/// Something that just happened and is worth reacting to out loud.
public enum FeelingEvent: Sendable, Equatable {
    case pluggedIn
    case unplugged
    case userReturned(minutesAway: Int)
    case moodChanged(Mood)
    /// Went from upset back to calm.
    case relieved(from: Mood)
    case tabsMilestone(Int)
    /// The human clicked "How are you feeling?".
    case poked
    /// The app just started.
    case launched

    /// For the LLM prompt.
    public var description: String {
        switch self {
        case .launched: "You just discovered you can talk. This is the very first thing you ever say to the human."
        case .pluggedIn: "The human just plugged in your charger."
        case .unplugged: "The human just unplugged your charger."
        case let .userReturned(m): "The human just came back after being away for \(TimeWords.words(minutes: Double(m)))."
        case let .moodChanged(mood): "You just started feeling \(mood.title.lowercased())."
        case let .relieved(from): "You were \(from.title.lowercased()) but you feel fine again now."
        case let .tabsMilestone(n): "The human just went past \(n) open browser tabs."
        case .poked: "The human just asked how you are feeling."
        }
    }

    /// Events the human caused directly get an answer even during the cooldown.
    public var isUrgent: Bool {
        switch self {
        case .pluggedIn, .unplugged, .userReturned, .poked, .launched: true
        case .moodChanged, .relieved, .tabsMilestone: false
        }
    }
}

/// Compares each new sample with the previous one and reports at most one event.
public struct EventDetector: Sendable {
    public static let tabMilestones = [25, 50, 100, 200, 500]
    /// Away for this long counts as having left.
    public static let awaySeconds: Double = 15 * 60

    private var previous: Vitals?
    private var previousMood: Mood?
    private var longestIdle: Double = 0

    public init() {}

    public mutating func detect(_ v: Vitals, mood: MoodReading) -> FeelingEvent? {
        defer {
            previous = v
            previousMood = mood.mood
        }
        // Track the whole idle stretch, because the sample right after return shows ~0 seconds.
        let awayFor = longestIdle
        let wasAway = awayFor >= Self.awaySeconds
        if v.idleSeconds < 60 {
            longestIdle = 0
        } else {
            longestIdle = max(longestIdle, v.idleSeconds)
        }

        guard let prev = previous else { return nil }

        if wasAway && v.idleSeconds < 60 {
            return .userReturned(minutesAway: Int(awayFor / 60))
        }
        if let a = prev.battery, let b = v.battery, a.onAC != b.onAC {
            return b.onAC ? .pluggedIn : .unplugged
        }
        if let a = prev.browserTabs, let b = v.browserTabs,
           let crossed = Self.tabMilestones.last(where: { a < $0 && b >= $0 }) {
            return .tabsMilestone(crossed)
        }
        if let old = previousMood, old != mood.mood {
            if mood.mood.isUpset && mood.intensity >= 0.55 {
                return .moodChanged(mood.mood)
            }
            if old.isUpset && !mood.mood.isUpset {
                return .relieved(from: old)
            }
        }
        return nil
    }
}

public enum Chattiness: String, CaseIterable, Sendable, Codable {
    case quiet, normal, chatty

    public var title: String {
        switch self {
        case .quiet: "Quiet"
        case .normal: "Normal"
        case .chatty: "Chatty"
        }
    }

    /// Minimum gap between unprompted remarks.
    public var cooldown: TimeInterval {
        switch self {
        case .quiet: 25 * 60
        case .normal: 10 * 60
        case .chatty: 3 * 60
        }
    }

    /// With no event, the Mac still grumbles about a strong mood after this long.
    public var nagInterval: TimeInterval {
        switch self {
        case .quiet: 60 * 60
        case .normal: 25 * 60
        case .chatty: 8 * 60
        }
    }
}

/// Decides whether to say something now. Pure, so the rules can be tested.
public enum SpeakPolicy {
    /// Never talk more often than this, even for urgent events.
    public static let minimumGap: TimeInterval = 20

    public static func shouldSpeak(
        event: FeelingEvent?,
        mood: MoodReading,
        idleSeconds: Double,
        secondsSinceLastRemark: TimeInterval,
        chattiness: Chattiness
    ) -> Bool {
        if event == .poked || event == .launched { return true }
        if secondsSinceLastRemark < minimumGap { return false }
        // Nobody is at the keyboard to hear it.
        if idleSeconds > 120 { return false }
        if let event {
            return event.isUrgent || secondsSinceLastRemark >= chattiness.cooldown
        }
        return mood.mood.isUpset
            && mood.intensity >= 0.6
            && secondsSinceLastRemark >= chattiness.nagInterval
    }
}
