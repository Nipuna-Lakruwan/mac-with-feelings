@testable import FeelingsCore
import Testing

@Suite struct MoodEngineTests {
    @Test func calmMacIsNotUpset() {
        #expect(!MoodEngine.mood(for: .calm).mood.isUpset)
    }

    @Test func hotCPUMakesItSweat() {
        var v = Vitals.calm
        v.cpuPercent = 97
        #expect(MoodEngine.mood(for: v).mood == .overheated)
    }

    @Test func lowBatteryOnlyMattersOffTheCharger() {
        var v = Vitals.calm
        v.battery = Battery(percent: 8, onAC: false, charging: false)
        #expect(MoodEngine.mood(for: v).mood == .starving)
        v.battery = Battery(percent: 8, onAC: true, charging: true)
        #expect(MoodEngine.mood(for: v).mood != .starving)
    }

    @Test func tabsOverwhelmIt() {
        var v = Vitals.calm
        v.browserTabs = 64
        let r = MoodEngine.mood(for: v)
        #expect(r.mood == .overwhelmed)
        #expect(r.reason == "64 browser tabs open")
    }

    @Test func strongestFeelingWins() {
        var v = Vitals.calm
        v.browserTabs = 30 // 0.6
        v.thermal = .critical // 1.0
        v.hour = 3 // 0.85
        #expect(MoodEngine.mood(for: v).mood == .overheated)
        let moods = MoodEngine.readings(for: v).map(\.mood)
        #expect(moods == [.overheated, .sleepy, .overwhelmed])
    }

    @Test func lateNightIsSleepy() {
        var v = Vitals.calm
        v.hour = 2
        #expect(MoodEngine.mood(for: v).mood == .sleepy)
    }

    @Test func oneReadingPerMood() {
        var v = Vitals.calm
        v.cpuPercent = 90
        v.thermal = .serious
        let r = MoodEngine.readings(for: v)
        #expect(r.filter { $0.mood == .overheated }.count == 1)
        #expect(r.first?.intensity == 0.85)
    }

    @Test func weakComplaintsAreIgnored() {
        var v = Vitals.calm
        v.browserTabs = 12 // 0.35, above threshold
        #expect(MoodEngine.mood(for: v).mood == .overwhelmed)
        v.browserTabs = 11
        #expect(!MoodEngine.mood(for: v).mood.isUpset)
    }

    @Test func coolChargedDesktopIsHappy() {
        var v = Vitals.calm
        v.battery = nil
        #expect(MoodEngine.mood(for: v).mood == .happy)
    }
}

@Suite struct EventTests {
    @Test func firstSampleIsQuiet() {
        var d = EventDetector()
        #expect(d.detect(.calm, mood: MoodEngine.mood(for: .calm)) == nil)
    }

    @Test func plugAndUnplug() {
        var d = EventDetector()
        var v = Vitals.calm
        v.battery = Battery(percent: 50, onAC: false, charging: false)
        _ = d.detect(v, mood: MoodEngine.mood(for: v))
        v.battery = Battery(percent: 50, onAC: true, charging: true)
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == .pluggedIn)
        v.battery = Battery(percent: 50, onAC: false, charging: false)
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == .unplugged)
    }

    @Test func returningAfterLongIdle() {
        var d = EventDetector()
        var v = Vitals.calm
        _ = d.detect(v, mood: MoodEngine.mood(for: v))
        v.idleSeconds = 20 * 60
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == nil)
        v.idleSeconds = 3
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == .userReturned(minutesAway: 20))
        v.idleSeconds = 4
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == nil)
    }

    @Test func shortIdleIsNotAReturn() {
        var d = EventDetector()
        var v = Vitals.calm
        _ = d.detect(v, mood: MoodEngine.mood(for: v))
        v.idleSeconds = 5 * 60
        _ = d.detect(v, mood: MoodEngine.mood(for: v))
        v.idleSeconds = 1
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == nil)
    }

    @Test func tabMilestone() {
        var d = EventDetector()
        var v = Vitals.calm
        v.browserTabs = 48
        _ = d.detect(v, mood: MoodEngine.mood(for: v))
        v.browserTabs = 53
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == .tabsMilestone(50))
    }

    @Test func moodChangeAndRelief() {
        var d = EventDetector()
        var v = Vitals.calm
        _ = d.detect(v, mood: MoodEngine.mood(for: v))
        v.cpuPercent = 95
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == .moodChanged(.overheated))
        v.cpuPercent = 10
        #expect(d.detect(v, mood: MoodEngine.mood(for: v)) == .relieved(from: .overheated))
    }
}

@Suite struct SpeakPolicyTests {
    let upset = MoodReading(mood: .overheated, intensity: 0.8, reason: "")
    let calm = MoodReading(mood: .content, intensity: 0.3, reason: "")

    @Test func pokeAlwaysAnswers() {
        #expect(SpeakPolicy.shouldSpeak(event: .poked, mood: calm, idleSeconds: 999, secondsSinceLastRemark: 1, chattiness: .quiet))
    }

    @Test func neverTalksToAnEmptyRoom() {
        #expect(!SpeakPolicy.shouldSpeak(event: .pluggedIn, mood: calm, idleSeconds: 600, secondsSinceLastRemark: 9999, chattiness: .chatty))
    }

    @Test func urgentEventsSkipCooldown() {
        #expect(SpeakPolicy.shouldSpeak(event: .unplugged, mood: calm, idleSeconds: 1, secondsSinceLastRemark: 60, chattiness: .quiet))
        #expect(!SpeakPolicy.shouldSpeak(event: .unplugged, mood: calm, idleSeconds: 1, secondsSinceLastRemark: 5, chattiness: .quiet))
    }

