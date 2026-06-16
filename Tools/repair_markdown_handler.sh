#!/bin/zsh
set -euo pipefail

APP_PATH="/Applications/MDViewer.app"
BUNDLE_ID="com.meyfroidt.mdviewer"
CONTENT_TYPE="net.daringfireball.markdown"
UNREGISTER_DUPLICATES=1
GARBAGE_COLLECT=1
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SWIFT_MODULE_CACHE="${TMPDIR:-/tmp}/mdviewer-swift-module-cache"

typeset -A FOUND_APP_PATHS

LSREGISTER_CANDIDATES=(
    "/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
)

usage() {
    print -r -- "Usage: Tools/repair_markdown_handler.sh [options] [path/to/MDViewer.app]"
    print -r -- ""
    print -r -- "Options:"
    print -r -- "  --no-unregister-duplicates  Do not unregister duplicate MDViewer bundles."
    print -r -- "  --no-gc                     Do not garbage-collect Launch Services."
    print -r -- "  -h, --help                  Show this help."
}

find_lsregister() {
    for candidate in "${LSREGISTER_CANDIDATES[@]}"; do
        if [[ -x "$candidate" ]]; then
            print -r -- "$candidate"
            return 0
        fi
    done

    return 1
}

bundle_id_for() {
    /usr/bin/defaults read "$1/Contents/Info" CFBundleIdentifier 2>/dev/null || true
}

add_found_app_path() {
    local candidate="$1"
    [[ -d "$candidate" ]] || return 0

    local candidate_bundle_id
    candidate_bundle_id="$(bundle_id_for "$candidate")"
    [[ "$candidate_bundle_id" == "$BUNDLE_ID" ]] || return 0

    local resolved="${candidate:A}"
    if [[ -z "${FOUND_APP_PATHS[$resolved]:-}" ]]; then
        FOUND_APP_PATHS[$resolved]=1
        print -r -- "$resolved"
    fi
}

find_mdviewer_apps() {
    FOUND_APP_PATHS=()

    local query="kMDItemCFBundleIdentifier == \"$BUNDLE_ID\""
    if [[ -x /usr/bin/mdfind ]]; then
        while IFS= read -r candidate; do
            add_found_app_path "$candidate"
        done < <(/usr/bin/mdfind "$query" 2>/dev/null || true)
    fi

    local search_roots=(
        "/Applications"
        "$HOME/Applications"
        "$HOME/Downloads"
        "$HOME/Desktop"
        "$REPO_ROOT"
        "/private/tmp/mdviewer-DerivedData"
        "/private/tmp/mdviewer-ReleaseDerivedData"
        "${TMPDIR:-/tmp}"
    )

    local root
    for root in "${search_roots[@]}"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r candidate; do
            add_found_app_path "$candidate"
        done < <(/usr/bin/find "$root" -name "MDViewer.app" -type d -prune 2>/dev/null || true)
    done
}

current_handlers() {
    /usr/bin/swift -module-cache-path "$SWIFT_MODULE_CACHE" -e 'import Foundation; import CoreServices
let contentType = CommandLine.arguments[1] as CFString
let roles: [(String, LSRolesMask)] = [
    ("viewer", .viewer),
    ("editor", .editor),
    ("all", .all)
]

for role in roles {
    let handler = LSCopyDefaultRoleHandlerForContentType(contentType, role.1)?.takeRetainedValue() as String? ?? "<none>"
    print("\(role.0): \(handler)")
}
' "$CONTENT_TYPE"
}

set_handler() {
    /usr/bin/swift -module-cache-path "$SWIFT_MODULE_CACHE" -e 'import Darwin
import Foundation
import CoreServices

let contentType = CommandLine.arguments[1] as CFString
let bundleID = CommandLine.arguments[2] as CFString
let roles: [(String, LSRolesMask)] = [
    ("viewer", .viewer),
    ("editor", .editor),
    ("all", .all)
]

var didFail = false
for role in roles {
    let status = LSSetDefaultRoleHandlerForContentType(contentType, role.1, bundleID)
    print("\(role.0): \(status)")
    if status != noErr {
        didFail = true
    }
}

exit(didFail ? 1 : 0)
' "$CONTENT_TYPE" "$BUNDLE_ID"
}

handler_is_mdviewer() {
    /usr/bin/swift -module-cache-path "$SWIFT_MODULE_CACHE" -e 'import Darwin
import Foundation
import CoreServices

let contentType = CommandLine.arguments[1] as CFString
let bundleID = CommandLine.arguments[2]
let roles: [LSRolesMask] = [.viewer, .editor, .all]

for role in roles {
    let handler = LSCopyDefaultRoleHandlerForContentType(contentType, role)?.takeRetainedValue() as String?
    if handler == bundleID {
        exit(0)
    }
}

exit(1)
' "$CONTENT_TYPE" "$BUNDLE_ID"
}

