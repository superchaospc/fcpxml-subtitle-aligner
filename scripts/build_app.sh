#!/bin/bash
set -euo pipefail

developer_dir="${DEVELOPER_DIR:-}"
app_name="FCPXML Subtitle Aligner.app"
bundle_identifier="local.codex.fcpxml-subtitle-aligner"
owner_marker_name=".fcpxml-subtitle-aligner-owner"

die() {
    echo "build_app.sh: $*" >&2
    exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_root="$(cd "$script_dir/.." && pwd -P)"
default_output_parent="$(cd "$source_root/.." && pwd -P)/outputs"
info_plist="$source_root/Resources/Info.plist"

test_mode=false
test_output_parent=""
test_prebuilt_binary=""
release_stage_parent=""
release_stage_owner_marker_name=".fcpxml-subtitle-aligner-release-stage-owner"
release_stage_owner_marker_value="local.codex.fcpxml-subtitle-aligner.release-stage"
inject_publish_failure=false
inject_destination_replacement_before_backup_move=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --test-output-parent)
            [[ $# -ge 2 ]] || die "--test-output-parent requires a path"
            test_mode=true
            test_output_parent="$2"
            shift 2
            ;;
        --test-prebuilt-binary)
            [[ $# -ge 2 ]] || die "--test-prebuilt-binary requires a path"
            test_prebuilt_binary="$2"
            shift 2
            ;;
        --release-stage-parent)
            [[ $# -ge 2 ]] || die "--release-stage-parent requires a path"
            release_stage_parent="$2"
            shift 2
            ;;
        --test-inject-publish-failure)
            inject_publish_failure=true
            shift
            ;;
        --test-inject-destination-replacement-before-backup-move)
            inject_destination_replacement_before_backup_move=true
            shift
            ;;
        *) die "unknown argument: $1" ;;
    esac
done

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
[[ -f "$source_root/Package.swift" ]] || die "Package.swift was not found under $source_root"
[[ -f "$info_plist" ]] || die "Info.plist was not found under $source_root"

if [[ "$test_mode" == true ]]; then
    [[ -z "$release_stage_parent" ]] || die "--test-output-parent cannot be combined with --release-stage-parent"
    [[ -n "$test_output_parent" ]] || die "test mode requires --test-output-parent"
    [[ "$test_output_parent" == /* && -d "$test_output_parent" ]] || die "test output parent must be an existing absolute directory"
    canonical_temp_root="$(cd -- /tmp && pwd -P)" || die "could not canonicalize /tmp"
    canonical_test_output_parent="$(cd -- "$test_output_parent" && pwd -P)" || die "could not canonicalize test output parent"
    test_output_parent_parent="$(dirname "$canonical_test_output_parent")"
    test_output_parent_name="$(basename "$canonical_test_output_parent")"
    [[ "$test_output_parent_parent" == "$canonical_temp_root" ]] || die "test output parent must be a direct child of $canonical_temp_root"
    case "$test_output_parent_name" in
        fcpxml-subtitle-aligner-packaging-test.?*) ;;
        *) die "test output parent must have a unique fcpxml-subtitle-aligner-packaging-test. prefix" ;;
    esac
    [[ -n "$test_prebuilt_binary" && -f "$test_prebuilt_binary" && -x "$test_prebuilt_binary" ]] || die "test mode requires an executable file --test-prebuilt-binary"
    test_prebuilt_binary="$(cd -- "$(dirname -- "$test_prebuilt_binary")" && pwd -P)/$(basename -- "$test_prebuilt_binary")"
    output_parent="$canonical_test_output_parent"
elif [[ -n "$release_stage_parent" ]]; then
    [[ "$release_stage_parent" == /* && -d "$release_stage_parent" && ! -L "$release_stage_parent" ]] || die "release stage parent must be an existing absolute directory"
    release_stage_parent="$(cd -- "$release_stage_parent" && pwd -P)"
    [[ "$(basename -- "$release_stage_parent")" == "app-output" ]] || die "release stage parent must be named app-output"
    release_workspace="$(dirname -- "$release_stage_parent")"
    release_owner_marker="$release_workspace/$release_stage_owner_marker_name"
    [[ -d "$release_workspace" && ! -L "$release_workspace" && -f "$release_owner_marker" && ! -L "$release_owner_marker" ]] || die "release stage workspace is not owned by build_release.sh"
    [[ "$(<"$release_owner_marker")" == "$release_stage_owner_marker_value" ]] || die "release stage workspace ownership marker is invalid"
    [[ -z "$(find "$release_stage_parent" -mindepth 1 -maxdepth 1 -print -quit)" ]] || die "release stage parent must be empty"
    if [[ -n "$test_prebuilt_binary" ]]; then
        test_mode=true
        canonical_temp_root="$(cd -- /tmp && pwd -P)" || die "could not canonicalize /tmp"
        [[ "$(dirname -- "$release_workspace")" == "$canonical_temp_root" && "$(basename -- "$release_workspace")" == .fcpxml-subtitle-aligner-release-stage.* ]] || die "test prebuilt binary requires a canonical release test workspace"
        [[ -f "$test_prebuilt_binary" && -x "$test_prebuilt_binary" ]] || die "test mode requires an executable file --test-prebuilt-binary"
        test_prebuilt_binary="$(cd -- "$(dirname -- "$test_prebuilt_binary")" && pwd -P)/$(basename -- "$test_prebuilt_binary")"
    else
        [[ "$inject_publish_failure" == false && "$inject_destination_replacement_before_backup_move" == false ]] || die "test-only options require a test prebuilt binary"
    fi
    output_parent="$release_stage_parent"
else
    [[ -z "$test_prebuilt_binary" && "$inject_publish_failure" == false && "$inject_destination_replacement_before_backup_move" == false ]] || die "test-only options require --test-output-parent"
    output_parent="$default_output_parent"
    mkdir -p "$output_parent"
fi

[[ -d "$output_parent" ]] || die "output directory is unavailable: $output_parent"
destination="$output_parent/$app_name"
stage_directory=""
stage_app=""
backup_directory=""
backup_identity=""
backup_verified_owned=false
preserve_backup=false
test_race_original_directory=""

path_is_occupied() {
    [[ -e "$1" || -L "$1" ]]
}

is_owned_bundle() {
    local bundle="$1"
    [[ -d "$bundle" && ! -L "$bundle" && -f "$bundle/Contents/Resources/$owner_marker_name" ]] || return 1
    [[ "$(<"$bundle/Contents/Resources/$owner_marker_name")" == "$bundle_identifier" ]]
}

lstat_identity() {
    /usr/bin/stat -f '%d:%i:%HT' "$1"
}

matches_identity() {
    local path="$1"
    local expected_identity="$2"
    [[ -n "$expected_identity" && -e "$path" && "$(lstat_identity "$path")" == "$expected_identity" ]]
}

safe_remove_temporary_directory() {
    local path="$1"
    case "$path" in
        "$output_parent"/.fcpxml-subtitle-aligner-stage.*)
            [[ -d "$path" ]] && rm -rf -- "$path"
            ;;
        *) echo "build_app.sh: refusing to remove unexpected temporary path: $path" >&2; return 1 ;;
    esac
}

preserve_backup_for_recovery() {
    [[ -n "$backup_directory" ]] || return 0
    preserve_backup=true
    echo "build_app.sh: preserved unverified backup for manual recovery: $backup_directory" >&2
}

backup_matches_expected_identity_and_owner() {
    local backup_app=""
    [[ -n "$backup_directory" && -n "$backup_identity" ]] || return 1
    backup_app="$backup_directory/$app_name"
    matches_identity "$backup_app" "$backup_identity" && is_owned_bundle "$backup_app"
}

verified_backup_is_intact() {
    [[ "$backup_verified_owned" == true ]] && backup_matches_expected_identity_and_owner
}

restore_owned_backup_if_possible() {
    local backup_app=""
    verified_backup_is_intact || return 1
    backup_app="$backup_directory/$app_name"
    ! path_is_occupied "$destination" || return 1
    mv "$backup_app" "$destination" || return 1
    matches_identity "$destination" "$backup_identity" && is_owned_bundle "$destination"
}

discard_verified_backup_if_possible() {
    local backup_app=""
    verified_backup_is_intact || return 1
    backup_app="$backup_directory/$app_name"
    rm -rf -- "$backup_app"
    rmdir -- "$backup_directory"
}

restore_test_race_original_if_possible() {
    local original_app=""
    [[ -n "$test_race_original_directory" ]] || return 0
    original_app="$test_race_original_directory/$app_name"
    if ! path_is_occupied "$destination" && matches_identity "$original_app" "$backup_identity" && is_owned_bundle "$original_app"; then
        mv "$original_app" "$destination" || return 1
        if matches_identity "$destination" "$backup_identity" && is_owned_bundle "$destination"; then
            rmdir -- "$test_race_original_directory" || true
            test_race_original_directory=""
            return 0
        fi
    fi
    echo "build_app.sh: preserved test race original for manual recovery: $test_race_original_directory" >&2
    return 1
}

cleanup() {
    if [[ -n "$stage_directory" && -d "$stage_directory" ]]; then
        safe_remove_temporary_directory "$stage_directory" || true
    fi
    if [[ -n "$backup_directory" && -d "$backup_directory" && "$preserve_backup" == false ]]; then
        if path_is_occupied "$destination"; then
            if path_is_occupied "$backup_directory/$app_name"; then
                discard_verified_backup_if_possible || preserve_backup_for_recovery
            else
                rmdir -- "$backup_directory" || preserve_backup_for_recovery
            fi
        elif restore_owned_backup_if_possible; then
            rmdir -- "$backup_directory" || preserve_backup_for_recovery
        else
            preserve_backup_for_recovery
        fi
    fi
}
trap cleanup EXIT

if path_is_occupied "$destination" && ! is_owned_bundle "$destination"; then
    die "refusing to replace unowned output destination: $destination"
fi

stage_directory="$(mktemp -d "$output_parent/.fcpxml-subtitle-aligner-stage.XXXXXX")"
stage_app="$stage_directory/$app_name"

if [[ "$test_mode" == true ]]; then
    binary="$test_prebuilt_binary"
else
    cd "$source_root"
    swift build -c release --arch arm64 --arch x86_64
    binary_directory="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
    binary="$binary_directory/FCPXMLSubtitleAligner"
    lipo "$binary" -verify_arch arm64 x86_64
fi
[[ -f "$binary" ]] || die "release executable was not produced: $binary"

mkdir -p "$stage_app/Contents/MacOS" "$stage_app/Contents/Resources"
install -m 755 "$binary" "$stage_app/Contents/MacOS/FCPXMLSubtitleAligner"
install -m 644 "$info_plist" "$stage_app/Contents/Info.plist"
printf '%s' "$bundle_identifier" > "$stage_app/Contents/Resources/$owner_marker_name"
plutil -lint "$stage_app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$stage_app"
codesign --verify --deep --strict "$stage_app"

if path_is_occupied "$destination"; then
    is_owned_bundle "$destination" || die "refusing to replace unowned output destination: $destination"
    destination_identity="$(lstat_identity "$destination")" || die "could not capture destination identity before replacement"
    [[ -n "$destination_identity" ]] || die "could not capture destination identity before replacement"
    if [[ "$inject_destination_replacement_before_backup_move" == true ]]; then
        test_race_original_directory="$(mktemp -d "$output_parent/.fcpxml-subtitle-aligner-race-original.XXXXXX")"
        mv "$destination" "$test_race_original_directory/$app_name"
        mkdir "$destination"
        printf '%s' 'simulated intruder' > "$destination/.fcpxml-subtitle-aligner-race-intruder"
    fi
    backup_directory="$(mktemp -d "$output_parent/.fcpxml-subtitle-aligner-backup.XXXXXX")"
    mv "$destination" "$backup_directory/$app_name"
    backup_identity="$destination_identity"
    if ! backup_matches_expected_identity_and_owner; then
        restore_test_race_original_if_possible || true
        preserve_backup_for_recovery
        die "refusing to publish because the moved destination changed or is no longer tool-owned"
    fi
    backup_verified_owned=true
fi

if path_is_occupied "$destination"; then
    preserve_backup=true
    die "destination appeared while publishing; preserved the owned backup"
fi

if [[ "$inject_publish_failure" == true ]]; then
    restore_owned_backup_if_possible
    die "injected test-only publish failure"
fi

if ! mv "$stage_app" "$destination"; then
    restore_owned_backup_if_possible || true
    die "could not publish staged app bundle"
fi

echo "Built $destination"
