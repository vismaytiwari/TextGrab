# Contributing to TextGrab

Thanks for helping improve TextGrab. Focused bug fixes, OCR improvements,
accessibility work, and small native-macOS refinements are welcome.

## Development setup

1. Fork and clone the repository.
2. Make sure Xcode Command Line Tools are installed.
3. Run `make app` from the repository root.
4. Launch `build.noindex/TextGrab.app` and verify the affected behavior manually.

## Pull requests

- Keep changes focused and explain the user-facing motivation.
- Preserve the on-device, network-free design.
- Do not add telemetry or persist captured images/text.
- Run `make app` before submitting.
- Manually verify capture, OCR, clipboard output, and cancellation when relevant.
- For UI changes, include before-and-after screenshots when practical.
- Update the README when permissions, requirements, or user-visible behavior change.

For security-sensitive reports, follow [SECURITY.md](SECURITY.md) instead of
opening a public issue.