while (( $# > 0 )); do
    case "$1" in
        --no-unregister-duplicates)
            UNREGISTER_DUPLICATES=0
            ;;
        --no-gc)
            GARBAGE_COLLECT=0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            print -r -- "Error: unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            APP_PATH="$1"
            ;;
    esac
    shift
done

APP_PATH="${APP_PATH:A}"

print -r -- "MDViewer Markdown handler repair"
print -r -- ""
print -r -- "macOS remembers default apps through Launch Services. If more than one"
print -r -- "MDViewer build has been launched, or a new build is installed without being"
print -r -- "registered, Launch Services can keep stale copies in the Open With menu"
print -r -- "and drift back to another Markdown-capable app."
print -r -- ""
print -r -- "This script will:"
if (( UNREGISTER_DUPLICATES )); then
    print -r -- "  1. Find duplicate MDViewer bundles and unregister them from Launch Services."
else
    print -r -- "  1. Leave duplicate MDViewer Launch Services registrations untouched."
fi
if (( GARBAGE_COLLECT )); then
    print -r -- "  2. Garbage-collect stale Launch Services records."
else
    print -r -- "  2. Skip Launch Services garbage collection."
fi
print -r -- "  3. Register the installed MDViewer app with Launch Services."
print -r -- "  4. Set ${BUNDLE_ID} as the handler for ${CONTENT_TYPE}."
print -r -- "  5. Verify the handler that macOS reports afterwards."
print -r -- ""
print -r -- "It does not delete app bundles from disk."
print -r -- ""

if [[ ! -d "$APP_PATH" ]]; then
    print -r -- "Error: app bundle not found at: $APP_PATH" >&2
    print -r -- "Pass a different app path if needed:" >&2
    print -r -- "  Tools/repair_markdown_handler.sh /path/to/MDViewer.app" >&2
    exit 1
fi

APP_BUNDLE_ID=$(/usr/bin/defaults read "$APP_PATH/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
if [[ "$APP_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    print -r -- "Error: $APP_PATH has bundle id '$APP_BUNDLE_ID', expected '$BUNDLE_ID'." >&2
    exit 1
fi

LSREGISTER="$(find_lsregister)" || {
    print -r -- "Error: could not find lsregister on this Mac." >&2
    exit 1
}

print -r -- "App:          $APP_PATH"
print -r -- "Bundle ID:    $BUNDLE_ID"
print -r -- "Content type: $CONTENT_TYPE"
print -r -- "Before:"
current_handlers || true
print -r -- ""

if (( UNREGISTER_DUPLICATES )); then
    print -r -- "Looking for duplicate MDViewer bundles..."
    duplicate_count=0
    while IFS= read -r candidate; do
        if [[ "$candidate" == "$APP_PATH" ]]; then
            continue
        fi

        duplicate_count=$((duplicate_count + 1))
        print -r -- "Unregistering duplicate: $candidate"
        if ! "$LSREGISTER" -u "$candidate"; then
            print -r -- "Warning: unable to unregister $candidate" >&2
        fi
    done < <(find_mdviewer_apps)

    if (( duplicate_count == 0 )); then
        print -r -- "No duplicate MDViewer bundles found."
    fi
    print -r -- ""
fi

if (( GARBAGE_COLLECT )); then
    print -r -- "Garbage-collecting stale Launch Services records..."
    "$LSREGISTER" -gc
    print -r -- ""
fi

print -r -- "Registering app bundle..."
"$LSREGISTER" -f -R "$APP_PATH"

print -r -- "Setting default Markdown handler..."
STATUS_OUTPUT="$(set_handler)" || {
    print -r -- "Error: unable to set one or more Launch Services roles:" >&2
    print -r -- "$STATUS_OUTPUT" >&2
    exit 1
}
print -r -- "$STATUS_OUTPUT"

print -r -- "After:"
current_handlers || true

if handler_is_mdviewer; then
    print -r -- ""
    print -r -- "Done. Markdown files should now open with MDViewer."
else
    print -r -- ""
    print -r -- "Warning: macOS did not report MDViewer as the default handler." >&2
    print -r -- "If this recurs, remove old MDViewer.app copies from /Applications," >&2
    print -r -- "~/Applications, Downloads, and Desktop, then run this script again." >&2
    exit 1
fi

print -r -- ""
print -r -- "If stale Open With entries are still visible, relaunch Finder or log out"
print -r -- "and back in. Finder can cache menu contents after Launch Services is fixed."
