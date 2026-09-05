#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
target="$(uname -m)-apple-macosx13.0"
swiftc -target "$target" -swift-version 5 -enable-testing -emit-library -static -emit-module -module-name LampCore \
  Sources/LampCore/State.swift -o .build/tests/libLampCore.a -emit-module-path .build/tests/LampCore.swiftmodule
swiftc -target "$target" -swift-version 5 -I .build/tests -L .build/tests -lLampCore \
  Tests/LampCoreTests/StateTests.swift Tests/Runner/main.swift -o .build/tests/LampTests
.build/tests/LampTests examples/*.json
for script in scripts/*.sh; do bash -n "$script"; done
