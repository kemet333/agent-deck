#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
preview_dir="${AGENT_DECK_FLOW_PREVIEW_DIR:-/private/tmp/agent-deck-flow-preview-20261103}"
app_dir="$preview_dir/Agent Deck Flow Review.app"
mkdir -p "$preview_dir/modules" "$app_dir/Contents/MacOS"
source_files=("$project_dir"/Sources/*.swift)
source_files=("${(@)source_files:#*AgentDeskApp.swift}")
source_files=("${(@)source_files:#*BuildIcon.swift}")
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$preview_dir/modules" \
 "$project_dir/Tests/FlowPreviewApp.swift" "${source_files[@]}" \
 -framework SwiftUI -framework AppKit -framework Speech -framework AVFoundation -framework Security -framework LocalAuthentication \
 -o "$app_dir/Contents/MacOS/FlowPreview"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.prompted.agentdeck.flow-review</string><key>CFBundleExecutable</key><string>FlowPreview</string><key>CFBundleName</key><string>Agent Deck Flow Review</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf 'FLOW_REVIEW_APP %s\n' "$app_dir"
