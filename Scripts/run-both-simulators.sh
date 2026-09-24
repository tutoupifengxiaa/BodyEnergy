#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
project_path="$project_dir/BodyEnergy.xcodeproj"
derived_data="${TMPDIR:-/tmp}/BodyEnergyRunBothDerived"

iphone_name="${BODY_ENERGY_IPHONE_SIMULATOR:-iPhone 17 Pro}"
watch_name="${BODY_ENERGY_WATCH_SIMULATOR:-Apple Watch Series 11 (46mm)}"

device_id() {
    local device_name="$1"
    local device_line
    device_line="$(xcrun simctl list devices available | grep -F "    $device_name (" | sed -n '1p')"
    print -r -- "$device_line" | sed -nE 's/.*\(([0-9A-F-]{36})\).*/\1/p'
}

pair_list="$(xcrun simctl list pairs)"
iphone_id="$(print -r -- "$pair_list" | sed -nE 's/^[[:space:]]*Phone:.*\(([0-9A-F-]{36})\).*/\1/p' | sed -n '1p')"
watch_id="$(print -r -- "$pair_list" | sed -nE 's/^[[:space:]]*Watch:.*\(([0-9A-F-]{36})\).*/\1/p' | sed -n '1p')"

if [[ -n "$iphone_id" && -n "$watch_id" ]]; then
    iphone_name="paired iPhone"
    watch_name="paired Apple Watch"
else
    iphone_id="$(device_id "$iphone_name")"
    watch_id="$(device_id "$watch_name")"
fi

if [[ -z "$iphone_id" ]]; then
    print -u2 "找不到 iPhone 模拟器：$iphone_name"
    exit 1
fi

if [[ -z "$watch_id" ]]; then
    print -u2 "找不到 Apple Watch 模拟器：$watch_name"
    exit 1
fi

if ! xcrun simctl list pairs | grep -q "$iphone_id"; then
    xcrun simctl shutdown "$iphone_id" >/dev/null 2>&1 || true
    xcrun simctl shutdown "$watch_id" >/dev/null 2>&1 || true
    xcrun simctl pair "$watch_id" "$iphone_id" >/dev/null
fi

print "正在启动 $iphone_name 和 $watch_name…"
xcrun simctl boot "$iphone_id" >/dev/null 2>&1 || true
xcrun simctl boot "$watch_id" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$iphone_id" -b
xcrun simctl bootstatus "$watch_id" -b
open -a Simulator

print "正在构建 iOS App…"
xcodebuild \
    -project "$project_path" \
    -scheme BodyEnergy \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$iphone_id" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

print "正在构建 watchOS App…"
xcodebuild \
    -project "$project_path" \
    -scheme BodyEnergyWatch \
    -configuration Debug \
    -destination "platform=watchOS Simulator,id=$watch_id" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

ios_app="$derived_data/Build/Products/Debug-iphonesimulator/BodyEnergy.app"
watch_app="$derived_data/Build/Products/Debug-watchsimulator/BodyEnergyWatch.app"

print "正在安装并打开两个 App…"
xcrun simctl install "$iphone_id" "$ios_app"
xcrun simctl install "$watch_id" "$watch_app"
xcrun simctl launch "$iphone_id" com.tutoupifengxiaa.BodyEnergy
xcrun simctl launch "$watch_id" com.tutoupifengxiaa.BodyEnergy.watchkitapp

print "Body Energy 已在 iPhone 和 Apple Watch 模拟器中启动。"
