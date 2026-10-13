#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
# Command Line Tools do not ship XCTest. This native harness needs no Xcode install.
swiftc -parse-as-library Sources/PaceCore/*.swift Tests/PacingTests.swift -o .build/PacingTests
.build/PacingTests
