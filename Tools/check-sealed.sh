#!/bin/zsh
# Sealed-build guard for YayaShot. Fails when network code appears outside the
# one allowed wrapper, when the host allowlist drifts, or when a built binary
# links anything that can reach the network another way.
#
#   Tools/check-sealed.sh                 check the source tree (build.sh runs this first)
#   Tools/check-sealed.sh path/to/App.app also check the built bundle (build.sh runs this last)
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
say_fail() { print -r -- "✗ $1"; fail=1; }

POLICY="Sources/Sealed/NetworkPolicy.swift"

# 1-4. Swift-aware source scan: strips comments while keeping string literals
#      (single-line and """ multi-line), then applies the rules below.
scan_output=$(/usr/bin/python3 - "$POLICY" <<'PY'
import re, sys, pathlib
policy = sys.argv[1]
roots = [pathlib.Path("Sources"), pathlib.Path("Vendor")]

def code_and_strings(text):
    """Yield (line_no, code_without_comments, [string literals on that line])."""
    out_code, lits, i, n, line = [], [], 0, len(text), 1
    buf, cur_lits, rows = [], [], []
    def flush():
        rows.append((line, "".join(buf), list(cur_lits)))
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            while i < n and text[i] != "\n": i += 1
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            line += text.count("\n", i, j); i = j; continue
        if text.startswith('"""', i):
            j = text.find('"""', i + 3); j = n if j < 0 else j + 3
            lit = text[i:j]; cur_lits.append(lit); buf.append('""'); line += lit.count("\n"); i = j; continue
        if c == '"':
            j = i + 1
            while j < n and text[j] not in '"\n':
                j += 2 if text[j] == "\\" else 1
            lit = text[i:j + 1]; cur_lits.append(lit); buf.append('""'); i = j + 1; continue
        if c == "\n":
            flush(); buf.clear(); cur_lits.clear(); line += 1; i += 1; continue
        buf.append(c); i += 1
    flush()
    return rows

NET = re.compile(r'\b(URLSession|NSURLSession|URLRequest|NSURLConnection|NWConnection|NWListener|NWBrowser|NWPathMonitor|nw_[a-z_]+|CFStream\w*|CFSocket\w*|CFHost\w*|CFHTTPMessage\w*|WebSocket\w*|dataTask|uploadTask|downloadTask|SCNetworkReachability\w*|getaddrinfo|DNSService\w*|NSStream|InputStream\(url|sendto|recvfrom)\b|(?<![.\w])(?<!func )(socket|connect)\s*\((?!\s*\w+\s*:)')
WEB = re.compile(r'\b(WKWebView|WebView|WKWebsiteDataStore|JSContext|NSAppleScript|OSAScript|NSUbiquitousKeyValueStore|CKContainer|CKDatabase|NSUserActivity)\b')
PROC = re.compile(r'\b(Process\s*\(|launchPath|executableURL|posix_spawn|NSUserUnixTask|NSTask)\b|(^|[^.\w])system\s*\(')
REMOTE_LOAD = re.compile(r'(contentsOf|contentsOfURL|url)\s*:\s*URL\s*\(\s*string')
SCHEME = re.compile(r'([A-Za-z][A-Za-z0-9+.-]*)://([A-Za-z0-9.-]*)')
PROC_ALLOWED = {"Sources/Capture/ScreencaptureRunner.swift", "Sources/App/BetterShotDelegate.swift"}
GITHUB_LINK_FILES = {"Sources/Settings/PreferencesView.swift", "Sources/Settings/MadeByFooter.swift", "Sources/App/ReleaseNotesWindowController.swift", "Sources/Services/AppUpdater.swift"}
API_FILES = {"Sources/Services/AppUpdater.swift"}

problems = []
for root in roots:
    for f in sorted(root.rglob("*.swift")):
        path = str(f)
        rows = code_and_strings(f.read_text(errors="replace"))
        for ln, code, lits in rows:
            where = f"{path}:{ln}"
            if path != policy and NET.search(code):
                problems.append(f"network API outside {policy}: {where}: {code.strip()[:120]}")
            if WEB.search(code):
                problems.append(f"web view / iCloud / scripting surface: {where}: {code.strip()[:120]}")
            if PROC.search(code) and path not in PROC_ALLOWED:
                problems.append(f"process launch outside the allowlist: {where}: {code.strip()[:120]}")
            if REMOTE_LOAD.search(code) or any(REMOTE_LOAD.search(l) for l in lits):
                problems.append(f"loader built from a URL string: {where}")
            for lit in lits:
                for scheme, host in SCHEME.findall(lit):
                    scheme = scheme.lower(); host = host.lower()
                    if scheme in ("file", "yayashot"):
                        continue
                    if scheme == "https" and host == "github.com" and path in GITHUB_LINK_FILES:
                        continue
                    if scheme == "https" and host == "api.github.com" and path in API_FILES:
                        continue
                    problems.append(f"URL {scheme}://{host} not allowed here: {where}")
            if "URLComponents" in code and ".host =" in code and path != policy:
                problems.append(f"host assembled at runtime: {where}")

# Pin the two allowed process launches to their fixed executables.
runner = pathlib.Path("Sources/Capture/ScreencaptureRunner.swift").read_text()
if '"/usr/sbin/screencapture"' not in runner:
    problems.append("ScreencaptureRunner must only launch /usr/sbin/screencapture")
delegate = pathlib.Path("Sources/App/BetterShotDelegate.swift").read_text()
launches = re.findall(r'launchPath\s*=\s*"([^"]+)"', delegate)
if launches != ["/bin/sh"] or 'sleep 0.5; open \\"$0\\"' not in delegate:
    problems.append(f"BetterShotDelegate may only relaunch the app itself via /bin/sh (found {launches})")
print("\n".join(problems))
PY
)
[[ -n "$scan_output" ]] && say_fail "source scan:"$'\n'"$scan_output"

