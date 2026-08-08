# Magic Bridge · App Store preparation

## Product metadata

- **Name:** Magic Bridge
- **Bundle ID:** `cn.com.fanyuchen.MagicBridge`
- **Version:** `1.0.0` (`1`)
- **Primary category:** Productivity
- **Minimum macOS:** 14.0
- **Suggested subtitle:** Connect local notes to your site
- **Suggested Chinese subtitle:** 连接本机笔记与个人网站
- **Privacy policy URL:** `https://functionhx.github.io/privacy/magic-bridge/`
- **Support URL:** `https://functionhx.github.io/`

Suggested Chinese description:

> Magic Bridge 是 Magic Notes 的本机伴侣。它以只读方式恢复 Apple
> 备忘录清单状态，并通过系统浏览器、GitHub OAuth 与 PKCE 安全连接个人网站。
> 笔记迁移完全在 Mac 上完成；笔记正文不会发送到服务器。

Suggested keywords:

`笔记,备忘录,清单,迁移,个人网站,写作,Markdown,同步`

## Already implemented

- Complete 16–1024 px macOS AppIcon set, compiled as `AppIcon.icns`.
- Release App Sandbox with user-selected read-only file access and outbound
  networking only.
- A read-only security-scoped bookmark for the Apple Notes source folder.
- `ASWebAuthenticationSession` + PKCE S256 + short-lived single-use exchange.
- Sealed native session stored in Keychain; no OAuth secret or GitHub token in
  the app bundle.
- Privacy manifest covering UserDefaults access and the GitHub user identifier
  used for app functionality.
- Custom callback scheme `magicbridge://oauth/callback`.
- `ITSAppUsesNonExemptEncryption = NO`; the app uses only Apple platform crypto
  for authentication, Keychain, and transport security.

## Before uploading

1. Select the paid Apple Developer team in Xcode and create the App ID
   `cn.com.fanyuchen.MagicBridge`.
2. Create the macOS app record in App Store Connect; add support and privacy
   policy URLs.
3. Archive the Release scheme with Apple Distribution signing.
4. Run Xcode **Validate App**, then upload to TestFlight.
5. Test on a clean macOS account: source-folder selection, 283-item checklist
   migration, GitHub OAuth, Keychain restore, disconnect, and offline errors.
6. Capture App Store screenshots at the sizes requested by App Store Connect.

The unsigned Release build is structurally validated in CI/local development,
but App Store validation cannot finish without the owner's Developer Team,
distribution certificate, provisioning profile, and App Store Connect record.
