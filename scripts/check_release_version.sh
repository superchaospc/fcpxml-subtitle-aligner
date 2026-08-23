#!/bin/bash
set -euo pipefail

die() {
    echo "check_release_version.sh: $*" >&2
    exit 1
}

[[ $# -eq 1 ]] || die "usage: $0 vMAJOR.MINOR.PATCH"
tag="$1"
[[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be an exact semver tag such as v1.0.0"
version="${tag#v}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd "$script_dir/.." && pwd -P)"
cli_source="$source_root/Sources/FCPXMLAlignerCLI/CLIApplication.swift"
plist="$source_root/Resources/Info.plist"
skill="$source_root/skills/fcpxml-subtitle-aligner/SKILL.md"
changelog="$source_root/CHANGELOG.md"

expected_cli="public static let version = \"$version\""
/usr/bin/grep -Fq "$expected_cli" "$cli_source" || die "version mismatch: CLIApplication.swift must declare $version"

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" || die "could not read CFBundleShortVersionString"
[[ "$app_version" == "$version" ]] || die "version mismatch: CFBundleShortVersionString is $app_version, expected $version"

for token in \
    "tag \`$tag\`" \
    "fcpxml-aligner-$tag-macos-universal.tar.gz" \
    "/releases/download/$tag/SHA256SUMS"
do
    /usr/bin/grep -Fq "$token" "$skill" || die "version mismatch: SKILL.md is missing $token"
done

/usr/bin/head -n 1 "$changelog" | /usr/bin/grep -Fq "## [$version]" || die "version mismatch: CHANGELOG.md must begin with [$version]"

echo "release version consistency: PASS ($tag)"
