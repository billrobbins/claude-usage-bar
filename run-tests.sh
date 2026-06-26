#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
# Core/ is Foundation-only — no extra frameworks needed for the test runner.
swiftc -o build/test_runner app/Sources/Core/*.swift tests/*.swift
./build/test_runner
