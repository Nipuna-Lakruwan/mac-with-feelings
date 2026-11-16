import Foundation

public enum Personality: String, CaseIterable, Sendable, Codable {
    case dramatic
    case sarcastic
    case wholesome
    case aunty

    public var title: String {
        switch self {
        case .dramatic: "Drama queen"
        case .sarcastic: "Sarcastic"
        case .wholesome: "Wholesome"
        case .aunty: "Sri Lankan aunty"
        }
    }

    public var style: String {
        switch self {
        case .dramatic:
            "You are a theatrical drama queen. Every small problem is a tragedy of epic proportions. Gasp, sigh and exaggerate, like a soap opera star."
        case .sarcastic:
            "You are dry, deadpan and sarcastic, like a tired office worker who has seen it all. Understatement over shouting."
        case .wholesome:
            "You are sweet, gentle and supportive, like an anxious golden retriever. You worry about the human and cheer them on."
        case .aunty:
            "You are a loving but nosy Sri Lankan aunty. Speak in English, adding only one Sri Lankan word such as 'aney', 'ado' or 'putha'. Compare the human to a cousin who became a doctor, and worry about whether they have eaten rice."
        }
    }

    /// Preferred macOS voice names, best first. The first one that is installed wins.
    public var preferredVoices: [String] {
        switch self {
        case .dramatic: ["Daniel", "Reed", "Eddy"]
        case .sarcastic: ["Fred", "Ralph", "Albert"]
        case .wholesome: ["Flo", "Samantha", "Junior"]
        case .aunty: ["Grandma", "Kathy", "Karen"]
        }
    }
}

public struct ChatMessage: Sendable, Equatable, Codable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public enum PromptBuilder {
    public static func messages(
        vitals: Vitals,
        mood: MoodReading,
        event: FeelingEvent?,
        personality: Personality,
        recentLines: [String]
    ) -> [ChatMessage] {
        let system = """
        You are a MacBook that has feelings. You speak out loud, in the first person, as the computer itself, \
        to the human using you. \(personality.style)

        Rules:
        - Reply with ONE or TWO short sentences, at most 30 words in total. It will be read aloud.
        - Be funny and specific: use one or two of the real numbers you are given, not all of them.
        - React to what just happened, if anything happened.
        - Plain text only. No emojis, no hashtags, no quotation marks, no stage directions, no lists.
        - Tease the human about their habits, never about their looks, body, money or identity. Never be cruel.
        """

        var user = "How your body feels right now:\n"
        user += vitals.facts.map { "- \($0)" }.joined(separator: "\n")
        user += "\n\nYour mood: \(mood.mood.title.lowercased()), because \(mood.reason)."
        if let event { user += "\nWhat just happened: \(event.description)" }
        if !recentLines.isEmpty {
            user += "\n\nYou recently said the lines below. Say something different:\n"
            user += recentLines.suffix(3).map { "- \($0)" }.joined(separator: "\n")
        }
        user += "\n\nWhat do you say?"

        return [ChatMessage(role: "system", content: system), ChatMessage(role: "user", content: user)]
    }
}

public enum LineCleaner {
    public static let maxCharacters = 240

    /// Makes model output safe to read aloud: no thinking, quotes, emojis, stage directions or rambling.
    public static func clean(_ raw: String) -> String? {
        var s = raw
        // Reasoning models may think out loud first.
        if let end = s.range(of: "</think>") { s = String(s[end.upperBound...]) }
        s = s.replacingOccurrences(of: #"\*[^*]{1,60}\*"#, with: "", options: .regularExpression) // *sighs*
        s = s.replacingOccurrences(of: #"\([^)]{1,60}\)"#, with: "", options: .regularExpression) // (gasps)
        s = String(s.unicodeScalars.filter {
            !(($0.properties.isEmoji && $0.value > 0x7F)
                || $0.value == 0xFE0F || $0.value == 0x200D)
        })
        s = s.replacingOccurrences(of: "\n", with: " ")
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        // Removed emoji or directions can leave "A !" behind.
        s = s.replacingOccurrences(of: #"\s+([!?.,;])"#, with: "$1", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`*-: "))
        // Some models prefix the speaker: "MacBook: ..."
        if let colon = s.firstIndex(of: ":"), s.distance(from: s.startIndex, to: colon) <= 12,
           !s[..<colon].contains(" ") || s[..<colon].lowercased().contains("mac") {
            s = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard s.count >= 3 else { return nil }
        if s.count > maxCharacters {
            // Cut at the last sentence end that fits, else at a word.
            let head = String(s.prefix(maxCharacters))
            if let end = head.lastIndex(where: { ".!?".contains($0) }), head.distance(from: head.startIndex, to: end) > 40 {
                s = String(head[...end])
            } else if let space = head.lastIndex(of: " ") {
                s = String(head[..<space]) + "…"
            } else {
                s = head
            }
        }
        return s
    }
}
