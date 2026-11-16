import AVFoundation
import FeelingsCore
import Observation

/// Reads lines aloud and flaps the face's mouth on every word.
@Observable
@MainActor
final class Speaker: NSObject {
    private(set) var isSpeaking = false
    private(set) var mouthOpen = false

    @ObservationIgnored private let synth = AVSpeechSynthesizer()
    @ObservationIgnored private var closeMouth: Task<Void, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// English voices installed on this Mac, by display name.
    static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
    }

    static func voice(named name: String, personality: Personality) -> AVSpeechSynthesisVoice? {
        let voices = englishVoices()
        if !name.isEmpty, let v = voices.first(where: { $0.identifier == name }) { return v }
        for preferred in personality.preferredVoices {
            // Prefer the British/US variant when a voice exists in several.
            if let v = voices.first(where: { $0.name.hasPrefix(preferred) }) { return v }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    func say(_ text: String, voiceID: String, personality: Personality, rate: Float) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(named: voiceID, personality: personality)
        u.rate = rate
        u.pitchMultiplier = personality == .dramatic ? 1.1 : 1.0
        synth.speak(u)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    fileprivate func wordStarted() {
        mouthOpen = true
        closeMouth?.cancel()
        closeMouth = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            self?.mouthOpen = false
        }
    }

    fileprivate func setSpeaking(_ speaking: Bool) {
        isSpeaking = speaking
        if !speaking { mouthOpen = false }
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(true) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(false) }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(false) }
    }

    nonisolated func speechSynthesizer(
        _ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange, utterance u: AVSpeechUtterance
    ) {
        Task { @MainActor in self.wordStarted() }
    }
}
