#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
flow_test_dir="${AGENT_DECK_FLOW_TEST_DIR:-/private/tmp/agent-deck-flow-tests}"
mkdir -p "$flow_test_dir/modules"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$flow_test_dir/modules" \
  "$project_dir/Sources/FlowCore.swift" "$project_dir/Sources/FlowController.swift" "$project_dir/Tests/FlowChecks.swift" \
  -framework AppKit -o "$flow_test_dir/flow-checks"
"$flow_test_dir/flow-checks"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$flow_test_dir/modules" \
  "$project_dir/Sources/FlowCore.swift" "$project_dir/Tests/FlowProtocolHarness.swift" -o "$flow_test_dir/flow-protocol"
python3 "$project_dir/Tests/test-flow-protocol.py" "$flow_test_dir/flow-protocol"
