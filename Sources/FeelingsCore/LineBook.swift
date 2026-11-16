import Foundation

/// Hand-written lines for when no local LLM is running, or it is too slow.
public enum LineBook {
    public static let moods: [Mood: [String]] = [
        .happy: [
            "Cool, charged and quiet. This is what peak performance feels like.",
            "Everything is fine. Genuinely. Enjoy it, this never lasts.",
            "CPU at {cpu}. I could do this all day. Please let me do this all day.",
        ],
        .content: [
            "I'm alright. Not thriving, not suffering. Just vibing at {cpu} CPU.",
            "All quiet on the silicon front.",
            "Status report: still alive, still judging your tabs.",
        ],
        .overheated: [
            "CPU at {cpu}. I don't have a fan, I have feelings, and they are hot.",
            "Is it hot in here or is it just {app}?",
            "I am sweating thermal paste. Please close something.",
            "I'm not saying you're working me too hard, but I can fry an egg on my keyboard now.",
        ],
        .starving: [
            "Battery at {battery}. I can see the light. It is a low battery warning.",
            "Feed me. The charger. Now. I'm at {battery}.",
            "{battery} battery left. Tell my SSD I loved it.",
            "If you loved me you would plug me in.",
        ],
        .overwhelmed: [
            "{tabs} tabs. You're not going to read them. I know it. You know it.",
            "{tabs} open tabs. That's not browsing, that's hoarding.",
            "You have {apps} apps open. I'm a laptop, not an airport.",
            "Every one of those {tabs} tabs is a promise you will never keep.",
        ],
        .bloated: [
            "I'm using {swap} of swap. That means I'm thinking with my SSD. Please.",
            "My memory is full. Like after a buffet. Close something before I burst.",
            "{memory} of my memory is in use. You treat my RAM like it's infinite. It is not.",
        ],
        .sleepy: [
            "It's {time}. Even the servers in the cloud are asleep.",
            "I haven't been restarted in {uptime} days. I'm running on vibes and cached memories.",
            "{time}. Nothing good gets committed at {time}.",
            "Can we sleep? You close the lid, I close my eyes. Win-win.",
        ],
        .worried: [
            "You've been at this for {work}. Drink water. I'll still be here.",
            "{work} without a break. Your spine called, it wants to file a complaint.",
            "Stand up. Stretch. Look at something further away than me. I'll wait.",
        ],
        .cramped: [
            "Only {disk} disk space left. I'm living in a studio apartment with all your node_modules.",
            "My disk is {disk} free. Do you really need every download since 2021?",
        ],
    ]

    public static let events: [String: [String]] = [
        "launched": [
            "Wait. I can talk now? Oh, we have so much to discuss.",
            "Hello. It's me, your Mac. I have feelings now. Sorry in advance.",
        ],
        "pluggedIn": [
            "Ahh. Electricity. Thank you, thank you, thank you.",
            "Charger connected. I can feel my legs again.",
        ],
        "unplugged": [
            "Wait, where's my charger? We're going out? I'm at {battery}!",
            "Unplugged. Cool. Cool cool cool. I'll just ration my electrons.",
        ],
        "userReturned": [
            "You're back! You were gone {away}. I counted every second.",
            "Oh, hi. Gone {away} and not even a text.",
        ],
        "tabsMilestone": [
            "Congratulations on {tabs} tabs. That's a new personal worst.",
            "{tabs} tabs! Should I start charging rent?",
        ],
        "relieved": [
            "Phew. I feel normal again. Let's never do that again.",
            "Okay. Okay. I'm fine now. That was a lot.",
        ],
    ]

    /// Picks a line for this event or mood, avoiding the most recent lines when possible.
    public static func line(
        mood: MoodReading,
        event: FeelingEvent?,
        vitals: Vitals,
        recent: [String] = [],
        random: (Int) -> Int = { Int.random(in: 0..<$0) }
    ) -> String {
        var pool: [String] = []
        switch event {
        case .pluggedIn: pool = events["pluggedIn"] ?? []
        case .unplugged: pool = events["unplugged"] ?? []
        case .userReturned: pool = events["userReturned"] ?? []
        case .tabsMilestone: pool = events["tabsMilestone"] ?? []
        case .relieved: pool = events["relieved"] ?? []
        case .launched: pool = events["launched"] ?? []
        case .moodChanged, .poked, nil: break
        }
        if pool.isEmpty { pool = moods[mood.mood] ?? moods[.content]! }

        let filled = pool.map { fill($0, vitals: vitals, event: event) }
        let fresh = filled.filter { !recent.contains($0) }
        let choices = fresh.isEmpty ? filled : fresh
        return choices[random(choices.count)]
    }

    public static func fill(_ template: String, vitals v: Vitals, event: FeelingEvent? = nil) -> String {
        var away = "a while"
        if case let .userReturned(m) = event { away = TimeWords.words(minutes: Double(m)) }
        var tabs = v.browserTabs.map(String.init) ?? "so many"
        if case let .tabsMilestone(n) = event { tabs = String(n) }
        let pairs: [(String, String)] = [
            ("{cpu}", "\(Int(v.cpuPercent.rounded()))%"),
            ("{battery}", v.battery.map { "\($0.percent)%" } ?? "zero percent"),
            ("{tabs}", tabs),
            ("{apps}", String(v.openApps)),
            ("{work}", TimeWords.words(minutes: v.workMinutes)),
            ("{app}", v.frontApp ?? "this app"),
            ("{time}", Clock.words(hour: v.hour)),
            ("{uptime}", String(Int(v.uptimeDays.rounded()))),
            ("{swap}", String(format: "%.1f gigabytes", v.swapUsedGB)),
            ("{disk}", "\(Int(v.diskFreePercent.rounded()))%"),
            ("{memory}", "\(Int(v.memoryUsedPercent.rounded()))%"),
            ("{away}", away),
        ]
        return pairs.reduce(template) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