    @Test func moodChangesRespectCooldown() {
        let e = FeelingEvent.moodChanged(.overheated)
        #expect(!SpeakPolicy.shouldSpeak(event: e, mood: upset, idleSeconds: 1, secondsSinceLastRemark: 60, chattiness: .normal))
        #expect(SpeakPolicy.shouldSpeak(event: e, mood: upset, idleSeconds: 1, secondsSinceLastRemark: 11 * 60, chattiness: .normal))
    }

    @Test func nagsOnlyWhenReallyUpset() {
        #expect(SpeakPolicy.shouldSpeak(event: nil, mood: upset, idleSeconds: 1, secondsSinceLastRemark: 30 * 60, chattiness: .normal))
        #expect(!SpeakPolicy.shouldSpeak(event: nil, mood: calm, idleSeconds: 1, secondsSinceLastRemark: 30 * 60, chattiness: .normal))
    }
}

@Suite struct LineTests {
    @Test func fillsPlaceholders() {
        var v = Vitals.calm
        v.browserTabs = 42
        v.cpuPercent = 88.4
        let s = LineBook.fill("{tabs} tabs at {cpu}, {time}", vitals: v)
        #expect(s == "42 tabs at 88%, 2 PM")
    }

    @Test func everyLineFillsCompletely() {
        var v = Vitals.calm
        v.battery = Battery(percent: 9, onAC: false, charging: false)
        let all = LineBook.moods.values.flatMap { $0 } + LineBook.events.values.flatMap { $0 }
        for template in all {
            #expect(!LineBook.fill(template, vitals: v, event: .userReturned(minutesAway: 30)).contains("{"), "\(template)")
        }
        #expect(Set(LineBook.moods.keys) == Set(Mood.allCases))
    }

    @Test func avoidsRepeats() {
        let r = MoodReading(mood: .starving, intensity: 1, reason: "")
        var v = Vitals.calm
        v.battery = Battery(percent: 9, onAC: false, charging: false)
        let pool = LineBook.moods[.starving]!.map { LineBook.fill($0, vitals: v) }
        let recent = Array(pool.dropLast())
        for _ in 0..<10 {
            #expect(LineBook.line(mood: r, event: nil, vitals: v, recent: recent) == pool.last)
        }
    }

    @Test func eventLinesWin() {
        let line = LineBook.line(mood: MoodEngine.mood(for: .calm), event: .pluggedIn, vitals: .calm)
        #expect(LineBook.events["pluggedIn"]!.contains(line))
    }

    @Test func timeWords() {
        #expect(TimeWords.words(minutes: 1) == "1 minute")
        #expect(TimeWords.words(minutes: 61) == "1 hour")
        #expect(TimeWords.words(minutes: 135) == "2 hours 15 minutes")
        #expect(Clock.words(hour: 0) == "12 AM")
        #expect(Clock.words(hour: 15) == "3 PM")
    }
}

@Suite struct CleanerTests {
    @Test func stripsThinkingQuotesAndEmoji() {
        let raw = "<think>hmm</think>\n\"Ugh, 47 tabs?! 😩 I'm melting.\""
        #expect(LineCleaner.clean(raw) == "Ugh, 47 tabs?! I'm melting.")
    }

    @Test func stripsStageDirectionsAndSpeaker() {
        #expect(LineCleaner.clean("MacBook: *sighs dramatically* Fine. (gasps) I'm fine.") == "Fine. I'm fine.")
    }

    @Test func closesGapsLeftByRemovedEmoji() {
        #expect(LineCleaner.clean("A tragedy! A 💥! I'm fine 🙂.") == "A tragedy! A! I'm fine.")
    }

    @Test func keepsNumbersAndHashes() {
        #expect(LineCleaner.clean("I'm at 9% and 3 hours, #1 fan") == "I'm at 9% and 3 hours, #1 fan")
    }

    @Test func trimsRambling() {
        let long = String(repeating: "This is a sentence that goes on. ", count: 20)
        let out = LineCleaner.clean(long)!
        #expect(out.count <= LineCleaner.maxCharacters)
        #expect(out.hasSuffix("."))
    }

    @Test func rejectsEmpty() {
        #expect(LineCleaner.clean("<think>only thoughts</think>   ") == nil)
    }
}

@Suite struct PromptTests {
    @Test func promptCarriesFactsEventAndHistory() {
        var v = Vitals.calm
        v.browserTabs = 77
        let msgs = PromptBuilder.messages(
            vitals: v, mood: MoodEngine.mood(for: v), event: .pluggedIn,
            personality: .aunty, recentLines: ["old line"]
        )
        #expect(msgs.count == 2)
        #expect(msgs[0].role == "system" && msgs[0].content.contains("aunty"))
        #expect(msgs[1].content.contains("open browser tabs: 77"))
        #expect(msgs[1].content.contains("charger"))
        #expect(msgs[1].content.contains("- old line"))
    }

    @Test func modelPicking() {
        let installed = OllamaClient.filterChatModels(["bge-m3:latest", "nomic-embed-text:latest", "llama3.2:3b", "qwen3:4b-instruct-2507-q4_K_M"])
        #expect(installed == ["llama3.2:3b", "qwen3:4b-instruct-2507-q4_K_M"])
        #expect(OllamaClient.pickModel(preferred: "missing:1b", installed: installed) == "qwen3:4b-instruct-2507-q4_K_M")
        #expect(OllamaClient.pickModel(preferred: "llama3.2:3b", installed: installed) == "llama3.2:3b")
        #expect(OllamaClient.pickModel(preferred: "x", installed: []) == nil)
    }
}
