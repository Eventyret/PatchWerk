#!/usr/bin/env bash
# check-versions.sh — Compare PatchWerk targetVersion fields against installed addon TOC versions
#
# Usage:
#   tools/check-versions.sh              Show version comparison for all groups
#   tools/check-versions.sh --update GroupName   Update targetVersion in patch file after verification
#   tools/check-versions.sh --create-issues      Create GitHub issues for mismatches via gh CLI
#   tools/check-versions.sh --json               Output results as JSON to tools/versions.json
#
# Requires: bash, awk, sed
# Optional: gh (GitHub CLI) for --create-issues

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADDON_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ADDONS_ROOT="$(cd "$ADDON_DIR/.." && pwd)"

PATCHES_DIR="$ADDON_DIR/Patches"
VERSIONS_JSON="$SCRIPT_DIR/versions.json"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    DIM='\033[0;90m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' DIM='' BOLD='' RESET=''
fi

# Map PatchWerk group ID -> actual addon folder name
# Most groups match their folder name, but some differ.
declare -A GROUP_TO_FOLDER=(
    [Details]="Details"
    [Plater]="Plater"
    [Pawn]="Pawn"
    [TipTac]="TipTac"
    [Questie]="Questie"
    [LFGBulletinBoard]="LFGBulletinBoard"
    [Bartender4]="Bartender4"
    [TitanPanel]="Titan"
    [OmniCC]="OmniCC"
    [Prat]="Prat-3.0"
    [GatherMate2]="GatherMate2"
    [Quartz]="Quartz"
    [Auctionator]="Auctionator"
    [VuhDo]="VuhDo"
    [Cell]="Cell"
    [BigDebuffs]="BigDebuffs"
    [EasyFrames]="EasyFrames"
    [BugSack]="BugSack"
    [LoonBestInSlot]="LoonBestInSlot"
    [NovaInstanceTracker]="NovaInstanceTracker"
    [AutoLayer]="AutoLayer_Vanilla"
    [AtlasLootClassic]="AtlasLootClassic"
    [BigWigs]="BigWigs"
    [Gargul]="Gargul"
    [SexyMap]="SexyMap"
    [MoveAny]="MoveAny"
    [Attune]="Attune"
    [NovaWorldBuffs]="NovaWorldBuffs"
)

