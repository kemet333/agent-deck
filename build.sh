#!/bin/zsh
# Compila Agent Desk sin Xcode (solo Command Line Tools): swiftc + bundle + icono + firma ad hoc.
# Resultado: ./Agent Desk.app  (y Agent-Desk-Mac.zip para repartir)
set -euo pipefail
project_dir="${0:A:h}"
build_dir="${AGENT_DESK_BUILD_DIR:-${TMPDIR:-/private/tmp}/agent-desk-build-$UID}"
app_dir="$build_dir/Agent Desk.app"
sdk_dir="$(xcrun --show-sdk-path)"
mkdir -p "$build_dir/modules" "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 -sdk "$sdk_dir" \
  -module-cache-path "$build_dir/modules" -parse-as-library \
  "$project_dir"/Sources/AgentDeskApp.swift "$project_dir"/Sources/DeskModel.swift \
  "$project_dir"/Sources/DeskView.swift "$project_dir"/Sources/FloatingPanel.swift "$project_dir"/Sources/Sender.swift \
  -framework SwiftUI -framework AppKit -framework ServiceManagement \
  -o "$app_dir/Contents/MacOS/AgentDesk"
xcrun swiftc -swift-version 5 -O -sdk "$sdk_dir" -module-cache-path "$build_dir/modules" \
  "$project_dir/Sources/BuildIcon.swift" -framework AppKit -o "$build_dir/build-icon"
"$build_dir/build-icon" "$build_dir/AppIcon.iconset" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
xattr -cr "$app_dir"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
plutil -lint "$app_dir/Contents/Info.plist" >/dev/null
rm -rf "$project_dir/Agent Desk.app"
ditto --norsrc --noextattr "$app_dir" "$project_dir/Agent Desk.app"
ditto --norsrc --noextattr -c -k --keepParent "$project_dir/Agent Desk.app" "$project_dir/Agent-Desk-Mac.zip"
printf 'Agent Desk compilada: %s\n' "$project_dir/Agent Desk.app"
