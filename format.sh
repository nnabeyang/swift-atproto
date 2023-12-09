#!/usr/bin/env bash
if type "swiftformat" > /dev/null 2>&1; then
    swift-format . --cache ignore
else
    swift run --skip-build -c release --package-path Tools swiftformat . --cache ignore
fi
