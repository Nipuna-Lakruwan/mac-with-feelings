import Foundation

/// Minimal client for a local Ollama server (https://ollama.com). Nothing leaves the machine.
public struct OllamaClient: Sendable {
    public var baseURL: URL
    public var timeout: TimeInterval

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!, timeout: TimeInterval = 45) {
        self.baseURL = baseURL
        self.timeout = timeout
    }

    public enum Failure: Error, Equatable {
        case badStatus(Int)
        case emptyReply
    }

    struct ChatRequest: Encodable {
        var model: String
        var messages: [ChatMessage]
        var stream = false
        var think = false
        /// Free the RAM soon after: this is an 8 GB laptop with feelings.
        var keep_alive = "3m"
        var options: Options

        struct Options: Encodable {
            var temperature: Double
            var num_predict: Int
            var top_p = 0.95
        }
    }

    struct ChatResponse: Decodable {
        struct Message: Decodable { var content: String }
        var message: Message
    }

    struct TagsResponse: Decodable {
        struct Model: Decodable { var name: String }
        var models: [Model]
    }

    public func chat(model: String, messages: [ChatMessage], temperature: Double = 1.0) async throws -> String {
        var req = URLRequest(url: baseURL.appending(path: "api/chat"), timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(
            ChatRequest(model: model, messages: messages, options: .init(temperature: temperature, num_predict: 90))
        )
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.badStatus(http.statusCode)
        }
        let text = try JSONDecoder().decode(ChatResponse.self, from: data).message.content
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.emptyReply }
        return text
    }

    /// Installed models that can chat (embedding-only models are left out).
    public func chatModels() async throws -> [String] {
        let req = URLRequest(url: baseURL.appending(path: "api/tags"), timeoutInterval: 3)
        let (data, _) = try await URLSession.shared.data(for: req)
        let names = try JSONDecoder().decode(TagsResponse.self, from: data).models.map(\.name)
        return Self.filterChatModels(names)
    }

    public static func filterChatModels(_ names: [String]) -> [String] {
        let embedHints = ["embed", "bge-", "minilm", "paraphrase", "e5-", "gte-", "nomic"]
        return names
            .filter { name in !embedHints.contains { name.lowercased().contains($0) } }
            .sorted()
    }

    /// Picks the configured model if installed, else a small instruct model, else anything.
    public static func pickModel(preferred: String, installed: [String]) -> String? {
        if installed.contains(preferred) { return preferred }
        let favourites = ["qwen3:4b-instruct", "llama3.2:3b", "gemma3", "qwen2.5:3b", "gemma2:2b", "phi"]
        for f in favourites {
            if let hit = installed.first(where: { $0.hasPrefix(f) }) { return hit }
        }
        return installed.first
    }
}
