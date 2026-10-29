# Interview Assistant

A native macOS app that listens to a video interview, captions both sides
live, spots the interviewer's questions and streams answer hints while you
talk. It also has a Practice Mode, where an AI interviewer asks you
questions and writes a feedback report afterwards.

Speech recognition runs on your Mac. The AI parts (question detection,
hints, practice, feedback, prep) use one AI provider of your choice:
Anthropic by default, or any OpenAI-compatible one.

## Features

- **Live**: captures the meeting app's audio (the interviewer) and your
  microphone (you) separately, shows live captions, and hints each question
  as soon as the interviewer stops talking. The goal is under 2 seconds from
  the end of the question to the first hint word. Press **⌃⌥H** in any app
  to hint the last question by hand. A floating overlay keeps captions and
  hints above the meeting window. While you answer, it shows how long you've
  been talking and how many fillers ("um", "eh", "anu", "you know") the
  captions caught; past two minutes it turns orange. Set **Translate
  questions into** in Setup to see each hinted question in your language too.
- **Prep**: generates the questions you're most likely to be asked, with
  answers built from your profile, CV and STAR stories. You can edit them.
  During a live interview, a question that clearly matches one of these
  shows its prepared answer right away. **Questions to ask them** writes your
  questions for "Do you have any questions for us?".
- **Practice**: an AI interviewer asks questions based on your profile, or
  from your prep sheet with real interview questions first. You answer by
  voice or by typing, then get a feedback report.
- **Sessions**: every live interview and practice run is saved with its
  transcript, hints and feedback. **Add questions to Prep** turns the
  questions an interview asked into clean prep-sheet entries, so they show
  instantly next time.
- **Setup**: your profile, CV import (PDF, Word, RTF or plain text), STAR
  stories, AI provider, hint style (short guide, a full answer of 1 to 1.5
  minutes, or both side by side), speech language and extra vocabulary.

## Requirements

- macOS 26 or later
- Command Line Tools with Swift 6.2 or later (`xcode-select --install`).
  Xcode is not needed.
- [xcbeautify](https://github.com/cpisciotta/xcbeautify), which the Makefile
  uses to shorten build output: `brew install xcbeautify`
- An API key for one AI provider, or a local [Ollama](https://ollama.com)

## Build and run

```sh
make run        # debug build, bundled and signed as .build/InterviewAssistant.app, then opened
make test       # run the tests
make install    # release build into "/Applications/Interview Assistant.app"
make uninstall  # remove it from /Applications (your data stays)
```

`make build` builds without opening the app, and `make icon` redraws
`App/Support/AppIcon.icns` from `scripts/make-icon.swift`.

## First run

1. Open **Setup** and choose an AI provider. Paste its API key, which is
   saved in your Keychain.
2. Fill in your profile: target role, CV (or **Import CV…**) and a few STAR
   stories. Hints only use the experience you put here.
3. Pick the speech language. English is the default, and Indonesian also
   works.
4. Allow microphone, audio capture and speech recognition when macOS asks.
5. Use headphones so the microphone doesn't pick up the interviewer.

In **Live**, choose where the interviewer's audio comes from (all system
audio, or one app such as Zoom or a browser) and press **Start**.

## AI providers

Only one provider is active at a time.

| Provider | Detection and hints | Practice, feedback and prep |
| --- | --- | --- |
| Anthropic (default) | `claude-haiku-5-5` | `claude-sonnet-5-5` |
| OpenAI, Google Gemini, DeepSeek, Groq, OpenRouter, Ollama, or another OpenAI-compatible server | your "fast" model | your "smart" model |

The prompts are tuned for Claude, so other models may answer differently.
They live in [prompts/](prompts/) as Markdown templates with `{{variables}}`.

## Privacy

- Speech is transcribed on your Mac. Raw audio is never saved.
- API keys are kept in the Keychain only.
- Your profile, CV and the interview conversation are sent to the AI
  provider you choose. Email addresses and phone numbers are removed from an
  imported CV.
- Profile, settings, prep and sessions are saved as JSON in
  `~/Library/Application Support/rakyat.interviewassistant`.

## Project layout

```text
App/
  Audio/     meeting-app audio (Core Audio process tap) and microphone capture
  Speech/    on-device speech recognition and interview vocabulary
  AI/        provider clients (Anthropic, OpenAI-compatible), detection, hints, practice, prep
  Live/      live session: captions, turn tracking, pause detection, hot key
  Practice/  practice session
  UI/        SwiftUI views and the floating overlay
  Store/     Codable models, JSON storage, Keychain
  Support/   Info.plist, entitlements, app icon
Tests/       unit tests
prompts/     prompt templates
scripts/     icon generator
```

Notes for working on the code, including the no-Xcode constraints, are in
[CLAUDE.md](claude.md).
