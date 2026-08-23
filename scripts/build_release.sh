#!/bin/bash
set -euo pipefail

developer_dir="${DEVELOPER_DIR:-}"
app_name="FCPXML Subtitle Aligner.app"
workspace_marker_name=".fcpxml-subtitle-aligner-release-stage-owner"
workspace_marker_value="local.codex.fcpxml-subtitle-aligner.release-stage"

die() {
    echo "build_release.sh: $*" >&2
    exit 1
}

path_is_occupied() {
    [[ -e "$1" || -L "$1" ]]
}

lstat_identity() {
    /usr/bin/stat -f '%d:%i:%HT' "$1"
}

matches_identity() {
    local path="$1"
    local expected_identity="$2"
    [[ -n "$expected_identity" && -e "$path" && ! -L "$path" && "$(lstat_identity "$path")" == "$expected_identity" ]]
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd "$script_dir/.." && pwd -P)"
build_app_script="$script_dir/build_app.sh"
version_check_script="$script_dir/check_release_version.sh"
skill_source="$source_root/skills/fcpxml-subtitle-aligner"

version=""
output_dir_input=""
test_prebuilt_app_binary=""
test_prebuilt_cli_binary=""
test_skip_fat_verification=false
test_inject_post_stage_failure=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 && -z "$version" ]] || die "--version requires one value"
            version="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 && -z "$output_dir_input" ]] || die "--output-dir requires one value"
            output_dir_input="$2"
            shift 2
            ;;
        --test-prebuilt-app-binary)
            [[ $# -ge 2 && -z "$test_prebuilt_app_binary" ]] || die "--test-prebuilt-app-binary requires one value"
            test_prebuilt_app_binary="$2"
            shift 2
            ;;
        --test-prebuilt-cli-binary)
            [[ $# -ge 2 && -z "$test_prebuilt_cli_binary" ]] || die "--test-prebuilt-cli-binary requires one value"
            test_prebuilt_cli_binary="$2"
            shift 2
            ;;
        --test-skip-fat-verification)
            test_skip_fat_verification=true
            shift
            ;;
        --test-inject-post-stage-failure)
            test_inject_post_stage_failure=true
            shift
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be an exact semver tag such as v1.0.0"
[[ -f "$version_check_script" && -x "$version_check_script" ]] || die "release version checker is unavailable or not executable"
"$version_check_script" "$version"
[[ -n "$output_dir_input" ]] || die "--output-dir is required"
[[ "$output_dir_input" != "/" ]] || die "--output-dir must name a release directory"

output_leaf="$(basename -- "$output_dir_input")"
[[ -n "$output_leaf" && "$output_leaf" != "." && "$output_leaf" != ".." ]] || die "--output-dir must name a release directory"
output_parent_input="$(dirname -- "$output_dir_input")"

test_mode=false
if [[ -n "$test_prebuilt_app_binary" || -n "$test_prebuilt_cli_binary" || "$test_skip_fat_verification" == true || "$test_inject_post_stage_failure" == true ]]; then
    test_mode=true
    canonical_temp_root="$(cd -- /tmp && pwd -P)" || die "could not canonicalize /tmp"
    [[ ( "$output_parent_input" == "/tmp" || "$output_parent_input" == "$canonical_temp_root" ) && "$output_leaf" == fcpxml-subtitle-aligner-release-test.?* ]] || die "test-only options require a canonical /tmp/fcpxml-subtitle-aligner-release-test.* output directory"
    [[ -n "$test_prebuilt_app_binary" && -n "$test_prebuilt_cli_binary" && "$test_skip_fat_verification" == true ]] || die "test mode requires both prebuilt binaries and --test-skip-fat-verification"
    [[ -f "$test_prebuilt_app_binary" && -x "$test_prebuilt_app_binary" ]] || die "--test-prebuilt-app-binary must be executable"
    [[ -f "$test_prebuilt_cli_binary" && -x "$test_prebuilt_cli_binary" ]] || die "--test-prebuilt-cli-binary must be executable"
    test_prebuilt_app_binary="$(cd -- "$(dirname -- "$test_prebuilt_app_binary")" && pwd -P)/$(basename -- "$test_prebuilt_app_binary")"
    test_prebuilt_cli_binary="$(cd -- "$(dirname -- "$test_prebuilt_cli_binary")" && pwd -P)/$(basename -- "$test_prebuilt_cli_binary")"
fi

path_is_occupied "$output_dir_input" && die "refusing to overwrite occupied output destination: $output_dir_input"
if [[ ! -e "$output_parent_input" ]]; then
    mkdir -p -- "$output_parent_input"
fi
[[ -d "$output_parent_input" ]] || die "output parent must be a directory: $output_parent_input"
output_parent="$(cd -- "$output_parent_input" && pwd -P)"
output_dir="$output_parent/$output_leaf"
path_is_occupied "$output_dir" && die "refusing to overwrite occupied output destination: $output_dir"
if [[ "$test_mode" == true ]]; then
    [[ "$output_parent" == "$canonical_temp_root" ]] || die "test-only output parent did not canonicalize to /tmp"
fi

[[ -f "$build_app_script" && -x "$build_app_script" ]] || die "build_app.sh is unavailable or not executable"
[[ -f "$skill_source/SKILL.md" && -f "$skill_source/agents/openai.yaml" && -d "$skill_source/assets" ]] || die "skill source is incomplete"
[[ -z "$(find "$skill_source" -type l -print -quit)" ]] || die "skill source must not contain symlinks"

if [[ "$test_mode" == false ]]; then
    if [[ -z "$developer_dir" ]]; then
        if [[ -d /Applications/Xcode_16.2.app/Contents/Developer ]]; then
            developer_dir=/Applications/Xcode_16.2.app/Contents/Developer
        elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
            developer_dir=/Applications/Xcode.app/Contents/Developer
        else
            developer_dir="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
        fi
    fi
    [[ -d "$developer_dir" ]] || die "Xcode developer directory is unavailable: $developer_dir"
    export DEVELOPER_DIR="$developer_dir"
    swift_version="$(swift --version 2>&1)" || die "could not run Swift from $developer_dir"
    printf '%s\n' "$swift_version" | /usr/bin/grep -Eq 'Swift version 6\.' || die "Swift version 6 is required; selected: $swift_version"
    [[ -z "$(git -C "$source_root" status --porcelain --untracked-files=no)" ]] || die "refusing to package dirty tracked source"
fi

workspace=""
workspace_identity=""
workspace_name=""

workspace_is_owned() {
    [[ -n "$workspace" && -n "$workspace_identity" ]] && matches_identity "$workspace" "$workspace_identity"
}

remove_owned_workspace() {
    [[ -n "$workspace" ]] || return 0
    if workspace_is_owned; then
        rm -rf -- "$workspace"
        workspace=""
        workspace_identity=""
    else
        echo "build_release.sh: refusing to remove workspace that no longer has this process's inode: $workspace" >&2
    fi
}

cleanup() {
    remove_owned_workspace
}

trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

remove_owned_workspace_child() {
    local child="$1"
    workspace_is_owned || die "release workspace ownership changed"
    case "$child" in
        "$workspace/app-output"|"$workspace/cli-payload"|"$workspace/verify-app"|"$workspace/verify-cli"|"$workspace/verify-skill") ;;
        *) die "refusing to remove unexpected workspace child: $child" ;;
    esac
    [[ -d "$child" && ! -L "$child" ]] || die "expected workspace child is missing or unsafe: $child"
    rm -rf -- "$child"
}

