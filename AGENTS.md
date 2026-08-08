# Magic Bridge repository guidelines

Magic Bridge is a native macOS companion for Magic Notes. It performs two
explicit jobs: local Apple Notes migration and authenticated communication with
the owner's personal website.

- Keep note migration local. Never log note titles, bodies, search terms, or
  protobuf payloads.
- Read Apple Notes through a consistent read-only SQLite snapshot; never write
  to `NoteStore.sqlite`.
- Migration archives are short-lived, mode `0600`, and contain only records
  required to repair an import.
- Store website sessions in Keychain. Never embed GitHub tokens, OAuth client
  secrets, Spark Vault keys, or private-note encryption keys in the app.
- Use SwiftUI for the shell and Foundation/AppKit for native integrations.
- Keep checklist decoding and website transport independently testable.

Verify with:

```bash
xcodegen generate
xcodebuild -project MagicBridge.xcodeproj -scheme MagicBridge \
  -destination 'platform=macOS' test
```
