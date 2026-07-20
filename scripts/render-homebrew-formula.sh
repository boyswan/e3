#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "usage: $0 VERSION ARM64_ARCHIVE X86_64_ARCHIVE [OUTPUT]" >&2
  exit 2
fi

version="$1"
arm64_archive="$2"
x86_64_archive="$3"
output="${4:-dist/e3-cli.rb}"
root="$(cd "$(dirname "$0")/.." && pwd)"
template="$root/packaging/homebrew/e3-cli.rb.in"

for archive in "$arm64_archive" "$x86_64_archive"; do
  if [[ ! -f "$archive" ]]; then
    echo "archive does not exist: $archive" >&2
    exit 2
  fi
done

arm64_sha="$(shasum -a 256 "$arm64_archive" | awk '{print $1}')"
x86_64_sha="$(shasum -a 256 "$x86_64_archive" | awk '{print $1}')"
mkdir -p "$(dirname "$output")"

sed \
  -e "s/@VERSION@/$version/g" \
  -e "s/@ARM64_SHA256@/$arm64_sha/g" \
  -e "s/@X86_64_SHA256@/$x86_64_sha/g" \
  "$template" > "$output"

echo "$output"
