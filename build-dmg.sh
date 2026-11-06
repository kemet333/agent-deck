#!/bin/zsh
# El instalador típico de Mac: un disco con la app y un acceso a Aplicaciones para arrastrarla.
# Uso: ./build.sh && ./build-dmg.sh   →   AgentBar.dmg
set -euo pipefail
project_dir="${0:A:h}"
app="$project_dir/Agent Deck.app"
[[ -d "$app" ]] || { echo "Primero ./build.sh"; exit 1; }
stage="$(mktemp -d "${TMPDIR:-/private/tmp}/agentbar-dmg.XXXXXX")"
ditto --norsrc --noextattr "$app" "$stage/Agent Deck.app"
ln -s /Applications "$stage/Applications"
rm -f "$project_dir/AgentBar.dmg"
hdiutil create -quiet -volname "Agent Bar" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$project_dir/AgentBar.dmg"
rm -rf "$stage"
codesign --force --sign - "$project_dir/AgentBar.dmg" 2>/dev/null || true
printf 'Instalador: %s\n' "$project_dir/AgentBar.dmg"
