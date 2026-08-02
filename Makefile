APP_NAME := TextGrab
BUNDLE_ID := io.github.vismaytiwari.TextGrab
BUILD_DIR := build.noindex
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
SOURCES := $(shell find Sources/TextGrab -name '*.swift' | sort)
FRAMEWORKS := -framework AppKit -framework Foundation -framework Vision -framework Carbon -framework ServiceManagement
# macOS ties the Screen Recording grant to the code signature, so a STABLE
# identity is what stops the permission being forgotten on every rebuild.
# Create it once with `make signing-cert`.
SIGN_IDENTITY ?= TextGrab Dev
INSTALLED_APP := /Applications/$(APP_NAME).app

.PHONY: app signing-cert install restart icon run clean print-sources

app:
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	swiftc -Osize -whole-module-optimization $(FRAMEWORKS) $(SOURCES) -o "$(MACOS_DIR)/$(APP_NAME)"
	cp Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	if [ -f Resources/$(APP_NAME).icns ]; then cp Resources/$(APP_NAME).icns "$(RESOURCES_DIR)/$(APP_NAME).icns"; fi
	printf 'APPL????' > "$(CONTENTS_DIR)/PkgInfo"
	plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS_DIR)/Info.plist"
	@if security find-identity -p codesigning 2>/dev/null | grep -q "$(SIGN_IDENTITY)"; then \
	  codesign --force --deep --sign "$(SIGN_IDENTITY)" --identifier "$(BUNDLE_ID)" "$(APP_DIR)"; \
	  echo "Signed with '$(SIGN_IDENTITY)' — the Screen Recording grant survives rebuilds."; \
	else \
	  codesign --force --deep --sign - --identifier "$(BUNDLE_ID)" "$(APP_DIR)"; \
	  echo "Ad-hoc signed. Run 'make signing-cert' once so macOS stops forgetting Screen Recording."; \
	fi
	@# A quarantined bundle signed by a local cert gets a Gatekeeper "Not Opened"
	@# refusal, and quarantine is also what makes macOS run the app from a random
	@# translocated path (which would break its permissions).
	@find "$(APP_DIR)" -print0 | xargs -0 xattr -d com.apple.quarantine 2>/dev/null || true

signing-cert:
	./Scripts/setup-signing-cert.sh

# The copy that actually runs (and that launch-at-login starts) is the one in
# /Applications — a build in $(BUILD_DIR) changes nothing until it is installed.
# The running app is quit first, because replacing a live bundle is asking for
# trouble, and the new copy is staged next to the old one so a failed copy cannot
# leave you without an app.
install: app
	-@osascript -e 'quit app "$(APP_NAME)"' >/dev/null 2>&1 || true
	-@pkill -f "$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" 2>/dev/null || true
	@sleep 1
	rm -rf "$(INSTALLED_APP).new"
	ditto --noqtn "$(APP_DIR)" "$(INSTALLED_APP).new"
	rm -rf "$(INSTALLED_APP)"
	mv "$(INSTALLED_APP).new" "$(INSTALLED_APP)"
	@find "$(INSTALLED_APP)" -print0 | xargs -0 xattr -d com.apple.quarantine 2>/dev/null || true
	@echo "Installed $(INSTALLED_APP)"

# `open` on a running app only activates it, so install (which quits it) first.
restart: install
	open "$(INSTALLED_APP)"
	@echo "Relaunched from $(INSTALLED_APP)"

icon:
	swift Scripts/generate_icon.swift
	iconutil -c icns Resources/$(APP_NAME).iconset -o Resources/$(APP_NAME).icns

run: app
	"$(MACOS_DIR)/$(APP_NAME)"

clean:
	rm -rf "$(BUILD_DIR)"

print-sources:
	@printf '%s\n' $(SOURCES)
