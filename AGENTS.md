# AGENTS.md

Quick reference for working on IP Scanner.

## Project overview
- macOS SwiftUI app that scans IP ranges, resolves hostnames, and checks open TCP services.
- Supports CSV export and configurable service lists (defaults + custom entries).

## Key locations
- App entry: `IP Scanner/IP_ScannerApp.swift`
- Main UI: `IP Scanner/UI/ContentView.swift`
- Settings UI (services): `IP Scanner/UI/SettingsView.swift`
- Scan orchestration + core logic: `IP Scanner/Logic/AppViewModel.swift`
- Service config model + JSON import/export: `IP Scanner/Logic/ServicesSupport.swift`
- Default service catalog: `IP Scanner/Logic/ServiceCatalog.swift`
- Bonjour cache/browser: `IP Scanner/Logic/BonjourBrowser.swift`
- CSV export: `IP Scanner/Logic/CSVDocument.swift`, `IP Scanner/Logic/ExportCSVAction.swift`

## Architecture notes
- `AppViewModel` owns scan lifecycle, runs concurrent tasks, and publishes results to SwiftUI.
- Host reachability uses ICMP ping first, then TCP port checks on discovery ports.
- Service scanning is TCP-only (no UDP support).
- Service configs are stored as JSON in `@AppStorage("serviceConfigsJSON")`.
- File menu CSV export is wired through `ExportActionsModel` (avoids `focusedValue` performance issues).

## Data formats
Service config JSON schema:
```json
[
  {
    "name": "My Service",
    "port": 1234,
    "isEnabled": true
  }
]
```

## Build/run
- Open `IP Scanner.xcodeproj` in Xcode and run the `IP Scanner` scheme.

## Development conventions
- Keep code ASCII-only unless the file already uses Unicode.
- Prefer `rg` for searching.
- Avoid destructive git commands unless explicitly requested.
