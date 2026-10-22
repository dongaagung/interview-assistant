import Foundation
import Testing
@testable import InterviewAssistant

struct MessageRequestTests {
    @Test func hintRequestEncodesCachedSystemAndLowLatencySettings() throws {
        let hints = HintGenerator(client: ClaudeClient(apiKey: "k"), systemPrompt: "SYSTEM")
        let json = try encode(ClaudeClient(apiKey: "k").messageRequest(for: hints.request(question: "Q", context: "C")))
        #expect(json["model"] as? String == "claude-haiku-5-5")
        #expect(json["max_tokens"] as? Int == HintStyle.guide.maxTokens)
        let system = try #require((json["system"] as? [[String: Any]])?.first)
        #expect(system["text"] as? String == "SYSTEM")
        #expect((system["cache_control"] as? [String: String]) == ["type": "ephemeral"])
        #expect((json["thinking"] as? [String: String]) == ["type": "disabled"])
        #expect((json["output_config"] as? [String: String]) == ["effort": "low"])
        #expect(json["fallbacks"] == nil)
        #expect(json["stream"] == nil)
    }

    @Test func detectorSchemaKeepsCamelCaseKeys() throws {
        let detector = QuestionDetector(client: ClaudeClient(apiKey: "k"), systemPrompt: "S")
        let json = try encode(ClaudeClient(apiKey: "k").messageRequest(for: detector.request(turn: "T", context: "C")))
        let format = try #require((json["output_config"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["required"] as? [String] == ["is_question", "question"])
    }

    @Test func fallbacksAddBetaHeader() throws {
        var request = MessageRequest(model: ClaudeModel.sonnet, maxTokens: 10, system: [], messages: [])
        #expect(try ClaudeClient(apiKey: "k").urlRequest(for: request).value(forHTTPHeaderField: "anthropic-beta") == nil)
        request.fallbacks = "default"
        let urlRequest = try ClaudeClient(apiKey: "secret").urlRequest(for: request)
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "secret")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    }

    private func encode(_ request: MessageRequest) throws -> [String: Any] {
        let data = try ClaudeClient.encoder.encode(request)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

struct StreamEventTests {
    @Test func decodesTheEventsWeUse() {
        #expect(StreamEvent.decode(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}"#) == .text("Hi"))
        #expect(StreamEvent.decode(line: #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#) == .stopReason("end_turn"))
        #expect(StreamEvent.decode(line: #"data: {"type":"message_stop"}"#) == .messageStop)
        #expect(StreamEvent.decode(line: #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#) == .error(type: "overloaded_error", message: "Overloaded"))
    }

    @Test func ignoresEverythingElse() {
        #expect(StreamEvent.decode(line: "event: content_block_delta") == nil)
        #expect(StreamEvent.decode(line: #"data: {"type":"ping"}"#) == nil)
        #expect(StreamEvent.decode(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":""}}"#) == nil)
        #expect(StreamEvent.decode(line: "") == nil)
    }
}

/// Talks to a stubbed URLSession, never the real API.
@Suite(.serialized)
struct ClaudeClientHTTPTests {
    let client = ClaudeClient(apiKey: "test", session: StubURLProtocol.session)
    let request = MessageRequest(
        model: ClaudeModel.haiku, maxTokens: 10, system: [], messages: [.init(role: .user, content: "hi")])

    @Test func streamsTextDeltas() async throws {
        StubURLProtocol.respond(200, body: sse([
            #"{"type":"message_start","message":{"id":"m"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#,
            #"{"type":"ping"}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#,
            #"{"type":"message_stop"}"#,
        ]))
        var text = ""
        for try await delta in client.stream(request) { text += delta }
        #expect(text == "Hello world")
    }

    @Test func streamRefusalThrows() async {
        StubURLProtocol.respond(200, body: sse([#"{"type":"message_delta","delta":{"stop_reason":"refusal"}}"#]))
        await #expect(throws: ClaudeClient.Failure.refusal) {
            for try await _ in client.stream(request) {}
        }
    }

    @Test func httpErrorCarriesAPIMessage() async {
        StubURLProtocol.respond(401, body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#)
        await #expect(throws: ClaudeClient.Failure.http(status: 401, message: "invalid x-api-key")) {
            _ = try await client.send(request)
        }
    }

    @Test func sendReadsTextBlocksByType() async throws {
        StubURLProtocol.respond(200, body: #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"is_question\":true}"}],"stop_reason":"end_turn"}"#)
        #expect(try await client.send(request).text == #"{"is_question":true}"#)
    }

    private func sse(_ events: [String]) -> String {
        events.map { "event: x\ndata: \($0)\n\n" }.joined()
    }
}

final class StubURLProtocol: URLProtocol {
    // Tests using this run serialized, so one shared response is enough.
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }()

    static func respond(_ status: Int, body: String) {
        self.status = status
        self.body = Data(body.utf8)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
