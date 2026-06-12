#!/bin/zsh
# DeskPin 빌드·설치 (DESIGN.md B3 — 4단계 고정: 종료 → 삭제 → 조립·서명 → 검증)
set -e
cd "$(dirname "$0")"

pkill -f 'DeskPin.app/Contents/MacOS/DeskPin' 2>/dev/null || true
sleep 0.3

swiftc -O Sources/*.swift -o /tmp/DeskPin_build

rm -rf /Applications/DeskPin.app
mkdir -p /Applications/DeskPin.app/Contents/MacOS
cp /tmp/DeskPin_build /Applications/DeskPin.app/Contents/MacOS/DeskPin
cp resources/Info.plist /Applications/DeskPin.app/Contents/Info.plist
mkdir -p /Applications/DeskPin.app/Contents/Resources
cp assets/sprites/*/*.png /Applications/DeskPin.app/Contents/Resources/ 2>/dev/null || true
rm -f /tmp/DeskPin_build

codesign --force --sign - /Applications/DeskPin.app
codesign --verify --strict /Applications/DeskPin.app

echo "BUILD OK -> /Applications/DeskPin.app"
