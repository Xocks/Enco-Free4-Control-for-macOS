#!/bin/zsh
set -euo pipefail
script_dir=${0:A:h}
repo_dir=${script_dir:h}
cd "$repo_dir"
mkdir -p .test-build
# No XCTest dependency: runs with Apple's standalone Command Line Tools as well as Xcode.
swiftc Sources/OppoPodsCore/*.swift Tests/ProtocolChecks/main.swift -o .test-build/protocol-checks
.test-build/protocol-checks
