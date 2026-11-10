#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
voice_test_dir="${AGENT_DECK_TEST_DIR:-${TMPDIR:-/private/tmp}/agent-deck-voice-tests-$UID}"
mkdir -p "$voice_test_dir/modules"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$voice_test_dir/modules" \
 "$project_dir/Sources/Strings.swift" "$project_dir/Sources/VoiceModels.swift" "${project_dir}/Sources/VoiceAudioFile.swift" "$project_dir/Sources/OpenAIVoiceClient.swift" \
 "$project_dir/Sources/VoiceKeychain.swift" "$project_dir/Sources/VoiceRecorder.swift" "$project_dir/Sources/Sender.swift" \
 "$project_dir/Sources/Dictation.swift" "$project_dir/Sources/VoiceController.swift" "$project_dir/Sources/RealtimeTranscriber.swift" "$project_dir/Sources/Chime.swift" "$project_dir/Sources/VoiceCommands.swift" "$project_dir/Tests/VoiceChecks.swift" \
 -framework AppKit -framework Speech -framework AVFoundation -framework Security -framework LocalAuthentication -o "$voice_test_dir/voice-checks"
"$voice_test_dir/voice-checks"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$voice_test_dir/modules" \
 "$project_dir/Sources/Autopilot.swift" "$project_dir/Tests/AutopilotChecks.swift" -o "$voice_test_dir/autopilot-checks"
"$voice_test_dir/autopilot-checks"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$voice_test_dir/modules" \
 "$project_dir/Sources/Strings.swift" "$project_dir/Sources/KeyPacks.swift" "$project_dir/Tests/PacksChecks.swift" -o "$voice_test_dir/packs-checks"
"$voice_test_dir/packs-checks"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$voice_test_dir/modules" \
 "$project_dir/Sources/Strings.swift" "$project_dir/Sources/Autopilot.swift" "$project_dir/Sources/VoiceCommands.swift" "$project_dir/Sources/Agents.swift" "$project_dir/Sources/Keys.swift" "$project_dir/Tests/AgentChecks.swift" \
 -framework AppKit -framework SwiftUI -o "$voice_test_dir/agent-checks"
"$voice_test_dir/agent-checks"
