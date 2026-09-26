#!/bin/zsh
# Sealed-build guard for YayaShot. Fails when network code appears outside the
# one allowed wrapper, or when the host allowlist drifts.
#
#   Tools/check-sealed.sh                 check the source tree
#   Tools/check-sealed.sh path/to/App.app also check the built binary's URLs
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
say_fail() { print -r -- "✗ $1"; fail=1; }

ALLOWED_NETWORK_FILE="Sources/Sealed/NetworkPolicy.swift"
SCAN=(Sources Vendor)

# 1. Network APIs only inside the policy wrapper.
net_hits=$(grep -rnE '\b(URLSession|URLRequest|NWConnection|NWListener|NWBrowser|CFStream|CFSocket|URLSessionWebSocketTask|WebSocket|dataTask|uploadTask|downloadTask|SCNetworkReachability|CFHTTPMessage)\b' "${SCAN[@]}" \
    | grep -v "^$ALLOWED_NETWORK_FILE:" | grep -vE '^[^:]+:[0-9]+:\s*//' || true)
[[ -n "$net_hits" ]] && say_fail "network API outside $ALLOWED_NETWORK_FILE:"$'\n'"$net_hits"

# 2. No web views, no scripting bridges that can fetch.
web_hits=$(grep -rnE '\b(WKWebView|WebView|JSContext|NSAppleScript|OSAScript)\b' "${SCAN[@]}" | grep -vE '^[^:]+:[0-9]+:\s*//' || true)
[[ -n "$web_hits" ]] && say_fail "web view or scripting bridge:"$'\n'"$web_hits"

# 3. No process launches of network tools.
proc_hits=$(grep -rnE '"/usr/bin/(curl|wget|nc|ssh|scp|sftp|ftp|telnet|git|open)"|"(curl|wget|nc|ssh|scp)"' "${SCAN[@]}" || true)
[[ -n "$proc_hits" ]] && say_fail "process launch of a network tool:"$'\n'"$proc_hits"

# 4. Only known hosts may be written in source. github.com appears only as
#    links the user opens in the browser; api.github.com only for the policy.
host_hits=$(grep -rhE --include='*.swift' 'https?://' "${SCAN[@]}" | grep -vE '^\s*//' | sed -E 's#//[^"]*$##' \
    | grep -oE 'https?://[A-Za-z0-9.-]+' | sed -E 's#https?://##' | sort -u \
    | grep -vxE 'github\.com|api\.github\.com|localhost|127\.0\.0\.1|www\.w3\.org|www\.apple\.com|apple\.com' || true)
[[ -n "$host_hits" ]] && say_fail "unexpected host in source: $host_hits"

# 5. The allowlist itself.
allow=$(grep -E 'static let allowedHosts' "$ALLOWED_NETWORK_FILE" | sed -E 's/.*\[(.*)\].*/\1/' | tr -d ' "')
[[ "$allow" == "api.github.com" ]] || say_fail "allowlist changed: [$allow] (expected api.github.com)"

# 6. Removed upstream pipelines stay removed.
for gone in Sources/Sharing/R2Uploader.swift Sources/Sharing/R2CredentialStore.swift Sources/Sharing/ShareManifest.swift Sources/Settings/SharingSettingsTab.swift; do
    [[ -e "$gone" ]] && say_fail "removed file is back: $gone"
done
grep -q 'var canShare: Bool { false }' Sources/BetterShot/CloudUploader.swift || say_fail "CloudUploader must stay a disabled stub"
grep -qE 'downloadTask|hdiutil|installUpdate' Sources/Services/AppUpdater.swift && say_fail "updater must not download or install"

# 7. Optional: URLs baked into the built binary.
if [[ $# -ge 1 ]]; then
    bin="$1/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$1/Contents/Info.plist")"
    bin_hosts=$(strings -a "$bin" | grep -oE 'https?://[A-Za-z0-9.-]+' | sed -E 's#https?://##' | sort -u \
        | grep -vxE 'github\.com|api\.github\.com|www\.apple\.com|apple\.com|www\.w3\.org|ns\.adobe\.com' || true)
    [[ -n "$bin_hosts" ]] && say_fail "unexpected host in binary: $bin_hosts"
    print -r -- "  binary hosts: $(strings -a "$bin" | grep -oE 'https?://[A-Za-z0-9.-]+' | sed -E 's#https?://##' | sort -u | tr '\n' ' ')"
fi

if (( fail )); then
    print -r -- "✗ sealed check FAILED"
    exit 1
fi
print -r -- "✓ sealed check passed (network only via $ALLOWED_NETWORK_FILE → api.github.com)"
