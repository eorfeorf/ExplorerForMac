#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
project_root="${script_directory:h}"
project_file="$project_root/ExplorerForMac.xcodeproj"
scheme_name="ExplorerForMac"
configuration_name="Release"
build_directory="${project_root}/build/release-universal"
artifact_directory="${project_root}/artifacts"

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    signing_identity="$CODE_SIGN_IDENTITY"
else
    signing_identity="-"
fi

mkdir -p "$artifact_directory"

# Xcode may retain architecture-specific module caches after a failed build.
# This path contains only generated release-build data owned by this script.
if [[ -d "$build_directory" ]]; then
    rm -rf "$build_directory"
fi

echo "Building Universal 2 release (arm64 + x86_64)…"
xcodebuild \
    -quiet \
    -jobs 1 \
    -project "$project_file" \
    -scheme "$scheme_name" \
    -configuration "$configuration_name" \
    -derivedDataPath "$build_directory" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    SWIFT_COMPILATION_MODE=incremental \
    CLANG_ENABLE_EXPLICIT_MODULES=NO \
    CODE_SIGN_IDENTITY="$signing_identity" \
    clean build

app_path="$build_directory/Build/Products/$configuration_name/Explorer for Mac.app"
if [[ ! -d "$app_path" ]]; then
    echo "Release app was not produced: $app_path" >&2
    exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
archive_name="Explorer-for-Mac-${version}-macOS-universal"
zip_path="$artifact_directory/${archive_name}.zip"
dmg_path="$artifact_directory/${archive_name}.dmg"
checksums_path="$artifact_directory/SHA256SUMS"

echo "Validating app bundle…"
codesign --verify --deep --strict "$app_path"
lipo "$app_path/Contents/MacOS/Explorer for Mac" -verify_arch arm64 x86_64
lipo "$app_path/Contents/PlugIns/ExplorerForMacFinderExtension.appex/Contents/MacOS/ExplorerForMacFinderExtension" -verify_arch arm64 x86_64

echo "Creating ZIP…"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

stage_directory=$(mktemp -d -t explorer-for-mac-dmg)
cleanup() {
    rm -rf "$stage_directory"
}
trap cleanup EXIT

ditto "$app_path" "$stage_directory/Explorer for Mac.app"
ln -s /Applications "$stage_directory/Applications"

echo "Creating DMG…"
hdiutil create \
    -quiet \
    -volname "Explorer for Mac $version" \
    -srcfolder "$stage_directory" \
    -ov \
    -format UDZO \
    "$dmg_path"

(
    cd "$artifact_directory"
    shasum -a 256 "${archive_name}.zip" "${archive_name}.dmg" > "$checksums_path"
)

echo "Release artifacts created:"
echo "  $zip_path"
echo "  $dmg_path"
echo "  $checksums_path"
