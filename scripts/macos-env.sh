#!/usr/bin/env bash
# Source this file on macOS before building/running without Nix:
#
#   source scripts/macos-env.sh
#   odin run src

set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. Install it from https://brew.sh, then run:" >&2
  echo "  brew install odin sdl3 sdl3_ttf" >&2
  return 1 2>/dev/null || exit 1
fi

missing=()
for formula in odin sdl3 sdl3_ttf; do
  if ! brew list --formula "$formula" >/dev/null 2>&1; then
    missing+=("$formula")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "Missing Homebrew dependencies. Install them with:" >&2
  echo "  brew install ${missing[*]}" >&2
  return 1 2>/dev/null || exit 1
fi

sdl3_prefix="$(brew --prefix sdl3)"
sdl3_ttf_prefix="$(brew --prefix sdl3_ttf)"
lib_paths=(
  "$sdl3_prefix/lib"
  "$sdl3_ttf_prefix/lib"
)

joined_lib_paths="$(IFS=:; echo "${lib_paths[*]}")"

export LIBRARY_PATH="$joined_lib_paths${LIBRARY_PATH:+:$LIBRARY_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="$joined_lib_paths${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

echo "macOS build environment configured."
echo "Run with: odin run src"
