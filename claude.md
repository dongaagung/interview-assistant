# Interview Assistant (macOS, SwiftUI)

Native macOS app (Swift 6, SwiftUI). Captures meeting-app audio
(interviewer) and mic (user) separately, shows live captions, detects
interviewer questions, streams answer hints from the Claude API.
Practice Mode: AI interviewer + feedback report.

## Layout
- Package.swift (SwiftPM). Builds with Command Line Tools only, no Xcode
  (not enough disk). `make build` bundles + ad-hoc signs .build/InterviewAssistant.app.
- App/Support: Info.plist (literal values, no $(VARS)), entitlements
- App/Audio: ProcessTapCapture (Core Audio tap), MicCapture (AVAudioEngine)
- App/Speech: SttProvider protocol, SpeechAnalyzerProvider (SpeechTranscriber;
  DictationTranscriber fallback for languages it lacks, e.g. id-ID),
  InterviewVocabulary (built-in Java/architecture terms + profile terms).
  Measured: SpeechTranscriber ignores contextual strings; DictationTranscriber
  uses them but finalizes 0.5–1 s later, so it's opt-in for English.
- App/AI: LLMClient protocol (provider-neutral requests by purpose), ClaudeClient
  (Anthropic, URLSession SSE), OpenAICompatibleClient (OpenAI, Gemini, DeepSeek, Groq,
  OpenRouter, Ollama, custom; JSON falls back schema → json_object → instructions),
  AIProvider, QuestionDetector, HintGenerator, QuestionTranslator, PracticeInterviewer +
  FeedbackGenerator, PrepGenerator, QuestionsToAskGenerator, AskedQuestionsGenerator
  (session → prep items), PromptTemplate (loads prompts/)
- App/Live: LiveSession (audio → captions → detection → hints; autosaves every
  10 s), TurnTracker (+ early hints: at a 0.55 s pause, a clear question in the
  volatile text is hinted before the final text, which takes 1–2 s more; kept
  only if the final text matches), PauseDetector (end of speech from audio level,
  also the start of the latency label), AnswerMeter (answer timer + filler count
  from the mic's final captions), GlobalHotKey (⌃⌥H "Hint now", Carbon), PrepMatcher (strict
  keyword match; macOS sentence embeddings mismatched questions, so not used)
- App/Practice: PracticeSession (AI interviewer, voice answers, feedback)
- App/UI: OverlayPanel (NSPanel), CaptionView, HintView, SetupView, LiveView,
  PrepView, PracticeView, SessionsView
- App/Store: Codable models (Profile, StarStory, Session, PrepItem) saved as JSON in
  Application Support. No SwiftData: @Model's macro plugin needs Xcode.
- prompts/*.md: templates with {{variables}}. Don't rewrite unless asked.

## Commands
- `make build` (errors only) · `make run` · `make test`
- `make install`: release build into "/Applications/Interview Assistant.app"
  (quits a running copy first) · `make uninstall` · `make icon` redraws
  App/Support/AppIcon.icns from scripts/make-icon.swift
- Build after every change; fix errors before reporting done.
- No Xcode-only tools: no #Preview, no asset catalogs, no SwiftData macros.
  `@State` is a macro in the macOS 27 SDK: use `@ViewState` (same wrapper).
  SwiftPM runs with `--build-system native` (default backend needs Xcode).

## Rules
- Exactly one AI provider is active (Setup). Anthropic is the default:
  claude-haiku-5-5 for detection + hints; claude-sonnet-5-5 for practice, feedback, prep.
  Other providers: the user's fast model for detection + hints, smart model for the rest.
- API keys from Keychain only (one account per provider). Never store raw audio.
- Target < 2s from end of question to first hint token.
- Stay within the current task; don't refactor unrelated files.