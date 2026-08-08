# Magic Bridge

Magic Bridge is the native macOS companion for
[Magic Notes](https://github.com/Functionhx/magic-notes). It keeps two
privileged capabilities outside the editor itself:

1. read a consistent, read-only snapshot of Apple Notes and restore native
   checklist state during migration;
2. connect Magic Notes to the owner's website through a short-lived,
   PKCE-bound session stored in Keychain.

The migration path is local-only. The app never writes to Apple Notes and does
not send note content to a server.

## Security boundary

- Apple Notes is read from a consistent SQLite backup; the live database is
  opened read-only and is never modified.
- The hand-off archive is mode `0600`, marked ephemeral, and removed by Magic
  Notes after import.
- GitHub OAuth runs in `ASWebAuthenticationSession` with PKCE S256. GitHub
  access tokens and OAuth secrets remain on the server; the Mac stores only a
  sealed Magic Bridge session in Keychain.
- Browser sessions and native sessions use different authenticated-encryption
  purposes, so they cannot be substituted for each other.

## Development

```bash
xcodegen generate
xcodebuild -project MagicBridge.xcodeproj -scheme MagicBridge \
  -destination 'platform=macOS' test
```

The Debug build can use the local Apple Notes group container directly and may
need Full Disk Access. The Release build is sandboxed and asks the user to
select `~/Library/Group Containers/group.com.apple.notes`; the resulting
security-scoped bookmark is read-only.

App Store metadata, privacy declarations, signing steps, and the remaining
submission checklist are documented in [APP_STORE.md](APP_STORE.md).
