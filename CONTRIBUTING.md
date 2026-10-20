# Contributing to Dockside

Thanks for helping make Dockside better! Bug fixes, new widgets, docs and design polish are all welcome.

## Ground rules

- Be kind — see the [Code of Conduct](CODE_OF_CONDUCT.md).
- One topic per pull request. Small PRs get reviewed fastest.
- **Privacy is a feature.** No analytics, tracking or telemetry. If your change talks to a new network service, add it to the *What leaves your Mac* table in the README.
- **Permissions are opt-in.** Only ask macOS for a permission when the user actually uses the widget that needs it, and document it in the README’s permissions table and the usage strings in `build.sh`.

## Getting set up

```sh
# Fork on GitHub, then:
git clone https://github.com/<you>/Dockside.git
cd Dockside
./build.sh          # builds a universal app and installs it to /Applications
```

You only need the Xcode Command Line Tools (`xcode-select --install`). Open the folder in Xcode or any editor — it’s a plain Swift package.

For quick iterations, `swift build -c release && .build/release/Dockside` runs the app without installing it.

## Project layout

```
Sources/Dockside/
├── DocksideApp.swift          app entry, menu bar, hotkeys, settings window
├── DockWindowController.swift the floating panel: sizing, scrolling, auto-hide, placement
├── DockView.swift             the bar, tiles and the widget switchboard (WidgetHost)
├── Models.swift               WidgetKind catalogue, profiles, settings
├── Store.swift                persistence (JSON in ~/Library/Application Support/Dockside)
├── Theme.swift                palette, Tile, PopoverTile, buttons, gauges
├── Widgets/                   one file per widget family
├── Services/                  system stats, weather, music, clipboard, calendar…
├── Claude/                    Claude chat client, artifacts and claude.ai panel
└── Settings/                  the Settings window
```

## Add a widget in 5 steps

1. **Register it.** Add a case to `WidgetKind` in `Models.swift`. The compiler will point you to each `switch` that needs a `title`, `symbol`, `tint`, `category` and `summary`.
2. **Build the view.** Create it in `Sources/Dockside/Widgets/`. Wrap it in `Tile` (or `PopoverTile` to get a click-to-expand popover) and read colors from `@Environment(\.palette)` so it works in every theme:

   ```swift
   struct HelloWidget: View {
       @Environment(\.palette) private var p
       var body: some View {
           PopoverTile(width: 140) {
               Text("Hello 👋").font(.system(size: 15, weight: .semibold)).foregroundStyle(p.primary)
           } popover: {
               Text("Expanded view")
           }
       }
   }
   ```
3. **Wire it up.** Add your case to `WidgetHost.content` in `DockView.swift`.
4. **Need live data?** Put it in an `ObservableObject` service in `Services/` and start it lazily or from `AppDelegate`. Keep polling cheap (seconds, not milliseconds) and only run when the widget is useful.
5. **Try it.** Build, open *Settings ▸ Widgets*, add your widget and check it in the Midnight, Glass and Light themes and at all three sizes. Add a screenshot to your PR.

## Testing without touching your own data

These environment variables make development and screenshots safe:

| Variable | Effect |
|---|---|
| `DOCKSIDE_DATA_DIR=/tmp/dockside-demo` | Use a separate data folder |
| `DOCKSIDE_DEMO=1` | Show a sample track instead of reading your music players |
| `DOCKSIDE_SNAPSHOT=/tmp/shots` | Render the app’s windows to PNGs after launch |
| `DOCKSIDE_PROFILE=Work`, `DOCKSIDE_TAB=widgets` | Pick a profile / settings tab for the snapshot |
| `DOCKSIDE_ASK="question \|\| follow-up"` | Send Claude chat turns on launch |
| `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY` | Point Claude chat at a proxy or local stub |

## Translating Dockside

Dockside ships in English, Spanish and Hindi. Translations live in `Resources/Localization/<lang>.lproj/Localizable.strings`.

1. Run `python3 Scripts/extract-strings.py` — it regenerates English from the source and lists untranslated keys per language.
2. To add a language, create `Resources/Localization/<code>.lproj/` (e.g. `fr.lproj`), run the script, then translate the values.
3. Build with `./build.sh` and test with `open -a Dockside --args -AppleLanguages "(fr)"`.

UI text in Swift should be a literal in a SwiftUI view (`Text("Hello")`) or `String(localized: "Hello")`, so the script can find it. Strings with interpolation (`"\(n) left"`) aren't extracted yet — converting them to proper format keys is a great first contribution.

## Code style

- Match the surrounding code: SwiftUI views, small focused types, `private` by default.
- Comments explain *why*, not *what*.
- No new third-party dependencies without discussing it in an issue first — Dockside stays small.
- Make sure `swift build -c release` passes with no new warnings.

## Pull requests

1. Branch from `main`.
2. Describe what changed and why; link the issue it closes.
3. Include screenshots or a short screen recording for anything visual.
4. CI must be green. A maintainer will review — thanks for your patience!

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

## Releasing (maintainers)

1. Bump `VERSION` and `BUILD_NUMBER` in `build.sh`; move *Unreleased* in `CHANGELOG.md` under the new version.
2. `./build.sh --dmg --no-install`, then publish `build/Dockside-<version>-beta.dmg` and its `.sha256` as a GitHub pre-release tagged `v<version>-beta` (or run the **Release DMG** workflow).
3. Update `version` and `sha256` in [shreyansa98/homebrew-tap](https://github.com/shreyansa98/homebrew-tap/blob/main/Casks/dockside.rb).
