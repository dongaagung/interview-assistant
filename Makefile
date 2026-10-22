# Builds with Command Line Tools + SwiftPM only (no Xcode).
# macOS ships GNU Make 3.81 (no .SHELLFLAGS), so pipefail is set per recipe.
SHELL := /bin/bash

NAME    := InterviewAssistant
SUPPORT := App/Support
APP     := .build/$(NAME).app
RELEASE := .build/release-bundle/$(NAME).app
# Installed under a readable name; the executable inside keeps $(NAME).
INSTALLED := /Applications/Interview Assistant.app
BUNDLE_ID := rakyat.interviewassistant

# The default Swift Build backend can't initialize without Xcode.
SWIFTPM := --build-system native
# Drop that flag's deprecation notice so `make build` stays errors-only.
FILTER  := sed '/build-system native. has been deprecated/d' | xcbeautify --quiet --disable-logging

# Command Line Tools ship Swift Testing outside the default search paths.
CLT_DEV := /Library/Developer/CommandLineTools/Library/Developer
TESTING := -Xswiftc -F$(CLT_DEV)/Frameworks -Xlinker -F$(CLT_DEV)/Frameworks \
           -Xlinker -rpath -Xlinker $(CLT_DEV)/Frameworks \
           -Xlinker -rpath -Xlinker $(CLT_DEV)/usr/lib

# $(call bundle,<executable>,<app>): assemble and ad-hoc sign an .app.
define bundle
	rm -rf "$(2)"
	mkdir -p "$(2)/Contents/MacOS" "$(2)/Contents/Resources"
	cp "$(1)" "$(2)/Contents/MacOS/$(NAME)"
	cp $(SUPPORT)/Info.plist "$(2)/Contents/"
	cp $(SUPPORT)/AppIcon.icns "$(2)/Contents/Resources/"
	cp -R prompts "$(2)/Contents/Resources/"
	set -o pipefail; codesign --force --options runtime \
		--entitlements $(SUPPORT)/$(NAME).entitlements --sign - "$(2)" 2>&1 \
		| sed '/replacing existing signature/d'
endef

.PHONY: build run test install uninstall icon

build:
	set -o pipefail; swift build $(SWIFTPM) 2>&1 | $(FILTER)
	$(call bundle,.build/debug/$(NAME),$(APP))

run: build
	open $(APP)

test:
	set -o pipefail; swift test $(SWIFTPM) $(TESTING) 2>&1 | $(FILTER) --is-ci

# Optimized build, installed in /Applications to open from Launchpad,
# Spotlight or the Dock. Quits a running copy first. Re-run after changes.
install:
	set -o pipefail; swift build -c release $(SWIFTPM) 2>&1 | $(FILTER)
	$(call bundle,.build/release/$(NAME),$(RELEASE))
	osascript -e 'quit app id "$(BUNDLE_ID)"' 2>/dev/null || true
	sleep 1
	rm -rf "$(INSTALLED)"
	ditto "$(RELEASE)" "$(INSTALLED)"
	@echo "Installed $(INSTALLED)"

uninstall:
	osascript -e 'quit app id "$(BUNDLE_ID)"' 2>/dev/null || true
	rm -rf "$(INSTALLED)"
	@echo "Removed $(INSTALLED). Your profile and sessions stay in ~/Library/Application Support/$(BUNDLE_ID)."

# Redraws App/Support/AppIcon.icns.
icon:
	swift scripts/make-icon.swift $(SUPPORT)/AppIcon.icns
