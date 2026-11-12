#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
out="${AGENT_DECK_PREVIEW_DIR:-${TMPDIR:-/private/tmp}/agent-deck-dashboard-preview-$UID}"
app_dir="$out/Agent Bar Dashboard Review.app"
mkdir -p "$out/modules" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/docs/packs/packs.json" "$app_dir/Contents/Resources/packs.json"
s="$project_dir/Sources"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$out/modules" \
 "$project_dir/Tests/DashboardPreviewApp.swift" "$s/DashboardView.swift" "$s/DeskModel.swift" "$s/DeskView.swift" \
 "$s/Sender.swift" "$s/Dictation.swift" "$s/Strings.swift" "$s/Chime.swift" "$s/Updater.swift" "$s/VoiceCommands.swift" "$s/Agents.swift" "$s/Keys.swift" "$s/Doctor.swift" "$s/DoctorLive.swift" "$s/DoctorView.swift" "$s/PasteTiming.swift" "$s/TalkKey.swift" "$s/Trading.swift" "$s/TradingPane.swift" "$s/AgentAwake.swift" "$s/AgentAwakeLive.swift" "$s/DeskKey.swift" "$s/Growth.swift" "$s/GrowthLive.swift" "$s/GrowthView.swift" "$s/VoiceModels.swift" "$s/VoiceAudioFile.swift" "$s/OpenAIVoiceClient.swift" \
 "$s/VoiceKeychain.swift" "$s/VoiceRecorder.swift" "$s/VoiceController.swift" "$s/RealtimeTranscriber.swift" "$s/FlowCore.swift" "$s/FlowController.swift" \
 "$s/ClaudeHooks.swift" "$s/Autopilot.swift" "$s/KeyPacks.swift" "$s/License.swift" "$s/ProView.swift" "$s/ProVoice.swift" \
 -framework SwiftUI -framework AppKit -framework ServiceManagement -framework Speech -framework AVFoundation -framework Security -framework LocalAuthentication -framework IOKit \
 -o "$app_dir/Contents/MacOS/DashboardPreview"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.prompted.agentdeck.dashboard-review</string><key>CFBundleExecutable</key><string>DashboardPreview</string><key>CFBundleName</key><string>Agent Bar Dashboard Review</string><key>CFBundleShortVersionString</key><string>0.20.0</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf 'REVIEW_APP %s\n' "$app_dir"
