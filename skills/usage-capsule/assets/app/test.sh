#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/swift-cache
swiftc -module-cache-path build/swift-cache Sources/Domain.swift Sources/Localization.swift Tests/main.swift -o build/domain-tests
build/domain-tests
python3 Tests/check_resources.py
if [[ "${1:-}" == --ui ]]; then
    swiftc -swift-version 5 -module-cache-path build/swift-cache -framework SwiftUI -framework AppKit Sources/Domain.swift Sources/Localization.swift Sources/Service.swift Sources/Views.swift Sources/GlassMaterial.swift Sources/WindowMotion.swift Sources/CapsuleInteraction.swift Tests/InteractionCoverage.swift -o build/interaction-tests
    build/interaction-tests
fi
