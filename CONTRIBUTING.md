# Contributing to SoundBlink

Thanks for your interest in SoundBlink! Issues and pull requests are welcome,
in English or Japanese (日本語でも大丈夫です).

By taking part, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
To report a security problem, follow [SECURITY.md](SECURITY.md) instead of
opening an issue.

## Reporting a bug

Use the
[bug report form](https://github.com/takuhoito/SoundBlink/issues/new?template=bug_report.yml).
The most useful details are:

- the output of `SoundBlink --list`
  (`/Applications/SoundBlink.app/Contents/MacOS/SoundBlink --list`)
- your Mac model and macOS version
- how the audio device is connected: directly, through a hub, or through a
  monitor or dock
- whether clicking the menu bar icon clears the noise

## Suggesting a feature

SoundBlink aims to stay small and quiet: one job, done well, with as few
settings as possible. Before you start on a larger change, please open an
issue to talk it through, so that your time isn't wasted.

## Development

You need macOS 13 or later and the Xcode command line tools (Swift 5.9 or
later).

```sh
swift build                        # compile
swift run SoundBlink --list        # try the CLI without building the app bundle
ARCHS=arm64 scripts/build-app.sh   # build build/SoundBlink.app quickly
```

`build/SoundBlink.app/Contents/MacOS/SoundBlink --reset` performs a real
reset, so expect a short gap in your audio. To watch the logs:

```sh
/usr/bin/log stream --predicate 'subsystem == "io.github.takuhoito.soundblink"'
```

### Where things are

| Path | Contents |
| --- | --- |
| `Sources/SoundBlink/CoreAudioDevices.swift` | Thin wrapper around the Core Audio HAL |
| `Sources/SoundBlink/Resetter.swift` | The switch-and-return logic |
| `Sources/SoundBlink/AppDelegate.swift` | Menu bar UI, timer, wake handling and login item |
| `Sources/SoundBlink/Settings.swift` | User defaults |
| `Sources/SoundBlink/main.swift` | Command-line options |
| `Resources/` | Info.plist template, localized strings and icon sources |
| `scripts/` | Build and icon scripts. The app name and version are in `config.sh` |
| `site/` | The website (plain HTML), published with GitHub Pages |

### Guidelines

- Identify audio devices by their UID and transport type, never by their
  display name, which is localized.
- Put user-facing text in both `Resources/en.lproj` and `Resources/ja.lproj`.
  The same goes for `README.md` and `README.ja.md`, and for
  `site/index.html` and `site/ja/index.html`. If you can't write one of the
  languages, say so in the pull request and I'll fill it in.
- Edit icons in their SVG sources and regenerate the assets with
  `scripts/make-icons.sh`. Only contribute artwork that you made yourself.
- After changing scripts, run `shellcheck -x scripts/*.sh`. After changing
  workflows, run `actionlint`.

## Pull requests

- Keep each pull request focused on one change.
- Write commit messages in the
  [Conventional Commits](https://www.conventionalcommits.org/) style, for
  example `fix: switch back when the device disappears`. Use `feat`, `fix`,
  `docs`, `build`, `ci` or `chore`.
- Describe how you tested the change, including your Mac model, macOS
  version and audio device.
- Contributions are released under the project's [MIT License](LICENSE).
