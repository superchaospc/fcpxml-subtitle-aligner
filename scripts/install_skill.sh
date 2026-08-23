#!/usr/bin/env bash
set -euo pipefail

fail() {
    printf 'install_skill.sh: %s\n' "$*" >&2
    exit 1
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source_path="$script_dir/../skills/fcpxml-subtitle-aligner"
home_path=""
home_supplied=false

usage() {
    cat >&2 <<'USAGE'
Usage: install_skill.sh [--source <dir>] [--home <dir>]
USAGE
}

while (($# > 0)); do
    case "$1" in
        --source)
            (($# >= 2)) || { usage; fail "--source requires a directory"; }
            source_path="$2"
            shift 2
            ;;
        --home)
            (($# >= 2)) || { usage; fail "--home requires a directory"; }
            home_path="$2"
            home_supplied=true
            shift 2
            ;;
        -h|--help)
            usage >&1
            exit 0
            ;;
        *)
            usage
            fail "unknown argument: $1"
            ;;
    esac
done

if [[ "$home_supplied" == true ]]; then
    [[ -n "$home_path" ]] || fail "explicit --home directory must not be empty"
else
    home_path="${HOME:?HOME must be set}"
fi

case "/$home_path/" in
    */./*|*/../*) fail "home path must not contain '.' or '..' components: $home_path" ;;
esac

[[ -d "$source_path" ]] || fail "source directory does not exist: $source_path"
[[ -r "$source_path" ]] || fail "source directory is not readable: $source_path"
[[ -f "$source_path/SKILL.md" ]] || fail "source SKILL.md does not exist: $source_path/SKILL.md"
[[ -r "$source_path/SKILL.md" ]] || fail "source SKILL.md is not readable: $source_path/SKILL.md"

canonical_source="$(cd "$source_path" && pwd -P)" \
    || fail "could not canonicalize source directory: $source_path"

if [[ "$home_path" != /* ]]; then
    home_path="$PWD/$home_path"
fi

missing_home_components=()
existing_home_path="$home_path"
while [[ ! -e "$existing_home_path" && ! -L "$existing_home_path" ]]; do
    missing_home_components+=("$(basename "$existing_home_path")")
    existing_home_path="$(dirname "$existing_home_path")"
done
[[ -d "$existing_home_path" ]] || fail "home path is not a directory: $home_path"
canonical_home="$(cd "$existing_home_path" && pwd -P)" \
    || fail "could not canonicalize home directory: $home_path"
for ((index = ${#missing_home_components[@]} - 1; index >= 0; index--)); do
    canonical_home="$canonical_home/${missing_home_components[$index]}"
done

destination_relatives=(
    ".codex/skills/fcpxml-subtitle-aligner"
    ".agents/skills/fcpxml-subtitle-aligner"
    ".claude/skills/fcpxml-subtitle-aligner"
)
destinations=()

ensure_directory_chain() {
    local path="$1"
    local current="/"
    local component
    local components=()
    IFS="/" read -r -a components <<< "${path#/}"
    for component in "${components[@]}"; do
        [[ -n "$component" ]] || continue
        current="$current$component"
        if [[ -L "$current" ]]; then
            fail "refusing symlink ancestor: $current"
        elif [[ -e "$current" ]]; then
            [[ -d "$current" ]] || fail "refusing non-directory ancestor: $current"
        else
            mkdir "$current" || fail "could not create directory: $current"
        fi
        current="$current/"
    done
}

preflight_ancestors() {
    local destination="$1"
    local relative="${destination#"$canonical_home/"}"
    local current="$canonical_home"
    local component
    local components=()
    IFS="/" read -r -a components <<< "$relative"
    for component in "${components[@]}"; do
        [[ "$component" == "fcpxml-subtitle-aligner" ]] && break
        current="$current/$component"
        if [[ -L "$current" ]]; then
            fail "refusing symlink ancestor: $current"
        elif [[ -e "$current" ]]; then
            [[ -d "$current" ]] || fail "refusing non-directory ancestor: $current"
        else
            return 0
        fi
    done
}

canonical_link_target() {
    local link="$1"
    local target
    target="$(readlink "$link")" \
        || return 1
    if [[ "$target" != /* ]]; then
        target="$(dirname "$link")/$target"
    fi
    (cd "$target" && pwd -P)
}

is_path_inside_source() {
    local path="$1"
    [[ "$path" == "$canonical_source" || "$path" == "$canonical_source"/* ]]
}

# Preflight every destination before changing any of them. This prevents a
# later refusal from leaving a partially installed set of links.
for relative in "${destination_relatives[@]}"; do
    destination="$canonical_home/$relative"
    destinations+=("$destination")

    if is_path_inside_source "$destination"; then
        fail "refusing destination inside source directory: $destination"
    fi

    preflight_ancestors "$destination"
    if [[ -L "$destination" ]]; then
        existing_target="$(canonical_link_target "$destination")" \
            || fail "refusing dangling or unreadable symlink: $destination"
        [[ "$existing_target" == "$canonical_source" ]] \
            || fail "refusing symlink to another source: $destination"
    elif [[ -e "$destination" ]]; then
        fail "refusing occupied destination: $destination"
    fi
done

# All destination and ancestor checks are complete. Only now create the
# selected home and missing destination parents.
ensure_directory_chain "$canonical_home"

for destination in "${destinations[@]}"; do
    parent="${destination%/*}"
    ensure_directory_chain "$parent"

    # Re-check before accepting an existing link so a race cannot turn this
    # narrowly permitted idempotent path into an overwrite of another object.
    if [[ -L "$destination" ]]; then
        existing_target="$(canonical_link_target "$destination")" \
            || fail "refusing changed or unreadable symlink: $destination"
        [[ "$existing_target" == "$canonical_source" ]] \
            || fail "refusing symlink to another source: $destination"
        printf 'Installed %s -> %s\n' "$destination" "$canonical_source"
        continue
    elif [[ -e "$destination" ]]; then
        fail "refusing occupied destination: $destination"
    fi

    ln -s "$canonical_source" "$destination" \
        || fail "could not install symlink: $destination"
    printf 'Installed %s -> %s\n' "$destination" "$canonical_source"
done
