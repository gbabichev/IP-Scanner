# IP Scanner

macOS app for scanning IP ranges, resolving hostnames, and reporting open services.

## Features
- Scan a single IP or range (for example `192.168.1.1-192.168.1.15`).
- Show hostname, reachability, and detected services.
- Filter results by reachability or by presence of services.
- Export results to CSV.
- Manage default and custom service definitions.

## Usage
1. Enter an IP or range in the main window.
2. Click Scan to start.
3. Use filters to refine the table.
4. Use the menu bar to export results or manage services.

## Services Export
Custom services can be exported from the Services menu. The export is pretty-printed JSON for readability.

Example JSON schema (each entry in the array is a service):
```json
[
  {
    "name": "My Service",
    "port": 1234,
    "isEnabled": true
  }
]
```

Notes:
- `name` is a human-friendly label.
- `port` is the TCP port number.
- `isEnabled` controls whether the service is used during scans.

## Default Services
The app ships with the following default services (name: port):
- http: 80
- https: 443
- ssh: 22
- smb: 445
- netbios: 139
- rdp: 3389
- vnc: 5900
- mqtt: 1883
- mqtts: 8883
- mysql: 3306
- postgres: 5432
- redis: 6379
- dns: 53
- ntp: 123
- ftp: 21
- smtp: 25
- imap: 143
- imaps: 993

## Build
Open `IP Scanner.xcodeproj` in Xcode and run the `IP Scanner` scheme.
