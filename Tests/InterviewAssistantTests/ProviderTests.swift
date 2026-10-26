import Foundation
import Testing
@testable import InterviewAssistant

struct OpenAICompatibleRequestTests {
    let client = OpenAICompatibleClient(
        providerName: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
        apiKey: "gsk_test", fastModel: "fast-model", smartModel: "smart-model")

    func json(_ body: OpenAICompatibleClient.Body) throws -> [String: Any] {
        let data = try ClaudeClient.encoder.encode(body)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func hintUsesTheFastModelWithSystemFirst() throws {
        let request = HintGenerator(client: client, systemPrompt: "SYSTEM").request(question: "Q", context: "C")
        let body = try json(client.body(for: request, stream: true, json: nil))
        #expect(body["model"] as? String == "fast-model")
        #expect(body["stream"] as? Bool == true)
        #expect(body["max_tokens"] as? Int == HintStyle.guide.maxTokens)
        #expect(body["max_completion_tokens"] == nil)
        #expect(body["response_format"] == nil)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(messages[0]["content"] == "SYSTEM")
    }

    @Test func practiceUsesTheSmartModel() throws {
        let request = PracticeInterviewer(client: client, systemPrompt: "S").request([.init(role: .user, content: "hi")])
        #expect(try json(client.body(for: request, stream: true, json: nil))["model"] as? String == "smart-model")
    }

    @Test func openAIGetsMaxCompletionTokens() throws {
        var openAI = client
        openAI.usesMaxCompletionTokens = true
        let body = try json(openAI.body(for: HintGenerator(client: openAI, systemPrompt: "S").request(question: "Q", context: "C"), stream: false, json: nil))
        #expect(body["max_completion_tokens"] as? Int == HintStyle.guide.maxTokens)
        #expect(body["max_tokens"] == nil)
    }

    @Test func thinkingIsTurnedOffOnlyForLatencyBoundRequests() throws {
        var deepSeek = client
        deepSeek.disablesThinkingForSpeed = true
        let hint = HintGenerator(client: deepSeek, systemPrompt: "S").request(question: "Q", context: "C")
        let detection = QuestionDetector(client: deepSeek, systemPrompt: "S").request(turn: "T", context: "C")
        let practice = PracticeInterviewer(client: deepSeek, systemPrompt: "S").request([.init(role: .user, content: "hi")])
        #expect((try json(deepSeek.body(for: hint, stream: true, json: nil))["thinking"] as? [String: String]) == ["type": "disabled"])
        #expect((try json(deepSeek.body(for: detection, stream: false, json: .object))["thinking"] as? [String: String]) == ["type": "disabled"])
        #expect(try json(deepSeek.body(for: practice, stream: true, json: nil))["thinking"] == nil)
        #expect(try json(client.body(for: hint, stream: true, json: nil))["thinking"] == nil, "other servers may reject the field")
    }

    @Test func jsonModesStepDownFromSchemaToInstructions() throws {
        let request = QuestionDetector(client: client, systemPrompt: "S").request(turn: "T", context: "C")
        let schema = try json(client.body(for: request, stream: false, json: .schema))
        let format = try #require(schema["response_format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(((format["json_schema"] as? [String: Any])?["strict"]) as? Bool == true)

        let object = try json(client.body(for: request, stream: false, json: .object))
        #expect((object["response_format"] as? [String: String]) == ["type": "json_object"])
        let objectSystem = try #require((object["messages"] as? [[String: String]])?.first?["content"])
        #expect(objectSystem.contains("is_question"), "the schema is spelled out when the server can't enforce it")

        let instructions = try json(client.body(for: request, stream: false, json: .instructions))
        #expect(instructions["response_format"] == nil)
    }

    @Test func streamLinesDecode() {
        #expect(OpenAICompatibleClient.decode(line: #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#) == .text("Hel"))
        #expect(OpenAICompatibleClient.decode(line: #"data:{"choices":[{"delta":{"role":"assistant"}}]}"#) == nil)
        #expect(OpenAICompatibleClient.decode(line: "data: [DONE]") == .done)
        #expect(OpenAICompatibleClient.decode(line: #"data: {"error":{"message":"Rate limited"}}"#) == .error("Rate limited"))
        #expect(OpenAICompatibleClient.decode(line: ": keep-alive") == nil)
    }

    @Test func jsonRepliesAreFoundInsideFences() {
        #expect(JSONReply.object(in: "Sure!\n```json\n{\"is_question\": true}\n```") == "{\"is_question\": true}")
        #expect(JSONReply.object(in: "no json") == "no json")
    }
}

/// Talks to a stubbed URLSession, never a real server.
@Suite(.serialized)
struct OpenAICompatibleHTTPTests {
    let client = OpenAICompatibleClient(
        providerName: "Groq", baseURL: URL(string: "https://api.groq.com/openai/v1")!,
        apiKey: "gsk_test", fastModel: "fast", smartModel: "smart", session: ProviderStub.session)

