#!/bin/zsh
# Builds YayaShot with the Command Line Tools only (no Xcode, no xcodebuild,
# no actool): compiles the three vendored packages as static modules, compiles
# the app, assembles the .app bundle by hand, and signs it.
#
#   ./build.sh            release build  -> dist/YayaShot.app
#   ./build.sh --dev      developer build -> dist/YayaShot (Developer).app, own bundle id
#   ./build.sh --install  also copy the release build to /Applications
#
# The bundle is staged in a temp dir before signing: folders synced by File
# Provider gain extended attributes that make codesign fail.
set -euo pipefail
cd "$(dirname "$0")"

DEV=0
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --dev)     DEV=1 ;;
        --install) INSTALL=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

VERSION="$(/usr/bin/python3 -c "import json; print(json.load(open('version.json'))['version'])")"
BUILD_NUM="$(/usr/bin/python3 -c "import json; print(json.load(open('version.json'))['build'])")"

if (( DEV )); then
    APP_NAME="YayaShot (Developer)"
    EXECUTABLE="YayaShotDeveloper"
    BUNDLE_ID="com.yahyaelghobashy.yayashot.dev"
    OPT=(-Onone -D YAYASHOT_DEVELOPMENT)
else
    APP_NAME="YayaShot"
    EXECUTABLE="YayaShot"
    BUNDLE_ID="com.yahyaelghobashy.yayashot"
    OPT=(-O)
fi

TARGET="arm64-apple-macosx26.0"
SIGNING_IDENTITY="YayaShot Signing"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/yayashot-signing.keychain-db"

# The macOS 27 SDK turns SwiftUI property wrappers into macros whose compiler
# plugin ships only inside Xcode. Pin the macOS 26 SDK; Swift 6.4 reads its
# interfaces when told the compiler version they were built with.
PINNED_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [[ -d "$PINNED_SDK" && -z "${DEVELOPER_DIR:-}" ]]; then
    SDK="$PINNED_SDK"
    SDK_FLAGS=(-Xfrontend -interface-compiler-version -Xfrontend 6.3.2)
else
    SDK="$(xcrun --show-sdk-path)"
    SDK_FLAGS=()
fi

BUILD="build/$([[ $DEV == 1 ]] && echo dev || echo release)"
MODS="$BUILD/modules"
mkdir -p "$MODS" dist

COMMON=(-target "$TARGET" -sdk "$SDK" "${SDK_FLAGS[@]}" "${OPT[@]}" -gnone)

# 1. Vendored packages -> static libraries + .swiftmodule
build_package() {
    local name="$1" mode="$2"; shift 2
    local sources=("${(@f)$(find "$@" -name '*.swift' | sort)}")
    echo "▸ $name (${#sources} files)"
    swiftc "${COMMON[@]}" -swift-version "$mode" -parse-as-library \
        -module-name "$name" -emit-module -emit-module-path "$MODS/$name.swiftmodule" \
        -emit-library -static -o "$BUILD/lib$name.a" "${sources[@]}"
}
build_package DockProgress 5 Vendor/DockProgress/Sources/DockProgress
build_package DynamicNotchKit 5 Vendor/DynamicNotchKit/Sources/DynamicNotchKit
build_package TourKit 5 Vendor/TourKit/Sources/TourKit

# 2. The app. Mirrors upstream's project.yml: Swift 5 mode, MainActor default
#    isolation, approachable concurrency, member import visibility.
APP_SOURCES=("${(@f)$(find Sources -name '*.swift' | sort)}")
echo "▸ $EXECUTABLE (${#APP_SOURCES} files)"
swiftc "${COMMON[@]}" -swift-version 5 \
    -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature MemberImportVisibility \
    -module-name YayaShot -I "$MODS" -L "$BUILD" \
    -lDockProgress -lDynamicNotchKit -lTourKit \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$BUILD/$EXECUTABLE" "${APP_SOURCES[@]}"

# 3. Bundle
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

/usr/bin/python3 - "$APP/Contents/Info.plist" "$EXECUTABLE" "$BUNDLE_ID" "$APP_NAME" "$VERSION" "$BUILD_NUM" <<'PY'
import plistlib, sys
out, exe, bid, name, ver, build = sys.argv[1:]
with open("Resources/Info.plist", "rb") as f:
    p = plistlib.load(f)
subs = {
    "$(EXECUTABLE_NAME)": exe, "$(PRODUCT_BUNDLE_IDENTIFIER)": bid, "$(PRODUCT_NAME)": name,
    "$(MARKETING_VERSION)": ver, "$(CURRENT_PROJECT_VERSION)": build,
    "$(DEVELOPMENT_LANGUAGE)": "en", "$(PRODUCT_BUNDLE_PACKAGE_TYPE)": "APPL",
    "$(MACOSX_DEPLOYMENT_TARGET)": "26.0",
}
def fix(v):
    if isinstance(v, str):
        for k, r in subs.items():
            v = v.replace(k, r)
        return v
    if isinstance(v, list):
        return [fix(x) for x in v]
    if isinstance(v, dict):
        return {k: fix(x) for k, x in v.items()}
    return v
p = fix(p)
p.update({"CFBundleExecutable": exe, "CFBundleIdentifier": bid, "CFBundleName": name,
          "CFBundleDisplayName": name, "CFBundleShortVersionString": ver, "CFBundleVersion": build,
          "CFBundlePackageType": "APPL", "CFBundleIconFile": "AppIcon", "LSMinimumSystemVersion": "26.0"})
with open(out, "wb") as f:
    plistlib.dump(p, f)
PY

cp -R Resources/Backgrounds Resources/Onboarding Resources/Licenses "$APP/Contents/Resources/"
cp CHANGELOG.md "$APP/Contents/Resources/"
# Asset catalog replacement (no actool): the icon as .icns and the menu-bar
# template image as plain PNGs, which NSImage(named:) finds by name.
cp Resources/Generated/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/Generated/MenuBarIcon.png "$APP/Contents/Resources/MenuBarIcon.png"
cp Resources/Generated/MenuBarIcon@2x.png "$APP/Contents/Resources/MenuBarIcon@2x.png"

# 4. Sign: the stable local identity when present (keeps Screen Recording and
#    Input Monitoring grants across rebuilds), otherwise ad-hoc.
xattr -cr "$APP"
security unlock-keychain -p yayashot-signing "$SIGNING_KEYCHAIN" 2>/dev/null || true
if /usr/bin/codesign --force --options runtime --entitlements Resources/YayaShot.entitlements \
        --sign "$SIGNING_IDENTITY" "$APP" 2>/dev/null; then
    echo "▸ signed with $SIGNING_IDENTITY"
else
    /usr/bin/codesign --force --options runtime --entitlements Resources/YayaShot.entitlements --sign - "$APP"
    echo "▸ signed ad-hoc (run Tools/setup-signing.sh for a stable identity)"
fi
/usr/bin/codesign --verify --deep --strict "$APP"

rm -rf "dist/$APP_NAME.app"
ditto "$APP" "dist/$APP_NAME.app"
echo "✓ dist/$APP_NAME.app ($VERSION, build $BUILD_NUM)"

if (( INSTALL && ! DEV )); then
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP" "/Applications/$APP_NAME.app"
    echo "✓ installed /Applications/$APP_NAME.app"
fi
