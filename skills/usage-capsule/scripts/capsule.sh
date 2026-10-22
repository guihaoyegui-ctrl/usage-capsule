#!/bin/zsh
set -eu
skill_dir="${0:A:h:h}"
source_dir="$skill_dir/assets/app"
build_dir="${USAGE_CAPSULE_BUILD_DIR:-$source_dir/build}"
install_dir="${USAGE_CAPSULE_INSTALL_DIR:-$HOME/Applications}"
app_bundle="$install_dir/Usage Capsule.app"
bundle_id='io.github.guihaoyegui-ctrl.usagecapsule'
action="${1:-help}"

find_cli() {
    local cli_candidate
    for cli_candidate in "${CODEX_CLI_PATH:-}" \
      '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex' \
      '/Applications/Codex.app/Contents/Resources/codex' '/opt/homebrew/bin/codex' '/usr/local/bin/codex'; do
        if [[ -n "$cli_candidate" && -x "$cli_candidate" ]]; then print -r -- "$cli_candidate"; return 0; fi
    done
    command -v codex 2>/dev/null || return 1
}
require_platform() {
    [[ "$(uname -s)" == Darwin ]] || { print -u2 'Usage Capsule requires macOS.'; exit 2; }
    [[ "$(uname -m)" == arm64 ]] || { print -u2 'This preview supports Apple Silicon Macs.'; exit 2; }
    local os_major="$(sw_vers -productVersion | cut -d. -f1)"
    (( os_major >= 13 )) || { print -u2 'macOS 13 or later is required.'; exit 2; }
}
require_compiler() {
    xcrun --find swiftc >/dev/null 2>&1 || { print -u2 'Install Xcode Command Line Tools first: xcode-select --install'; exit 2; }
}
running_pids() {
    local process_id command_path process_list
    process_list="$(ps -axo pid=,comm=)" || return $?
    print -r -- "$process_list" | while read -r process_id command_path; do
        if [[ "$command_path" == "$app_bundle/Contents/MacOS/UsageCapsule" ]]; then print -r -- "$process_id"; fi
    done
}
stop_target() {
    local process_id capsule_pids
    capsule_pids="$(running_pids)" || return $?
    for process_id in ${(f)capsule_pids}; do [[ -z "$process_id" ]] || kill -TERM "$process_id"; done
}
build_target() {
    require_platform; require_compiler
    mkdir -p "$build_dir"
    zsh "$source_dir/build.sh" "$build_dir/Usage Capsule.app"
}
start_target() {
    [[ -d "$app_bundle" ]] || { print -u2 "Not installed. Run: zsh $0 install"; exit 2; }
    local cli_binary="$(find_cli)"
    [[ -n "$cli_binary" ]] || { print -u2 'Codex CLI not found. Install/sign in to Codex, then retry.'; exit 2; }
    open "$app_bundle" --args --codex-cli "$cli_binary"
    print "Started: $app_bundle"
}
install_target() {
    build_target
    mkdir -p "$install_dir"
    if [[ -e "$app_bundle" ]]; then
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_bundle/Contents/Info.plist")" == "$bundle_id" ]] || {
            print -u2 'The destination contains a different app. Choose another USAGE_CAPSULE_INSTALL_DIR.'; exit 2
        }
    fi
    local staging_dir="$(mktemp -d "$install_dir/.usage-capsule.XXXXXX")"
    if ! ditto "$build_dir/Usage Capsule.app" "$staging_dir/new.app" || ! chmod -R u+rwX "$staging_dir/new.app" || ! codesign --verify --deep --strict "$staging_dir/new.app"; then
        rm -rf "$staging_dir"; return 1
    fi
    if ! stop_target; then rm -rf "$staging_dir"; return 1; fi
    if [[ -e "$app_bundle" ]]; then mv "$app_bundle" "$staging_dir/previous.app"; fi
    if ! mv "$staging_dir/new.app" "$app_bundle"; then
        [[ ! -d "$staging_dir/previous.app" ]] || mv "$staging_dir/previous.app" "$app_bundle"
        rm -rf "$staging_dir"; return 1
    fi
    chmod -R u+rwX "$staging_dir"
    rm -rf "$staging_dir"
    print "Installed: $app_bundle"
}

case "$action" in
    doctor)
        require_platform; require_compiler
        print 'Platform: macOS / Apple Silicon'
        swiftc --version | head -n 1
        if cli_binary="$(find_cli)"; then print "Codex CLI: $cli_binary"
        else print -u2 'Codex CLI not found. Required for live usage; demo preview still works.'; exit 1; fi
        print "Install destination: $app_bundle"
        ;;
    build) build_target ;;
    install) install_target ;;
    start) require_platform; start_target ;;
    stop) require_platform; stop_target; print 'Stopped the installed Usage Capsule instance.' ;;
    status)
        require_platform
        if [[ -d "$app_bundle" ]]; then print "Installed: $app_bundle"; else print 'Not installed'; fi
        capsule_pids="$(running_pids)"
        if [[ -n "$capsule_pids" ]]; then print "Running PID: $capsule_pids"; else print 'Not running'; fi
        ;;
    preview)
        build_target
        "$build_dir/Usage Capsule.app/Contents/MacOS/UsageCapsule" --render-preview --reference-preview --dark-preview "$build_dir/preview.png"
        print "Demo-only preview: $build_dir/preview.png"
        ;;
    demo)
        require_platform
        [[ -d "$app_bundle" ]] || { print -u2 'Install the app first.'; exit 2; }
        [[ -z "$(running_pids)" ]] || { print -u2 'Quit the installed instance before opening demo mode.'; exit 2; }
        open "$app_bundle" --args --demo
        ;;
    language)
        require_platform
        selected_language="${2:-}"
        case "$selected_language" in system|zh-Hans|en|ja|ko) ;; *) print -u2 'Choose system, zh-Hans, en, ja, or ko'; exit 2;; esac
        capsule_pids="$(running_pids)"
        defaults write "$bundle_id" interfaceLanguage -string "$selected_language"
        if [[ -n "$capsule_pids" ]]; then stop_target; start_target; fi
        print "Language: $selected_language"
        ;;
    *)
        print 'Usage: zsh scripts/capsule.sh {doctor|build|install|start|stop|status|preview|demo|language CODE}'
        print 'Default install: ~/Applications/Usage Capsule.app'
        print 'Language codes: system, zh-Hans, en, ja, ko'
        print 'preview/demo use example data and never query your account.'
        ;;
esac
