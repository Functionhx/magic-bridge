<div align="center">
  <img
    src="MagicBridge/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
    width="152"
    alt="Magic Bridge app icon"
  >

  # Magic Bridge

  **A secure handshake between Apple Notes, Magic Notes, and the web.**

  Migration stays local. Identity stays with the system. Secrets stay out of the app.

  [中文](README.md) · [English](README-EN.md)

  ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white)
  ![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)
  ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat-square)
  ![Privacy](https://img.shields.io/badge/Privacy-local--first-C218B8?style=flat-square)
</div>

---

Magic Bridge is not another notes app. It is the native privilege boundary for
[Magic Notes](https://github.com/Functionhx/magic-notes): a small, explicit, and
auditable place for Apple Notes migration and authenticated website sessions.

## One bridge, two paths

| Apple Notes → Magic Notes | Magic Notes → personal site |
| --- | --- |
| Restore native checklist state from a consistent read-only snapshot | Sign in through the system OAuth window |
| Produce a one-time handoff archive with mode `0600` | Bind each authorization with PKCE S256 |
| Remove the archive after import | Keep only a sealed session in macOS Keychain |
| Never modify Apple Notes or upload note bodies | Keep GitHub tokens and OAuth secrets on the server |

```mermaid
flowchart LR
    A["Apple Notes<br/>read-only snapshot"] -->|"ephemeral archive · 0600"| B["Magic Bridge"]
    B -->|"local handoff"| C["Magic Notes"]
    B -->|"GitHub OAuth + PKCE"| D["Personal site"]
    %% Reserve the bottom-right corner for GitHub's Mermaid controls.
    D ~~~ Z["GitHub diagram controls"]
    classDef spacer fill:transparent,stroke:transparent,color:transparent;
    class Z spacer;
```

## Why a separate bridge?

The editor runs every day; access to the Apple Notes database and website
authorization should not. Magic Bridge performs those privileged actions only
when you ask, keeping Magic Notes smaller and making every permission legible.

- **Local-first migration:** note titles and bodies never leave the Mac.
- **Read-only access:** Apple Notes is read from a consistent SQLite backup;
  the live database is never modified.
- **Short-lived artifacts:** handoff archives contain only migration repair data,
  use mode `0600`, and are deleted after import.
- **System-backed identity:** `ASWebAuthenticationSession` and PKCE S256 handle
  authorization; the Mac stores only a sealed session in Keychain.
- **Separated sessions:** browser and native sessions use different
  authenticated-encryption purposes and cannot be substituted for each other.

## Development

Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) are required:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MagicBridge.xcodeproj -scheme MagicBridge \
  -destination 'platform=macOS' test
```

Debug builds may access the local Apple Notes group container directly and can
require Full Disk Access. The sandboxed App Store Release build asks the user to
select `~/Library/Group Containers/group.com.apple.notes` and stores a read-only
security-scoped bookmark.

## Release status

The icon set, sandbox entitlements, privacy manifest, encryption declaration,
and universal archive are ready. Distribution signing and upload still require
an Apple Developer Team, distribution certificate, and App Store Connect record.
See [APP_STORE.md](APP_STORE.md) for the submission checklist.

## The Magic family

- [Magic Notes](https://github.com/Functionhx/magic-notes): a native, local-first
  writing and notes app for macOS.
- [Personal site](https://functionhx.github.io/): the public layer for writing,
  tools, and work.
