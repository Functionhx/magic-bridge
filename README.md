<div align="center">
  <img
    src="MagicBridge/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
    width="152"
    alt="Magic Bridge app icon"
  >

  # Magic Bridge

  **让 Apple 备忘录、Magic Notes 与个人网站安全握手。**

  迁移留在本地，身份交给系统，密钥不进应用。

  [中文](README.md) · [English](README-EN.md)

  ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square&logo=apple&logoColor=white)
  ![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)
  ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF?style=flat-square)
  ![Privacy](https://img.shields.io/badge/Privacy-local--first-C218B8?style=flat-square)
</div>

---

Magic Bridge 不是另一款笔记应用。它是
[Magic Notes](https://github.com/Functionhx/magic-notes) 的原生权限边界：把读取
Apple 备忘录与连接个人网站这两件高权限操作，从编辑器中独立出来，做成一座可见、
可控、可审计的网桥。

## 一座桥，两条路

| Apple 备忘录 → Magic Notes | Magic Notes → 个人网站 |
| --- | --- |
| 从一致的只读快照恢复原生清单状态 | 使用系统 OAuth 窗口完成 GitHub 登录 |
| 生成权限为 `0600` 的一次性迁移包 | 使用 PKCE S256 绑定本次授权 |
| 导入完成后自动删除临时文件 | 只把密封会话保存在 macOS Keychain |
| 不修改 Apple 备忘录，也不上传正文 | GitHub token 与 OAuth secret 始终留在服务端 |

```mermaid
flowchart LR
    A["Apple 备忘录<br/>只读快照"] -->|"临时迁移包 · 0600"| B["Magic Bridge"]
    B -->|"本机交接"| C["Magic Notes"]
    B -->|"GitHub OAuth + PKCE"| D["个人网站"]
    %% 为 GitHub 的 Mermaid 缩放控件预留右下角空间。
    D ~~~ Z["GitHub diagram controls"]
    classDef spacer fill:transparent,stroke:transparent,color:transparent;
    class Z spacer;
```

## 为什么需要独立的网桥？

笔记编辑器每天都在运行，但读取系统备忘录数据库、发起网站授权并不应该成为它的
常驻权限。Magic Bridge 只在你明确发起迁移或连接时工作，让 Magic Notes 保持更小、
更安静，也让权限用途一眼可见。

- **本地优先**：迁移流程完全在 Mac 上完成，笔记标题与正文不会发送到服务器。
- **只读迁移**：通过一致的 SQLite 备份读取 Apple 备忘录，绝不写入实时数据库。
- **短命文件**：交接包仅包含修复导入所需的数据，权限为 `0600`，使用后即删除。
- **系统级身份保护**：授权通过 `ASWebAuthenticationSession` 与 PKCE S256 完成，
  Mac 端只保存无法直接换取 GitHub 权限的密封会话。
- **会话不可混用**：浏览器会话与原生应用会话采用不同的认证加密用途。

## 开发与验证

需要 Xcode 及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MagicBridge.xcodeproj -scheme MagicBridge \
  -destination 'platform=macOS' test
```

Debug 构建可直接使用本机 Apple Notes group container，因此可能需要“完全磁盘访问”
权限。面向 App Store 的 Release 构建启用沙盒，并让用户手动选择
`~/Library/Group Containers/group.com.apple.notes`；保存的 security-scoped bookmark
只有读取权限。

## 发布状态

App Store 所需的应用图标、沙盒 entitlement、隐私清单、加密声明和通用架构归档均已
准备完成。正式签名与上传仍需 Apple Developer Team、发行证书和 App Store Connect
记录。完整清单见 [APP_STORE.md](APP_STORE.md)。

## Magic 系列

- [Magic Notes](https://github.com/Functionhx/magic-notes)：原生、local-first 的 macOS
  写作与笔记应用。
- [个人网站](https://functionhx.github.io/)：公开写作、工具与工作的最终呈现层。
