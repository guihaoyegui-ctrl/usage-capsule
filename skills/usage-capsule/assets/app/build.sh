#!/bin/zsh
set -eu
cd "${0:A:h}"
app_output="${1:-${PWD}/build/Usage Capsule.app}"
app_output="${app_output:A}"
swift_cache="${USAGE_CAPSULE_SWIFT_CACHE:-${app_output:h}/swift-cache}"
capsule_arch="${CAPSULE_ARCH:-arm64}"
case "$capsule_arch" in arm64|x86_64) ;; *) print -u2 'CAPSULE_ARCH must be arm64 or x86_64'; exit 2;; esac
mkdir -p "$swift_cache" "${app_output:h}"
if [[ -e "$app_output" ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_output/Contents/Info.plist")" == 'io.github.guihaoyegui-ctrl.usagecapsule' ]] || {
        print -u2 'Build destination contains a different app.'; exit 2
    }
fi
stage_root="$(mktemp -d "${app_output:h}/.usage-capsule-build.XXXXXX")"
trap 'chmod -R u+rwX "$stage_root"; rm -rf "$stage_root"' EXIT
staged_app="$stage_root/Usage Capsule.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
swiftc -swift-version 5 -target "${capsule_arch}-apple-macos13.0" -O -module-cache-path "$swift_cache" -framework SwiftUI -framework AppKit Sources/*.swift -o "$staged_app/Contents/MacOS/UsageCapsule"
cp Info.plist "$staged_app/Contents/Info.plist"
cp Resources/CapsuleGlass.png Resources/OverviewGlass.png "$staged_app/Contents/Resources/"
for locale_dir in Resources/*.lproj; do cp -R "$locale_dir" "$staged_app/Contents/Resources/"; done
chmod -R u+rwX "$staged_app"
codesign --force --deep --sign - "$staged_app"
codesign --verify --deep --strict "$staged_app"
if [[ -e "$app_output" ]]; then mv "$app_output" "$stage_root/previous.app"; fi
if ! mv "$staged_app" "$app_output"; then
    [[ ! -d "$stage_root/previous.app" ]] || mv "$stage_root/previous.app" "$app_output"
    exit 1
fi
print "Built: $app_output"
