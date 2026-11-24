# shellcheck shell=bash disable=SC2034
# Project identity, shared by the build scripts. Change these in one place.
# Note: APP_NAME must match the executable target name in Package.swift.

APP_NAME="SoundBlink"
BUNDLE_ID="io.github.takuhoito.soundblink"
AUTHOR="Ito Takuho"
GITHUB_REPO="takuhoito/SoundBlink"

# Overridable from the environment (CI sets these from the git tag / run number).
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