    @Test func streamsTextAndSendsTheKey() async throws {
        ProviderStub.respond([(200, """
            data: {"choices":[{"delta":{"role":"assistant"}}]}

            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[{"delta":{"content":" world"}}]}

            data: [DONE]

            """)])
        var text = ""
        for try await delta in client.stream(HintGenerator(client: client, systemPrompt: "S").request(question: "Q", context: "C")) {
            text += delta
        }
        #expect(text == "Hello world")
        #expect(ProviderStub.requests.first?.value(forHTTPHeaderField: "authorization") == "Bearer gsk_test")
        #expect(ProviderStub.requests.first?.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
    }

    @Test func detectorFallsBackWhenTheServerRefusesJSONSchemas() async throws {
        ProviderStub.respond([
            (400, #"{"error":{"message":"response_format json_schema is not supported"}}"#),
            (200, #"{"choices":[{"message":{"content":"```json\n{\"is_question\": true, \"question\": \"Why Kafka?\"}\n```"}}]}"#),
        ])
        let question = try await QuestionDetector(client: client, systemPrompt: "S").detect(turn: "so why kafka", context: "")
        #expect(question == "Why Kafka?")
        let formats = ProviderStub.bodies.map { body in
            ((try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["response_format"] as? [String: Any])?["type"] as? String
        }
        #expect(formats == ["json_schema", "json_object"])
    }

    @Test func detectorSkipsJSONSchemasWhereTheyAreKnownRefused() async throws {
        var deepSeek = client
        deepSeek.supportsJSONSchema = false
        ProviderStub.respond([(200, #"{"choices":[{"message":{"content":"{\"is_question\": true, \"question\": \"Why Kafka?\"}"}}]}"#)])
        let question = try await QuestionDetector(client: deepSeek, systemPrompt: "S").detect(turn: "so why kafka", context: "")
        #expect(question == "Why Kafka?")
        let formats = ProviderStub.bodies.map { body in
            ((try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["response_format"] as? [String: Any])?["type"] as? String
        }
        #expect(formats == ["json_object"])
    }

    @Test func rejectedKeyExplainsWhereToFixIt() async {
        ProviderStub.respond([(401, #"{"error":{"message":"Invalid API Key"}}"#)])
        do {
            _ = try await client.complete(PracticeInterviewer(client: client, systemPrompt: "S").request([.init(role: .user, content: "hi")]))
            Issue.record("expected an error")
        } catch {
            #expect(error.localizedDescription == "Groq rejected the API key. Check it in Setup.")
        }
    }

    @Test func listsModels() async throws {
        ProviderStub.respond([(200, #"{"data":[{"id":"model-b"},{"id":"model-a"}]}"#)])
        let models = try await OpenAICompatibleClient.listModels(
            baseURL: URL(string: "http://localhost:11434/v1")!, apiKey: nil, session: ProviderStub.session)
        #expect(models == ["model-a", "model-b"])
        #expect(ProviderStub.requests.first?.url?.absoluteString == "http://localhost:11434/v1/models")
        #expect(ProviderStub.requests.first?.value(forHTTPHeaderField: "authorization") == nil)
    }
}

/// Separate from the Claude tests' stub so the two serialized suites can
/// run side by side.
final class ProviderStub: URLProtocol {
    nonisolated(unsafe) private static var responses: [(Int, Data)] = []
    nonisolated(unsafe) private(set) static var requests: [URLRequest] = []
    nonisolated(unsafe) private(set) static var bodies: [Data] = []

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProviderStub.self]
        return URLSession(configuration: configuration)
    }()

    /// Responses in order; the last one repeats.
    static func respond(_ responses: [(Int, String)]) {
        self.responses = responses.map { ($0.0, Data($0.1.utf8)) }
        requests = []
        bodies = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(of: request))
        let (status, body) = Self.responses.count > 1 ? Self.responses.removeFirst() : Self.responses[0]
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream, not `httpBody`.
    private static func readBody(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@MainActor
struct ProviderSettingsTests {
    func store() -> AppStore {
        AppStore(
            files: JSONFileStore(directory: FileManager.default.temporaryDirectory.appending(path: "ai-\(UUID().uuidString)")),
            keychainPrefix: "test-\(UUID().uuidString)-")
    }

    @Test func olderSettingsKeepClaude() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"localeIdentifier":"id-ID"}"#.utf8))
        #expect(settings.aiProvider == .anthropic)
        #expect(settings.models(for: .groq).baseURL == "https://api.groq.com/openai/v1")
    }

    @Test func providerModelsSaveUnderReadableKeys() throws {
        var settings = AppSettings()
        settings.providerModels[.groq] = ProviderModels(baseURL: "https://x/v1", fastModel: "f", smartModel: "s")
        let text = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        #expect(text.contains(#""groq":"#))
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data(text.utf8)).providerModels == settings.providerModels)
    }

    @Test func claudeNeedsItsKey() {
        let store = store()
        #expect(store.aiProblem == "Add your Claude API key in Setup.")
        #expect(store.aiClient() == nil)
    }

    @Test func ollamaNeedsModelsButNoKey() {
        let store = store()
        store.settings.aiProvider = .ollama
        #expect(store.aiProblem == "Choose the Ollama models in Setup.")
        store.settings.providerModels[.ollama] = ProviderModels(
            baseURL: AIProvider.ollama.defaultBaseURL, fastModel: "small", smartModel: "large")
        #expect(store.isAIReady)
        #expect(store.aiClient()?.providerName == "Ollama")
    }

    @Test func deepSeekAnswersHintsWithoutThinkingFirst() throws {
        let store = store()
        store.settings.aiProvider = .deepSeek
        store.setAPIKey("sk-test", for: .deepSeek)
        store.settings.providerModels[.deepSeek] = ProviderModels(
            baseURL: AIProvider.deepSeek.defaultBaseURL, fastModel: "deepseek-flash", smartModel: "deepseek-flash")
        let client = try #require(store.aiClient() as? OpenAICompatibleClient)
        #expect(client.disablesThinkingForSpeed)
        #expect(!client.supportsJSONSchema)
        store.setAPIKey("", for: .deepSeek)
    }

    @Test func customServerNeedsAnAddress() {
        let store = store()
        store.settings.aiProvider = .custom
        #expect(store.aiProblem == "Enter the server address for your server in Setup.")
    }
}

struct ClaudePurposeTests {
    @Test(arguments: [
        (LLMRequest.Purpose.practice, "claude-sonnet-5-5", "between_tools", "low"),
        (.feedback, "claude-sonnet-5-5", "adaptive", "medium"),
        (.hint, "claude-haiku-5-5", "disabled", "low"),
    ])
    func eachPurposeKeepsItsClaudeSettings(purpose: LLMRequest.Purpose, model: String, thinking: String, effort: String) throws {
        let request = LLMRequest(purpose: purpose, system: "S", messages: [.init(role: .user, content: "hi")], maxTokens: 10)
        let message = ClaudeClient(apiKey: "k").messageRequest(for: request)
        #expect(message.model == model)
        #expect(message.thinking?.type == thinking)
        #expect(message.outputConfig?.effort == effort)
        #expect(message.fallbacks == (purpose.needsSpeed ? nil : "default"))
    }
}
