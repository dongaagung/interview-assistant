# Interview Assistant (macOS, SwiftUI)

Native macOS app (Swift 6, SwiftUI). Captures meeting-app audio
(interviewer) and mic (user) separately, shows live captions, detects
interviewer questions, streams answer hints from the Claude API.
Practice Mode: AI interviewer + feedback report.

## Layout
- project.yml (XcodeGen). Never edit .xcodeproj; run `make gen`.
- App/Audio: ProcessTapCapture (Core Audio tap), MicCapture (AVAudioEngine)
- App/Speech: SttProvider protocol, SpeechAnalyzerProvider
- App/AI: ClaudeClient (URLSession SSE), QuestionDetector, HintGenerator
- App/UI: OverlayPanel (NSPanel), CaptionView, HintView, SetupView
- App/Store: SwiftData models (Profile, StarStory, Session)
- prompts/*.md: templates with {{variables}}. Don't rewrite unless asked.

## Commands
- `make build` (errors only) · `make run` · `make test`
- Build after every change; fix errors before reporting done.

## Rules
- claude-haiku-5-5 for detection + hints; claude-sonnet-5-5 for practice + feedback
- API key from Keychain only. Never store raw audio.
- Target < 2s from end of question to first hint token.
- Stay within the current task; don't refactor unrelated files.