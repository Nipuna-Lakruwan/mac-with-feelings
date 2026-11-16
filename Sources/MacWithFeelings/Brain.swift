import FeelingsCore
import Foundation
import Observation
import os

let log = Logger(subsystem: "io.github.nipuna-lakruwan.MacWithFeelings", category: "brain")

struct Remark: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let mood: Mood
    let date: Date
    /// False when the built-in line book answered instead of the LLM.
    let fromLLM: Bool
}

enum LLMStatus: Equatable {
    case checking
    case ready(String)
    case noModels
    case offline
}

/// Samples the Mac every few seconds, works out how it feels, and decides when to say so.
@Observable
@MainActor
final class Brain {
    let settings: Settings
    let speaker = Speaker()

    private(set) var vitals = Vitals.calm
    private(set) var reading = MoodEngine.mood(for: .calm)
    private(set) var diary: [Remark] = []
    private(set) var thinking = false
    private(set) var llmStatus: LLMStatus = .checking
    private(set) var installedModels: [String] = []

    @ObservationIgnored private let sampler = VitalsSampler()
    @ObservationIgnored private var detector = EventDetector()
    @ObservationIgnored private var lastRemark = Date.distantPast
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let client = OllamaClient()
    @ObservationIgnored private let bubble = BubbleController()

    static let sampleInterval: Duration = .seconds(10)

    init(settings: Settings) {
        self.settings = settings
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            // The first CPU reading needs a previous one to compare with.
            _ = self?.sampler.sample(countTabs: self?.settings.countTabs ?? false)
            await self?.refreshModels()
            try? await Task.sleep(for: .seconds(2))
            self?.tick(initial: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sampleInterval)
                self?.tick(initial: false)
            }
        }
    }

    /// For `--render-popover`: real vitals plus a line from the line book, without the timer.
    func seedForScreenshot() {
        _ = sampler.sample(countTabs: settings.countTabs)
        Thread.sleep(forTimeInterval: 1)
        vitals = sampler.sample(countTabs: settings.countTabs)
        reading = MoodEngine.mood(for: vitals)
        let line = LineBook.line(mood: reading, event: nil, vitals: vitals)
        diary = [Remark(text: line, mood: reading.mood, date: Date(), fromLLM: false)]
        llmStatus = .offline
    }

    /// "How are you feeling?"
    func poke() {
        Task { await remark(.poked, showBubble: false) }
    }

    func refreshModels() async {
        llmStatus = .checking
        do {
            installedModels = try await client.chatModels()
            if let model = OllamaClient.pickModel(preferred: settings.model, installed: installedModels) {
                llmStatus = .ready(model)
            } else {
                llmStatus = .noModels
            }
        } catch {
            installedModels = []
            llmStatus = .offline
        }
    }

    private func tick(initial: Bool) {
        vitals = sampler.sample(countTabs: settings.countTabs)
        reading = MoodEngine.mood(for: vitals)
        let detected = detector.detect(vitals, mood: reading)
        let event = initial ? .launched : detected
        guard !thinking else { return }
        let speak = SpeakPolicy.shouldSpeak(
            event: event,
            mood: reading,
            idleSeconds: vitals.idleSeconds,
            secondsSinceLastRemark: Date().timeIntervalSince(lastRemark),
            chattiness: settings.chattiness
        )
        if speak {
            Task { await remark(event, showBubble: true) }
        }
    }

    private func remark(_ event: FeelingEvent?, showBubble: Bool) async {
        guard !thinking else { return }
        thinking = true
        lastRemark = Date()
        if event == .poked {
            // Read fresh numbers instead of ones up to 10 seconds old.
            vitals = sampler.sample(countTabs: settings.countTabs)
            reading = MoodEngine.mood(for: vitals)
        }
        let recent = diary.prefix(4).map(\.text)

        var text: String?
        if settings.useLLM {
            if case .ready = llmStatus {} else { await refreshModels() }
            if case let .ready(model) = llmStatus {
                let messages = PromptBuilder.messages(
                    vitals: vitals, mood: reading, event: event,
                    personality: settings.personality, recentLines: Array(recent)
                )
                do {
                    text = LineCleaner.clean(try await client.chat(model: model, messages: messages))
                } catch {
                    log.error("LLM failed: \(error.localizedDescription, privacy: .public)")
                    llmStatus = .offline
                }
            }
        }
        let fromLLM = text != nil
        log.notice("mood=\(self.reading.mood.rawValue, privacy: .public) event=\(String(describing: event), privacy: .public) llm=\(fromLLM) line=\(text ?? "(line book)", privacy: .public)")
        let line = text ?? LineBook.line(mood: reading, event: event, vitals: vitals, recent: Array(recent))

        diary.insert(Remark(text: line, mood: reading.mood, date: Date(), fromLLM: fromLLM), at: 0)
        if diary.count > 30 { diary.removeLast(diary.count - 30) }
        thinking = false
        lastRemark = Date()

        if settings.speakAloud {
            speaker.say(line, voiceID: settings.voiceID, personality: settings.personality, rate: settings.speechRate)
        }
        if showBubble && settings.showBubbles {
            bubble.show(line, mood: reading.mood)
        }
    }
}