# Extract the first targetVersion for each group from patch files
declare -A GROUP_TARGET_VERSION
extract_target_versions() {
    for lua_file in "$PATCHES_DIR"/*.lua; do
        [ -f "$lua_file" ] || continue

        # Extract group and targetVersion pairs using awk
        awk '
            /group *= *"/ {
                match($0, /group *= *"([^"]+)"/, g)
                group = g[1]
            }
            /targetVersion *= *"/ {
                match($0, /targetVersion *= *"([^"]+)"/, v)
                if (group != "" && !seen[group]) {
                    print group "\t" v[1]
                    seen[group] = 1
                }
                group = ""
            }
        ' "$lua_file"
    done
}

while IFS=$'\t' read -r group version; do
    GROUP_TARGET_VERSION["$group"]="$version"
done < <(extract_target_versions)

# Resolve TOC file for an addon folder. Tries TBC-specific suffixes first.
resolve_toc() {
    local folder="$1"
    local base="$ADDONS_ROOT/$folder"

    # Try TBC Classic specific TOC files first
    for suffix in "_TBC" "-BCC" "-TBC" ""; do
        local toc="$base/${folder}${suffix}.toc"
        if [ -f "$toc" ]; then
            echo "$toc"
            return 0
        fi
    done

    # Try any .toc file in the directory
    local any_toc
    any_toc=$(find "$base" -maxdepth 1 -name "*.toc" -print -quit 2>/dev/null || true)
    if [ -n "$any_toc" ]; then
        echo "$any_toc"
        return 0
    fi

    return 1
}

# Read version from a TOC file
read_toc_version() {
    local toc_file="$1"
    awk -F': *' '/^## *Version:/ { gsub(/\r/, "", $2); print $2; exit }' "$toc_file"
}

# ─── Main comparison logic ────────────────────────────────────────────────

do_compare() {
    local matches=0 mismatches=0 missing=0 skipped=0
    local json_entries=()
    local mismatch_groups=()

    printf "${BOLD}PatchWerk Version Check${RESET}\n"
    printf "${DIM}Comparing targetVersion fields against installed addon TOCs${RESET}\n\n"

    # Sort group names for consistent output
    local sorted_groups
    sorted_groups=$(printf '%s\n' "${!GROUP_TO_FOLDER[@]}" | sort)

    while IFS= read -r group; do
        local folder="${GROUP_TO_FOLDER[$group]}"
        local target="${GROUP_TARGET_VERSION[$group]:-}"

        # No targetVersion in patch file
        if [ -z "$target" ]; then
            printf "  ${DIM}[SKIP]${RESET}  %-24s %s\n" "$group" "no targetVersion defined"
            skipped=$((skipped + 1))
            json_entries+=("{\"group\":\"$group\",\"status\":\"skip\",\"reason\":\"no targetVersion\"}")
            continue
        fi

        # Addon folder doesn't exist
        if [ ! -d "$ADDONS_ROOT/$folder" ]; then
            printf "  ${DIM}[MISSING]${RESET} %-24s %s\n" "$group" "addon not installed ($folder)"
            missing=$((missing + 1))
            json_entries+=("{\"group\":\"$group\",\"status\":\"missing\",\"folder\":\"$folder\",\"targetVersion\":\"$target\"}")
            continue
        fi

        # Resolve and read TOC
        local toc_file
        if ! toc_file=$(resolve_toc "$folder"); then
            printf "  ${YELLOW}[MISSING]${RESET} %-24s %s\n" "$group" "no TOC found in $folder"
            missing=$((missing + 1))
            json_entries+=("{\"group\":\"$group\",\"status\":\"missing\",\"folder\":\"$folder\",\"targetVersion\":\"$target\"}")
            continue
        fi

        local installed
        installed=$(read_toc_version "$toc_file")

        if [ -z "$installed" ]; then
            printf "  ${YELLOW}[MISSING]${RESET} %-24s %s\n" "$group" "no version in TOC"
            missing=$((missing + 1))
            json_entries+=("{\"group\":\"$group\",\"status\":\"missing\",\"folder\":\"$folder\",\"targetVersion\":\"$target\"}")
            continue
        fi

        if [ "$installed" = "$target" ]; then
            printf "  ${GREEN}[MATCH]${RESET}   %-24s %s\n" "$group" "$installed"
            matches=$((matches + 1))
            json_entries+=("{\"group\":\"$group\",\"status\":\"match\",\"version\":\"$installed\"}")
        else
            printf "  ${RED}[MISMATCH]${RESET} %-24s target: ${DIM}%s${RESET}  installed: ${CYAN}%s${RESET}\n" \
                "$group" "$target" "$installed"
            mismatches=$((mismatches + 1))
            mismatch_groups+=("$group")
            json_entries+=("{\"group\":\"$group\",\"status\":\"mismatch\",\"targetVersion\":\"$target\",\"installedVersion\":\"$installed\"}")
        fi
    done <<< "$sorted_groups"

    printf "\n${BOLD}Summary:${RESET} "
    printf "${GREEN}%d match${RESET}, " "$matches"
    printf "${RED}%d mismatch${RESET}, " "$mismatches"
    printf "${DIM}%d missing, %d skipped${RESET}\n" "$missing" "$skipped"

    # Write JSON manifest
    if [ "$WRITE_JSON" = "true" ]; then
        printf "[\n" > "$VERSIONS_JSON"
        local first=true
        for entry in "${json_entries[@]}"; do
            if [ "$first" = "true" ]; then
                first=false
            else
                printf ",\n" >> "$VERSIONS_JSON"
            fi
            printf "  %s" "$entry" >> "$VERSIONS_JSON"
        done
        printf "\n]\n" >> "$VERSIONS_JSON"
        printf "\n${DIM}Manifest written to: tools/versions.json${RESET}\n"
    fi

    # Store mismatch groups for --create-issues
    MISMATCH_GROUPS=("${mismatch_groups[@]+"${mismatch_groups[@]}"}")
}

# ─── --update GroupName ───────────────────────────────────────────────────

do_update() {
    local group="$1"
    local folder="${GROUP_TO_FOLDER[$group]:-}"

    if [ -z "$folder" ]; then
        printf "${RED}Error:${RESET} Unknown group: %s\n" "$group" >&2
        printf "Valid groups: %s\n" "$(printf '%s\n' "${!GROUP_TO_FOLDER[@]}" | sort | tr '\n' ', ')" >&2
        exit 1
    fi

    local toc_file
    if ! toc_file=$(resolve_toc "$folder"); then
        printf "${RED}Error:${RESET} No TOC found for %s (%s)\n" "$group" "$folder" >&2
        exit 1
    fi

    local installed
    installed=$(read_toc_version "$toc_file")
    if [ -z "$installed" ]; then
        printf "${RED}Error:${RESET} No version in TOC for %s\n" "$folder" >&2
        exit 1
    fi

    local old_target="${GROUP_TARGET_VERSION[$group]:-}"
    if [ -z "$old_target" ]; then
        printf "${RED}Error:${RESET} No targetVersion found in patch file for group %s\n" "$group" >&2
        exit 1
    fi

    if [ "$installed" = "$old_target" ]; then
        printf "${GREEN}Already up to date:${RESET} %s = %s\n" "$group" "$installed"
        exit 0
    fi

    # Find the patch file for this group
    local patch_file=""
    for lua_file in "$PATCHES_DIR"/*.lua; do
        if grep -q "group *= *\"$group\"" "$lua_file" 2>/dev/null; then
            patch_file="$lua_file"
            break
        fi
    done

    if [ -z "$patch_file" ]; then
        printf "${RED}Error:${RESET} No patch file found for group %s\n" "$group" >&2
        exit 1
    fi

    printf "Updating ${BOLD}%s${RESET}: %s -> %s\n" "$group" "$old_target" "$installed"
    printf "  File: %s\n" "$(basename "$patch_file")"

    # Escape special characters for sed
    local escaped_old escaped_new
    escaped_old=$(printf '%s' "$old_target" | sed 's/[&/\]/\\&/g; s/\./\\./g')
    escaped_new=$(printf '%s' "$installed" | sed 's/[&/\]/\\&/g')

    sed -i "s/targetVersion *= *\"${escaped_old}\"/targetVersion = \"${escaped_new}\"/g" "$patch_file"

    local count
    count=$(grep -c "targetVersion = \"$installed\"" "$patch_file" || true)
    printf "  ${GREEN}Updated %d targetVersion entries${RESET}\n" "$count"
}

# ─── --create-issues ──────────────────────────────────────────────────────

do_create_issues() {
    if ! command -v gh &>/dev/null; then
        printf "${YELLOW}Warning:${RESET} gh (GitHub CLI) not found. Install it to create issues automatically.\n" >&2
        printf "  https://cli.github.com/\n" >&2
        exit 1
    fi

    if [ ${#MISMATCH_GROUPS[@]} -eq 0 ]; then
        printf "${GREEN}No mismatches found — nothing to report.${RESET}\n"
        exit 0
    fi

    printf "\n${BOLD}Creating GitHub issues for %d mismatched groups...${RESET}\n\n" "${#MISMATCH_GROUPS[@]}"

    for group in "${MISMATCH_GROUPS[@]}"; do
        local folder="${GROUP_TO_FOLDER[$group]}"
        local target="${GROUP_TARGET_VERSION[$group]}"
        local toc_file installed

        toc_file=$(resolve_toc "$folder") || continue
        installed=$(read_toc_version "$toc_file")

        local title="[Outdated]: $group updated from $target to $installed"

        # Check for existing open issue with same title (deduplication)
        local existing
        existing=$(gh issue list --state open --search "$group updated" --json title --jq '.[].title' 2>/dev/null || true)
        if echo "$existing" | grep -qF "$title"; then
            printf "  ${DIM}[EXISTS]${RESET} %s — skipping\n" "$group"
            continue
        fi

        local body
        body=$(cat <<EOF
## Outdated Patch Report

**Addon:** $group
**Addon folder:** $folder
**Previous version (targetVersion):** $target
**Installed version:** $installed

This was auto-detected by \`tools/check-versions.sh --create-issues\`.

### Next steps
1. Test the patched addon in-game to verify patches still work
2. If patches still work: \`tools/check-versions.sh --update $group\`
3. If patches are broken: update the patch code, then update targetVersion
4. If patches are no longer needed: remove them
EOF
        )

        if gh issue create --title "$title" --body "$body" --label "outdated-patch" 2>/dev/null; then
            printf "  ${GREEN}[CREATED]${RESET} %s\n" "$group"
        else
            printf "  ${RED}[FAILED]${RESET}  %s — could not create issue\n" "$group" >&2
        fi
    done
}

# ─── CLI argument parsing ─────────────────────────────────────────────────

WRITE_JSON="false"
ACTION="compare"
UPDATE_GROUP=""
MISMATCH_GROUPS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --update)
            ACTION="update"
            if [ -z "${2:-}" ]; then
                printf "${RED}Error:${RESET} --update requires a group name\n" >&2
                exit 1
            fi
            UPDATE_GROUP="$2"
            shift 2
            ;;
        --create-issues)
            ACTION="create-issues"
            shift
            ;;
        --json)
            WRITE_JSON="true"
            shift
            ;;
        --help|-h)
            printf "Usage: %s [OPTIONS]\n\n" "$(basename "$0")"
            printf "Options:\n"
            printf "  (no args)           Show version comparison for all groups\n"
            printf "  --update <Group>    Update targetVersion in patch file\n"
            printf "  --create-issues     Create GitHub issues for mismatches\n"
            printf "  --json              Write results to tools/versions.json\n"
            printf "  --help              Show this help\n"
            exit 0
            ;;
        *)
            printf "${RED}Error:${RESET} Unknown option: %s\n" "$1" >&2
            exit 1
            ;;
    esac
done

case "$ACTION" in
    compare)
        WRITE_JSON="true"
        do_compare
        ;;
    update)
        do_update "$UPDATE_GROUP"
        ;;
    create-issues)
        do_compare
        do_create_issues
        ;;
esac
