#!/bin/bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# Swoirenberg XCFramework Build Script
#
# Builds the forked Swoirenberg (with chonk/IVC support) as an
# XCFramework for iOS device and simulator targets.
#
# Prerequisites:
#   rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#   Xcode with iOS SDK installed
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SWOIRENBERG_DIR="$SCRIPT_DIR/swoirenberg"
RUST_DIR="$SWOIRENBERG_DIR/Rust"
SWIFT_DIR="$SWOIRENBERG_DIR/Swift"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_DIR="$SCRIPT_DIR/output"

echo "══════════════════════════════════════════════"
echo "  Swoirenberg XCFramework Builder (Chonk Fork)"
echo "══════════════════════════════════════════════"

# Clean previous builds
rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
mkdir -p "$BUILD_DIR"/{ios-device,ios-sim} "$OUTPUT_DIR"

# ── Step 1: Build Rust staticlib for iOS targets ──
echo ""
echo "▸ Step 1: Compiling Rust for iOS targets..."

cd "$RUST_DIR"

echo "  ▸ Building aarch64-apple-ios (device)..."
rustup run nightly cargo build --release --target aarch64-apple-ios 2>&1 | tail -3
cp target/aarch64-apple-ios/release/libswoirenberg.a "$BUILD_DIR/ios-device/"

echo "  ▸ Building aarch64-apple-ios-sim (simulator)..."
rustup run nightly cargo build --release --target aarch64-apple-ios-sim 2>&1 | tail -3
cp target/aarch64-apple-ios-sim/release/libswoirenberg.a "$BUILD_DIR/ios-sim/"

echo "  ✓ Rust builds complete"

# ── Step 2: Collect Swift bridge files ──
echo ""
echo "▸ Step 2: Collecting Swift bridge files..."

GENERATED_DIR="$RUST_DIR/target/swift-bridge"
if [ ! -d "$GENERATED_DIR" ]; then
    # swift-bridge may output to different locations
    GENERATED_DIR=$(find "$RUST_DIR/target" -name "SwiftBridgeCore.swift" -exec dirname {} \; | head -1)
fi

if [ -z "$GENERATED_DIR" ] || [ ! -d "$GENERATED_DIR" ]; then
    echo "  ⚠ Swift bridge files not found in expected location"
    echo "    Checking Swift/Sources/Swoirenberg/ for existing files..."
    GENERATED_DIR="$SWIFT_DIR/Sources/Swoirenberg"
fi

echo "  Bridge files from: $GENERATED_DIR"

# ── Step 3: Create module map ──
echo ""
echo "▸ Step 3: Creating module map..."

cat > "$BUILD_DIR/module.modulemap" << 'MODULEMAP'
module SwoirenbergFramework {
    header "Swoirenberg-Swift.h"
    export *
}
MODULEMAP

cat > "$BUILD_DIR/Swoirenberg-Swift.h" << 'HEADER'
#ifndef SWOIRENBERG_SWIFT_H
#define SWOIRENBERG_SWIFT_H

#include <stdint.h>
#include <stdbool.h>

// Swift-bridge generated headers are included via the Swift wrapper

#endif
HEADER

# ── Step 4: Create XCFramework ──
echo ""
echo "▸ Step 4: Creating XCFramework..."

FRAMEWORK_NAME="SwoirenbergFramework"
XCFRAMEWORK_PATH="$OUTPUT_DIR/Swoirenberg.xcframework"

# Create framework structure for device
DEVICE_FW="$BUILD_DIR/ios-device/$FRAMEWORK_NAME.framework"
mkdir -p "$DEVICE_FW/Headers" "$DEVICE_FW/Modules"
cp "$BUILD_DIR/ios-device/libswoirenberg.a" "$DEVICE_FW/$FRAMEWORK_NAME"
cp "$BUILD_DIR/module.modulemap" "$DEVICE_FW/Modules/"
cp "$BUILD_DIR/Swoirenberg-Swift.h" "$DEVICE_FW/Headers/"

cat > "$DEVICE_FW/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.swoir.swoirenberg</string>
    <key>CFBundleName</key>
    <string>SwoirenbergFramework</string>
    <key>CFBundleVersion</key>
    <string>1.0.0-beta.19-1-chonk</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>iPhoneOS</string></array>
</dict>
</plist>
PLIST

# Create framework structure for simulator
SIM_FW="$BUILD_DIR/ios-sim/$FRAMEWORK_NAME.framework"
mkdir -p "$SIM_FW/Headers" "$SIM_FW/Modules"
cp "$BUILD_DIR/ios-sim/libswoirenberg.a" "$SIM_FW/$FRAMEWORK_NAME"
cp "$BUILD_DIR/module.modulemap" "$SIM_FW/Modules/"
cp "$BUILD_DIR/Swoirenberg-Swift.h" "$SIM_FW/Headers/"

cat > "$SIM_FW/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.swoir.swoirenberg</string>
    <key>CFBundleName</key>
    <string>SwoirenbergFramework</string>
    <key>CFBundleVersion</key>
    <string>1.0.0-beta.19-1-chonk</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>iPhoneSimulator</string></array>
</dict>
</plist>
PLIST

xcodebuild -create-xcframework \
    -framework "$DEVICE_FW" \
    -framework "$SIM_FW" \
    -output "$XCFRAMEWORK_PATH" 2>&1

echo "  ✓ XCFramework created at: $XCFRAMEWORK_PATH"

# ── Step 5: Calculate checksum ──
echo ""
echo "▸ Step 5: Computing checksum..."

cd "$OUTPUT_DIR"
zip -r Swoirenberg.xcframework.zip Swoirenberg.xcframework > /dev/null
CHECKSUM=$(swift package compute-checksum Swoirenberg.xcframework.zip 2>/dev/null || shasum -a 256 Swoirenberg.xcframework.zip | cut -d' ' -f1)

echo "  Checksum: $CHECKSUM"
echo "  Archive: $OUTPUT_DIR/Swoirenberg.xcframework.zip"

# ── Step 6: Print sizes ──
echo ""
echo "▸ Build sizes:"
du -sh "$BUILD_DIR/ios-device/libswoirenberg.a" | awk '{print "  Device staticlib: " $1}'
du -sh "$BUILD_DIR/ios-sim/libswoirenberg.a" | awk '{print "  Sim staticlib:    " $1}'
du -sh "$XCFRAMEWORK_PATH" | awk '{print "  XCFramework:      " $1}'
du -sh "$OUTPUT_DIR/Swoirenberg.xcframework.zip" | awk '{print "  Archive:          " $1}'

echo ""
echo "══════════════════════════════════════════════"
echo "  Done! Update Package.swift with:"
echo ""
echo "  .binaryTarget("
echo "      name: \"SwoirenbergFramework\","
echo "      url: \"<GITHUB_RELEASE_URL>/Swoirenberg.xcframework.zip\","
echo "      checksum: \"$CHECKSUM\""
echo "  )"
echo "══════════════════════════════════════════════"
