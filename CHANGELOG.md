# Changelog

All notable changes to Dockside are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- **Watch** widget: search YouTube and play videos inside the dock bar or in a floating picture-in-picture window; Netflix and JioHotstar in the same player (#6).
- **Countdown** widget — days until a date you pick, with quick presets (#1).
- **Drag to reorder** widgets right on the dock (#3).
- **Multiple displays:** Settings ▸ Appearance ▸ Display ▸ *Follow the pointer* (#4).
- **Localization:** Spanish and Hindi, plus `Scripts/extract-strings.py` for translators (#5).

### Fixed
- Scrolling a dock wider than the screen: trackpad swipes now scroll sideways and reach both ends.

## [0.1.0-beta] — 2026-10-19

The first public beta. 🎉

### Added
- A floating second dock that auto-hides, reveals on a bottom-edge hover and stays clear of the macOS Dock.
- 34 widgets across AI, media, apps & files, productivity, Mac controls, creator tools and developer tools.
- Claude panel (<kbd>⌃⌥C</kbd>): streaming chat with Opus 5.5 by default, live artifacts, and your claude.ai account.
- Now Playing for YouTube Music (Chrome, Brave, Edge, Safari), Spotify and Apple Music.
- Profiles, four themes, seven accent colors, three sizes, top/bottom or free placement.
- Horizontal scrolling when your widgets don’t fit the screen.
- Universal build for Apple Silicon and Intel.

### Known limitations
- Builds aren’t notarized yet, so macOS asks you to confirm the first launch.
- One dock on the main display only.
