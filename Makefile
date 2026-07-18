APP_NAME := TextGrab
BUNDLE_ID := io.github.vismaytiwari.TextGrab
BUILD_DIR := build.noindex
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
SOURCES := $(shell find Sources/TextGrab -name '*.swift' | sort)
FRAMEWORKS := -framework AppKit -framework Foundation -framework Vision -framework Carbon -framework ServiceManagement

.PHONY: app icon run clean print-sources

app:
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	swiftc -Osize -whole-module-optimization $(FRAMEWORKS) $(SOURCES) -o "$(MACOS_DIR)/$(APP_NAME)"
	cp Resources/Info.plist "$(CONTENTS_DIR)/Info.plist"
	if [ -f Resources/$(APP_NAME).icns ]; then cp Resources/$(APP_NAME).icns "$(RESOURCES_DIR)/$(APP_NAME).icns"; fi
	printf 'APPL????' > "$(CONTENTS_DIR)/PkgInfo"
	plutil -replace CFBundleExecutable -string "$(APP_NAME)" "$(CONTENTS_DIR)/Info.plist"
	plutil -replace CFBundleIdentifier -string "$(BUNDLE_ID)" "$(CONTENTS_DIR)/Info.plist"
	codesign --force --deep --sign - "$(APP_DIR)"

icon:
	swift Scripts/generate_icon.swift
	iconutil -c icns Resources/$(APP_NAME).iconset -o Resources/$(APP_NAME).icns

run: app
	"$(MACOS_DIR)/$(APP_NAME)"

clean:
	rm -rf "$(BUILD_DIR)"

print-sources:
	@printf '%s\n' $(SOURCES)
