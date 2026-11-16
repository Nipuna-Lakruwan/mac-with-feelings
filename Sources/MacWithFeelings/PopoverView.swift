import FeelingsCore
import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @Bindable var brain: Brain
    @State private var showSettings = false

    private var settings: Settings { brain.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            speech
            actions
            Divider()
            if showSettings {
                SettingsPane(brain: brain)
            } else {
                VitalsGrid(vitals: brain.vitals)
                if brain.diary.count > 1 { diary }
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 14) {
            FaceView(mood: brain.reading.mood, mouthOpen: brain.speaker.mouthOpen)
                .frame(width: 96, height: 77)
            VStack(alignment: .leading, spacing: 3) {
                Text(brain.reading.mood.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text(brain.reading.reason.prefix(1).capitalized + brain.reading.reason.dropFirst())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var speech: some View {
        Group {
            if brain.thinking {
                ThinkingDots()
            } else if let last = brain.diary.first {
                Text(last.text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text("Clearing my throat…").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .padding(12)
        .background(brain.reading.mood.screen.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var actions: some View {
        HStack {
            Button {
                brain.poke()
            } label: {
                Label("How are you feeling?", systemImage: "bubble.left.and.text.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(brain.thinking)
            .keyboardShortcut(.defaultAction)

            Button {
                settings.speakAloud.toggle()
                if !settings.speakAloud { brain.speaker.stop() }
            } label: {
                Image(systemName: settings.speakAloud ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .frame(width: 20)
            }
            .controlSize(.large)
            .help(settings.speakAloud ? "Mute" : "Speak aloud")
        }
    }

    private var diary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Earlier").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(brain.diary.dropFirst().prefix(3)) { remark in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(remark.mood.emoji).font(.caption)
                    Text(remark.text).font(.caption).lineLimit(2)
                    Spacer(minLength: 4)
                    Text(remark.date, style: .time).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(showSettings ? "Done" : "Settings") { showSettings.toggle() }
            Spacer()
            Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .buttonStyle(.borderless)
    }

    private var statusText: String {
        guard settings.useLLM else { return "Built-in lines" }
        switch brain.llmStatus {
        case .checking: return "Looking for Ollama…"
        case let .ready(model): return "Brain: \(model.split(separator: ":").first ?? "")"
        case .noModels: return "No Ollama models, using built-in lines"
        case .offline: return "Ollama offline, using built-in lines"
        }
    }
}

private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { context in
            let n = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 4
            Text("Thinking about my feelings" + String(repeating: ".", count: n))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct VitalsGrid: View {
    let vitals: Vitals

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
            row("cpu", "CPU", "\(Int(vitals.cpuPercent.rounded()))%", vitals.cpuPercent / 100)
            row("thermometer.medium", "Heat", vitals.thermal.label.capitalized, Double(vitals.thermal.rawValue + 1) / 4)
            if let b = vitals.battery {
                row(b.onAC ? "battery.100percent.bolt" : "battery.50percent", "Battery",
                    "\(b.percent)%\(b.onAC ? " ⚡︎" : "")", Double(b.percent) / 100, invert: true)
            }
            row("memorychip", "Memory", "\(Int(vitals.memoryUsedPercent.rounded()))%", vitals.memoryUsedPercent / 100)
            if let t = vitals.browserTabs {
                row("square.on.square", "Tabs", "\(t)", min(1, Double(t) / 50))
            }
            row("figure.walk", "No break", TimeWords.words(minutes: vitals.workMinutes), min(1, vitals.workMinutes / 180))
        }
    }

    @ViewBuilder
    private func row(_ icon: String, _ name: String, _ value: String, _ level: Double, invert: Bool = false) -> some View {
        let bad = invert ? 1 - level : level
        GridRow {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 18)
            Text(name).font(.callout)
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule()
                            .fill(bad > 0.8 ? Color.red : bad > 0.55 ? Color.orange : Color.green)
                            .frame(width: max(6, g.size.width * max(0, min(1, level))))
                    }
                }
                .frame(width: 120, height: 6)
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
        }
    }
}

private struct SettingsPane: View {
    @Bindable var brain: Brain
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var s = brain.settings
        Form {
            Picker("Personality", selection: $s.personality) {
                ForEach(Personality.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Chattiness", selection: $s.chattiness) {
                ForEach(Chattiness.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Voice", selection: $s.voiceID) {
                Text("Match personality").tag("")
                ForEach(Speaker.englishVoices(), id: \.identifier) { v in
                    Text("\(v.name) (\(v.language))").tag(v.identifier)
                }
            }
            Slider(value: $s.speechRate, in: 0.35...0.6) { Text("Speed") }
            Toggle("Speech bubbles", isOn: $s.showBubbles)
            Toggle("Count browser tabs", isOn: $s.countTabs)
            Toggle("Use local LLM (Ollama)", isOn: $s.useLLM)
            if s.useLLM && !brain.installedModels.isEmpty {
                Picker("Model", selection: $s.model) {
                    ForEach(brain.installedModels, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: s.model) { Task { await brain.refreshModels() } }
            }
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
        }
        .formStyle(.columns)
        .controlSize(.small)
    }
}