# 5. The allowlist itself.
allow=$(grep -E 'static let allowedHosts' "$POLICY" | sed -E 's/.*\[(.*)\].*/\1/' | tr -d ' "')
[[ "$allow" == "api.github.com" ]] || say_fail "allowlist changed: [$allow] (expected api.github.com)"
grep -q 'willPerformHTTPRedirection' "$POLICY" || say_fail "NetworkPolicy must refuse redirects off the allowlist"

# 6. Removed upstream pipelines stay removed.
for gone in Sources/Sharing/R2Uploader.swift Sources/Sharing/R2CredentialStore.swift Sources/Sharing/ShareManifest.swift Sources/Settings/SharingSettingsTab.swift; do
    [[ -e "$gone" ]] && say_fail "removed file is back: $gone"
done
grep -q 'var canShare: Bool { false }' Sources/BetterShot/CloudUploader.swift || say_fail "CloudUploader must stay a disabled stub"
grep -qE 'downloadTask|hdiutil|installUpdate' Sources/Services/AppUpdater.swift && say_fail "updater must not download or install"
grep -q '= "capture/fullscreen"' Sources/App/CaptureURLAction.swift && say_fail "the silent capture/fullscreen URL route must stay removed"

# 7. Optional: the built bundle.
if [[ $# -ge 1 ]]; then
    app="$1"
    exe="$app/Contents/MacOS/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist")"
    machos=$(find "$app" -type f -perm +111 -exec sh -c 'file -b "$1" | grep -q Mach-O && echo "$1"' _ {} \;)
    [[ "$machos" == "$exe" ]] || say_fail "unexpected executable code in bundle: $machos"
    bin_hosts=$(strings -a "$exe" | grep -oE '[A-Za-z][A-Za-z0-9+.-]*://[A-Za-z0-9.-]+' | sort -u \
        | grep -vxE 'https://(api\.)?github\.com|https?://(www\.)?apple\.com|http://www\.w3\.org|http://ns\.adobe\.com|file://|yayashot://' || true)
    [[ -n "$bin_hosts" ]] && say_fail "unexpected URL in binary: $bin_hosts"
    bad_syms=$(nm -u "$exe" 2>/dev/null | grep -E '^_(socket|connect|getaddrinfo|sendto|recvfrom|CFSocket|CFStream|CFHost|nw_|DNSService)|OBJC_CLASS_\$_(WKWebView|NSURLConnection|CKContainer|NSUbiquitousKeyValueStore|NSAppleScript)' || true)
    [[ -n "$bad_syms" ]] && say_fail "forbidden imported symbols: $bad_syms"
    bad_libs=$(otool -L "$exe" | grep -E '/(WebKit|Network|CloudKit|JavaScriptCore)\.framework/' || true)
    [[ -n "$bad_libs" ]] && say_fail "forbidden linked frameworks: $bad_libs"
    print -r -- "  binary URLs: $(strings -a "$exe" | grep -oE 'https?://[A-Za-z0-9.-]+' | sort -u | tr '\n' ' ')"
fi

if (( fail )); then
    print -r -- "✗ sealed check FAILED"
    exit 1
fi
print -r -- "✓ sealed check passed (network only via $POLICY → api.github.com)"
