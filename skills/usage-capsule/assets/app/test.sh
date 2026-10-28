#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/swift-cache
swiftc -module-cache-path build/swift-cache Sources/Domain.swift Sources/Localization.swift Tests/main.swift -o build/domain-tests
build/domain-tests
python3 Tests/check_resources.py
swiftc -swift-version 5 -module-cache-path build/swift-cache -framework SwiftUI -framework AppKit Sources/Domain.swift Sources/Localization.swift Sources/AutoResume.swift Sources/HandoffLedger.swift Sources/AutoResumeService.swift Sources/Service.swift Tests/ResetConfirmationTests.swift Tests/RefreshRecoveryTests.swift Tests/AutoResumeTests.swift Tests/NativeQueueTests.swift -o build/reset-confirmation-tests
build/reset-confirmation-tests
swiftc -swift-version 5 -module-cache-path build/swift-cache Sources/AutoResume.swift Tests/ResetTransitionTests.swift -o build/reset-transition-tests
build/reset-transition-tests
swiftc -swift-version 5 -module-cache-path build/swift-cache Sources/HandoffLedger.swift Tests/HandoffLedgerTests.swift -o build/handoff-ledger-tests
build/handoff-ledger-tests
if [[ "${1:-}" == --ui ]]; then
    swiftc -swift-version 5 -module-cache-path build/swift-cache -framework SwiftUI -framework AppKit Sources/Domain.swift Sources/Localization.swift Sources/AutoResume.swift Sources/HandoffLedger.swift Sources/AutoResumeService.swift Sources/Service.swift Sources/Views.swift Sources/GlassMaterial.swift Sources/WindowMotion.swift Sources/CapsuleInteraction.swift Tests/InteractionCoverage.swift -o build/interaction-tests
    build/interaction-tests
fi
