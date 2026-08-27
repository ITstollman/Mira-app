# Vendored DecartSDK

Source copy of https://github.com/DecartAI/decart-ios at **v0.6.10**, unmodified
except for line 1 of `Package.swift`.

Upstream declares `// swift-tools-version: 6.2.1`, which needs Xcode 26. This
machine runs Xcode 16.3 / Swift 6.1, so SPM refuses to even parse the manifest.
The Swift sources themselves compile clean on 6.1 — only the manifest line
blocks it, so it is lowered to `6.0` here.

ponytail: delete this directory and point the project at the remote package
(`https://github.com/DecartAI/decart-ios`, from 0.6.10) once Xcode is upgraded.

To re-sync against a newer upstream tag:

    git clone https://github.com/DecartAI/decart-ios /tmp/decart && cd /tmp/decart && git checkout <tag>
    rsync -a --delete /tmp/decart/Sources/ Vendor/DecartSDK/Sources/
    cp /tmp/decart/Package.swift Vendor/DecartSDK/Package.swift
    sed -i '' '1s|.*|// swift-tools-version: 6.0|' Vendor/DecartSDK/Package.swift
