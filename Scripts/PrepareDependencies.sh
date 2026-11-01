#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
cache="$PWD/.build/Dependencies"
mkdir -p "$cache"
archive="$cache/VLCKit-3.7.3.tar.xz"
if [ ! -f "$archive" ]; then
 curl --fail --location --retry 3 'https://download.videolan.org/cocoapods/prod/VLCKit-3.7.3-319ed2c0-79128878.tar.xz' -o "$archive.partial"
 mv "$archive.partial" "$archive"
fi
printf '%s  %s\n' '019afdae4e2e2d0f3ac325fac8f7ba0af25dca70b9d157df7d60db88e0be8e5d' "$archive" | shasum -a 256 -c -
tar -xf "$archive" -C "$cache" 'VLCKit - binary package/VLCKit.xcframework' 'VLCKit - binary package/COPYING.txt'
ditto "$cache/VLCKit - binary package/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework" "$cache/VLCKit.framework"
