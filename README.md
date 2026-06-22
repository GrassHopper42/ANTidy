# ANTidy

ANTidy is a native macOS SwiftUI cleaner prototype built from the attached implementation guide. Its concept is a colony of tiny workers that carefully collect reclaimable clutter. Scanning, review, and deletion stay separate, and deletion only moves selected items to the macOS Trash.

## Run

```bash
swift run ANTidy
```

## Implemented

- SwiftUI macOS app with Apple Liquid Glass APIs on macOS 26 and material fallback on older supported macOS releases.
- Safe scan/review/delete flow.
- Full Disk Access status probe and System Settings shortcut.
- Scanners for developer junk, app caches, logs/reports, iOS backups, large files, orphaned app data, and byte-identical duplicates.
- Duplicate pipeline using size grouping, partial SHA-256, and full SHA-256.
- APFS clone suspect handling via `mayShareFileContent` with conservative reclaim estimates.
- Trash-only deletion using `FileManager.trashItem`.
