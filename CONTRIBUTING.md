# Contributing to YayaShot

YayaShot is a sealed fork of [BetterShot](https://github.com/KartikLabhshetwar/better-shot).
Feature work and bug fixes that are not about sealing or branding belong upstream first;
this repository merges upstream releases and keeps its own seal.

## Rules for changes

- Network access goes only through `Sources/Sealed/NetworkPolicy.swift`. Do not add
  `URLSession`, sockets, web views or process launches of network tools anywhere else.
  `Tools/check-sealed.sh` enforces this.
- Keep every upstream copyright header and the files in `Resources/Licenses`.
- Build and check before sending a change:

```bash
./build.sh --dev
Tools/check-sealed.sh "dist/YayaShot (Developer).app"
```

## Merging an upstream release

```bash
git fetch upstream --tags
git merge v<version>
Tools/check-sealed.sh
./build.sh --dev
```

Resolve conflicts in favor of the sealed behavior: no uploads, notify-only updates.
Update `upstreamBaseVersion` in `Sources/Services/AppUpdater.swift` after the merge.

The tests in `Tests/` are upstream's and run through its Xcode-based runners.
