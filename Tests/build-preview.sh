#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
voice_preview_dir="${AGENT_DECK_PREVIEW_DIR:-/private/tmp/agent-deck-voice-preview-20261102}"
app_dir="$voice_preview_dir/Agent Deck Voice Review.app"
mkdir -p "$voice_preview_dir/modules" "$app_dir/Contents/MacOS"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$voice_preview_dir/modules" \
 "$project_dir/Tests/VoicePreviewApp.swift" "$project_dir/Sources/DeskModel.swift" "$project_dir/Sources/DeskView.swift" \
 "$project_dir/Sources/Sender.swift" "$project_dir/Sources/PasteTiming.swift" "$project_dir/Sources/TalkKey.swift" "$project_dir/Sources/Dictation.swift" "$project_dir/Sources/Strings.swift" \
 "$project_dir/Sources/VoiceModels.swift" "${project_dir}/Sources/VoiceAudioFile.swift" "$project_dir/Sources/OpenAIVoiceClient.swift" "$project_dir/Sources/VoiceKeychain.swift" \
 "$project_dir/Sources/VoiceRecorder.swift" "$project_dir/Sources/VoiceController.swift" "$project_dir/Sources/Chime.swift" "$project_dir/Sources/VoiceCommands.swift" "$project_dir/Sources/VoiceWorkspaceView.swift" \
 "$project_dir/Sources/FlowCore.swift" "$project_dir/Sources/FlowController.swift" "$project_dir/Sources/FlowWorkspaceView.swift" \
 -framework SwiftUI -framework AppKit -framework Speech -framework AVFoundation -framework Security -framework LocalAuthentication -o "$app_dir/Contents/MacOS/VoicePreview"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.prompted.agentdeck.voice-review</string><key>CFBundleExecutable</key><string>VoicePreview</string><key>CFBundleName</key><string>Agent Deck Voice Review</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$app_dir"
printf 'REVIEW_APP %s\n' "$app_dir"
