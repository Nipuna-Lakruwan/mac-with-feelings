import FeelingsCore
import Foundation
import Observation

/// User preferences, saved to UserDefaults as they change.
@Observable
@MainActor
final class Settings {
    @ObservationIgnored private let defaults: UserDefaults

    var personality: Personality { didSet { defaults.set(personality.rawValue, forKey: "personality") } }
    var chattiness: Chattiness { didSet { defaults.set(chattiness.rawValue, forKey: "chattiness") } }
    var speakAloud: Bool { didSet { defaults.set(speakAloud, forKey: "speakAloud") } }
    /// An AVSpeechSynthesisVoice identifier, or "" to pick one that suits the personality.
    var voiceID: String { didSet { defaults.set(voiceID, forKey: "voiceID") } }
    var speechRate: Float { didSet { defaults.set(speechRate, forKey: "speechRate") } }
    var showBubbles: Bool { didSet { defaults.set(showBubbles, forKey: "showBubbles") } }
    var countTabs: Bool { didSet { defaults.set(countTabs, forKey: "countTabs") } }
    var useLLM: Bool { didSet { defaults.set(useLLM, forKey: "useLLM") } }
    var model: String { didSet { defaults.set(model, forKey: "model") } }

    static let defaultModel = "qwen3:4b-instruct-2507-q4_K_M"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        personality = defaults.string(forKey: "personality").flatMap(Personality.init) ?? .dramatic
        chattiness = defaults.string(forKey: "chattiness").flatMap(Chattiness.init) ?? .normal
        speakAloud = defaults.object(forKey: "speakAloud") as? Bool ?? true
        voiceID = defaults.string(forKey: "voiceID") ?? ""
        speechRate = defaults.object(forKey: "speechRate") as? Float ?? 0.5
        showBubbles = defaults.object(forKey: "showBubbles") as? Bool ?? true
        countTabs = defaults.object(forKey: "countTabs") as? Bool ?? true
        useLLM = defaults.object(forKey: "useLLM") as? Bool ?? true
        model = defaults.string(forKey: "model") ?? Self.defaultModel
    }
}