remove_owned_workspace_marker() {
    local marker="$workspace/$workspace_marker_name"
    workspace_is_owned || die "release workspace ownership changed"
    [[ -f "$marker" && ! -L "$marker" && "$(<"$marker")" == "$workspace_marker_value" ]] || die "release workspace ownership marker changed"
    rm -- "$marker"
}

assert_no_appledouble_entries() {
    local listing="$1"
    local entry=""
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        [[ "$entry" != __MACOSX/* && "$entry" != *"/._"* ]] || die "archive contains AppleDouble junk: $entry"
    done <<< "$listing"
}

assert_zip_root() {
    local archive="$1"
    local root="$2"
    local listing=""
    local entry=""
    listing="$(/usr/bin/unzip -Z1 "$archive")" || die "could not list ZIP archive: $archive"
    assert_no_appledouble_entries "$listing"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        [[ "$entry" == "$root" || "$entry" == "$root/"* ]] || die "ZIP archive has unexpected root entry: $entry"
    done <<< "$listing"
}

assert_ad_hoc_signature() {
    local bundle="$1"
    local signature_details=""
    codesign --verify --deep --strict "$bundle"
    signature_details="$(codesign -dvv "$bundle" 2>&1)" || die "could not inspect app signing identity"
    printf '%s\n' "$signature_details" | /usr/bin/grep -Fx 'Signature=adhoc' >/dev/null || die "release app is not ad-hoc signed"
}

assert_exact_skill_archive_inventory() {
    local archive="$1"
    local actual=""
    local expected=""
    actual="$(/usr/bin/unzip -Z1 "$archive" | LC_ALL=C sort)" || die "could not list Skill archive"
    expected="$(printf '%s\n' \
        "fcpxml-subtitle-aligner/" \
        "fcpxml-subtitle-aligner/SKILL.md" \
        "fcpxml-subtitle-aligner/agents/" \
        "fcpxml-subtitle-aligner/agents/openai.yaml" \
        "fcpxml-subtitle-aligner/assets/" \
        "fcpxml-subtitle-aligner/assets/icon-400.png" \
        "fcpxml-subtitle-aligner/assets/logo.svg" | LC_ALL=C sort)"
    [[ "$actual" == "$expected" ]] || die "Skill archive inventory differs from the committed allowlist"
}

assert_final_inventory() {
    local directory="$1"
    local expected_name=""
    local entry=""
    local count=0
    for expected_name in "$app_archive_name" "$cli_archive_name" "$skill_archive_name" "SHA256SUMS"; do
        [[ -f "$directory/$expected_name" && ! -L "$directory/$expected_name" ]] || die "release asset is missing or unsafe: $expected_name"
    done
    while IFS= read -r entry; do
        count=$((count + 1))
        case "$(basename -- "$entry")" in
            "$app_archive_name"|"$cli_archive_name"|"$skill_archive_name"|SHA256SUMS) ;;
            *) die "release workspace contains unexpected entry: $entry" ;;
        esac
    done < <(find "$directory" -mindepth 1 -maxdepth 1 -print)
    [[ "$count" -eq 4 ]] || die "release workspace must contain exactly four assets"
}

workspace="$(mktemp -d "$output_parent/.fcpxml-subtitle-aligner-release-stage.XXXXXX")"
workspace_identity="$(lstat_identity "$workspace")" || die "could not capture release workspace identity"
workspace_name="$(basename -- "$workspace")"
printf '%s' "$workspace_marker_value" > "$workspace/$workspace_marker_name"

app_output="$workspace/app-output"
mkdir -- "$app_output"
if [[ "$test_mode" == true ]]; then
    "$build_app_script" --release-stage-parent "$app_output" --test-prebuilt-binary "$test_prebuilt_app_binary"
else
    (
        cd "$source_root"
        swift package clean
    )
    "$build_app_script" --release-stage-parent "$app_output"
    (
        cd "$source_root"
        swift build -c release --arch arm64 --arch x86_64 --product fcpxml-aligner
    )
fi

app_binary="$app_output/$app_name/Contents/MacOS/FCPXMLSubtitleAligner"
if [[ "$test_mode" == true ]]; then
    cli_binary="$test_prebuilt_cli_binary"
else
    binary_directory="$(cd "$source_root" && swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    cli_binary="$binary_directory/fcpxml-aligner"
fi
[[ -f "$app_binary" && -x "$app_binary" ]] || die "app executable was not produced"
[[ -f "$cli_binary" && -x "$cli_binary" ]] || die "CLI executable was not produced"
assert_ad_hoc_signature "$app_output/$app_name"
if [[ "$test_skip_fat_verification" == false ]]; then
    lipo "$app_binary" -verify_arch arm64 x86_64
    lipo "$cli_binary" -verify_arch arm64 x86_64
fi

app_archive_name="FCPXML-Subtitle-Aligner-${version}-macos-universal.zip"
cli_archive_name="fcpxml-aligner-${version}-macos-universal.tar.gz"
skill_archive_name="fcpxml-subtitle-aligner-skill-${version}.zip"
app_archive="$workspace/$app_archive_name"
cli_archive="$workspace/$cli_archive_name"
skill_archive="$workspace/$skill_archive_name"
source_date_epoch="$(git -C "$source_root" log -1 --format=%ct HEAD)" || die "could not determine committed source timestamp"

ditto -c -k --keepParent --norsrc "$app_output/$app_name" "$app_archive"
cli_payload="$workspace/cli-payload"
mkdir -- "$cli_payload"
install -m 755 "$cli_binary" "$cli_payload/fcpxml-aligner"
COPYFILE_DISABLE=1 SOURCE_DATE_EPOCH="$source_date_epoch" tar --format=ustar --uid 0 --gid 0 --numeric-owner --no-xattrs -czf "$cli_archive" -C "$cli_payload" fcpxml-aligner
git archive --format=zip --prefix=fcpxml-subtitle-aligner/ HEAD:skills/fcpxml-subtitle-aligner > "$skill_archive"

assert_zip_root "$app_archive" "$app_name"
app_listing="$(/usr/bin/unzip -Z1 "$app_archive")" || die "could not list app archive"
printf '%s\n' "$app_listing" | /usr/bin/grep -Fx "$app_name/Contents/MacOS/FCPXMLSubtitleAligner" >/dev/null || die "app archive has no app executable"
verify_app="$workspace/verify-app"
mkdir -- "$verify_app"
ditto -x -k "$app_archive" "$verify_app"
[[ -x "$verify_app/$app_name/Contents/MacOS/FCPXMLSubtitleAligner" ]] || die "app archive did not preserve executable mode"
assert_ad_hoc_signature "$verify_app/$app_name"

cli_listing="$(tar -tzf "$cli_archive")" || die "could not list CLI archive"
assert_no_appledouble_entries "$cli_listing"
[[ "$cli_listing" == "fcpxml-aligner" ]] || die "CLI archive must contain only fcpxml-aligner"
verify_cli="$workspace/verify-cli"
mkdir -- "$verify_cli"
tar -xzf "$cli_archive" -C "$verify_cli"
[[ -x "$verify_cli/fcpxml-aligner" ]] || die "CLI archive did not preserve executable mode"

assert_zip_root "$skill_archive" "fcpxml-subtitle-aligner"
assert_exact_skill_archive_inventory "$skill_archive"
skill_listing="$(/usr/bin/unzip -Z1 "$skill_archive")" || die "could not list Skill archive"
for required_skill_path in \
    "fcpxml-subtitle-aligner/SKILL.md" \
    "fcpxml-subtitle-aligner/agents/openai.yaml" \
    "fcpxml-subtitle-aligner/assets/logo.svg" \
    "fcpxml-subtitle-aligner/assets/icon-400.png"; do
    printf '%s\n' "$skill_listing" | /usr/bin/grep -Fx "$required_skill_path" >/dev/null || die "Skill archive is missing $required_skill_path"
done
verify_skill="$workspace/verify-skill"
mkdir -- "$verify_skill"
ditto -x -k "$skill_archive" "$verify_skill"
[[ -s "$verify_skill/fcpxml-subtitle-aligner/SKILL.md" ]] || die "Skill archive has no readable SKILL.md"
/usr/bin/head -n 1 "$verify_skill/fcpxml-subtitle-aligner/SKILL.md" | /usr/bin/grep -Fx -- '---' >/dev/null || die "Skill frontmatter is invalid"
/usr/bin/grep -Fx -- 'name: fcpxml-subtitle-aligner' "$verify_skill/fcpxml-subtitle-aligner/SKILL.md" >/dev/null || die "Skill name is invalid"

(
    cd "$workspace"
    printf '%s\n' "$app_archive_name" "$cli_archive_name" "$skill_archive_name" | LC_ALL=C sort | while IFS= read -r archive_name; do
        shasum -a 256 "$archive_name"
    done > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
)

remove_owned_workspace_child "$app_output"
remove_owned_workspace_child "$cli_payload"
remove_owned_workspace_child "$verify_app"
remove_owned_workspace_child "$verify_cli"
remove_owned_workspace_child "$verify_skill"
remove_owned_workspace_marker
assert_final_inventory "$workspace"

if [[ "$test_inject_post_stage_failure" == true ]]; then
    die "injected test-only failure after release staging"
fi

path_is_occupied "$output_dir" && die "output destination appeared during release staging"
if ! mv "$workspace" "$output_dir"; then
    die "could not publish complete release directory"
fi
if [[ -d "$output_dir/$workspace_name" ]] && matches_identity "$output_dir/$workspace_name" "$workspace_identity"; then
    workspace="$output_dir/$workspace_name"
    die "output destination appeared during publish; removed only the owned nested workspace"
fi
matches_identity "$output_dir" "$workspace_identity" || die "published release directory does not have the staged workspace inode"
workspace=""
workspace_identity=""

echo "Built ad-hoc signed, unnotarized developer build release $output_dir"
