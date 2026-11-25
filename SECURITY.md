# Security policy

## Supported versions

Only the latest release of SoundBlink receives fixes.

## Reporting a vulnerability

Please don't report security problems in public issues. Use GitHub's private
vulnerability reporting instead:

1. Open the [Security tab](https://github.com/takuhoito/SoundBlink/security)
   of this repository.
2. Click **Report a vulnerability** and describe the problem.

Only the maintainer can see the report. Please include the steps to reproduce
the problem, the SoundBlink and macOS versions, and what an attacker could
achieve with it.

SoundBlink is a spare-time project with a single maintainer. I'll try to
acknowledge your report within a week and keep you updated until it is
resolved.

## Scope

SoundBlink does not connect to the network and does not ask for special
permissions. It changes the system's default audio output and stores its own
settings. Reports about the following are especially welcome:

- the app or its command-line interface doing anything beyond that
- the build and release pipeline (GitHub Actions) or the published zip files
