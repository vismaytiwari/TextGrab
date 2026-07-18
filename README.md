<p align="center">
  <img src="Resources/TextGrab.iconset/icon_128x128.png" width="112" alt="TextGrab app icon">
</p>

<h1 align="center">TextGrab</h1>

<p align="center">
  Select any region of your screen and copy its text in one shortcut.
</p>

<p align="center">
  <a href="https://github.com/vismaytiwari/TextGrab/actions/workflows/build.yml"><img src="https://github.com/vismaytiwari/TextGrab/actions/workflows/build.yml/badge.svg" alt="Build status"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14 or later">
  <img src="https://img.shields.io/badge/OCR-on--device-2ea44f" alt="On-device OCR">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/vismaytiwari/TextGrab" alt="MIT License"></a>
</p>

Press **⇧⌘2**, drag a box over anything on screen, and the recognized text is
placed on your clipboard. TextGrab works with screenshots, PDF pages, video
frames, remote desktops, and apps that do not expose selectable text.

## Why TextGrab

- One global shortcut and the familiar macOS selection crosshair
- Accurate on-device OCR through Apple's Vision framework
- A compact confirmation HUD with the captured region and text preview
- No network requests, accounts, analytics, or telemetry
- No Accessibility permission: the shortcut uses the system hot-key API
- A native AppKit menu-bar app with a single small Swift binary

## Requirements

- macOS 14 Sonoma or later
- Xcode Command Line Tools (or Xcode) with a Swift compiler

Install the command-line tools if needed:

```sh
xcode-select --install
```

## Quick start

```sh
git clone https://github.com/vismaytiwari/TextGrab.git
cd TextGrab
make app
open build.noindex/TextGrab.app
```

To keep the app in Applications:

```sh
ditto build.noindex/TextGrab.app /Applications/TextGrab.app
```

TextGrab enables launch at login on first launch. You can turn it off from the
TextGrab menu-bar menu.

## Use

1. Press **⇧⌘2**.
2. Drag over the region containing text.
3. Paste the recognized text into any app.

TextGrab calls macOS's own interactive `screencapture` tool, sends the selected
pixels through Vision, and replaces the captured image on the clipboard with
recognized text. Pressing Escape cancels without changing anything.

## Permissions

macOS may request **Screen Recording** permission on the first grab. This is a
system requirement for reading pixels displayed by other apps. TextGrab does
not need Accessibility permission.

If capture is blocked, enable TextGrab in **System Settings → Privacy & Security
→ Screen & System Audio Recording**, then relaunch it.

## Privacy

Every OCR request runs locally on your Mac. Captured images and recognized text
are never transmitted or saved by TextGrab; the successful result exists only
on the system clipboard and briefly in the confirmation HUD.

## Development

```sh
make app            # build build.noindex/TextGrab.app
make run            # build and launch TextGrab
make icon           # regenerate Resources/TextGrab.icns
make print-sources  # show the Swift compilation inputs
make clean          # remove local build output
```

The project intentionally uses a small Makefile rather than an Xcode project.
See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## License

TextGrab is available under the [MIT License](LICENSE).
