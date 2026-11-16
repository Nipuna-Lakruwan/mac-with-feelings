import AppKit
import FeelingsCore
import SwiftUI

@main
struct MacWithFeelingsApp: App {
    @State private var brain: Brain

    init() {
        // Build helpers: render the app icon or a contact sheet of every mood, then quit.
        if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), i + 1 < CommandLine.arguments.count {
            Renderer.icon(to: CommandLine.arguments[i + 1])
            exit(0)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--render-moods"), i + 1 < CommandLine.arguments.count {
            Renderer.moodSheet(to: CommandLine.arguments[i + 1])
            exit(0)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--render-popover"), i + 1 < CommandLine.arguments.count {
            let brain = Brain(settings: Settings())
            brain.seedForScreenshot()
            Renderer.popover(brain, to: CommandLine.arguments[i + 1])
            exit(0)
        }

        // A menu-bar app: no Dock icon, even when started with `swift run`.
        NSApplication.shared.setActivationPolicy(.accessory)
        let brain = Brain(settings: Settings())
        brain.start()
        _brain = State(initialValue: brain)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(brain: brain)
        } label: {
            Text(brain.thinking ? "💭" : brain.reading.mood.emoji)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
enum Renderer {
    static func icon(to path: String) {
        let view = FaceView(mood: .happy, animated: false)
            .padding(70)
            .frame(width: 1024, height: 1024)
            .background(
                RoundedRectangle(cornerRadius: 220, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.82), Color(red: 1, green: 0.8, blue: 0.7)],
                                         startPoint: .top, endPoint: .bottom))
                    .padding(100)
            )
        save(view, size: CGSize(width: 1024, height: 1024), to: path)
    }

    static func moodSheet(to path: String) {
        let view = Grid(horizontalSpacing: 24, verticalSpacing: 20) {
            ForEach(Array(stride(from: 0, to: Mood.allCases.count, by: 3)), id: \.self) { start in
                GridRow {
                    ForEach(Mood.allCases[start..<min(start + 3, Mood.allCases.count)], id: \.self) { mood in
                        VStack(spacing: 6) {
                            FaceView(mood: mood, animated: false).frame(width: 200, height: 160)
                            Text("\(mood.emoji) \(mood.title)").font(.system(size: 18, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
        }
        .padding(30)
        .background(Color.white)
        save(view, size: CGSize(width: 760, height: 660), to: path)
    }

    static func popover(_ brain: Brain, to path: String) {
        let view = PopoverView(brain: brain).background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func save(_ view: some View, size: CGSize, to path: String) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
            exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
