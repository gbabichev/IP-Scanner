# IP Scanner

macOS app for scanning IP ranges, resolving hostnames, and reporting open services.

## Features
- Scan a single IP or range (for example `192.168.1.1-192.168.1.15`).
- Show hostname, reachability, and detected services.
- Filter results by reachability or by presence of services.
- Export results to CSV.
- Manage default and custom service definitions.
- Add custom services and export/import them as JSON.

## Usage
1. Enter an IP or range in the main window.
2. Check Settings to ensure you are scanning the right services. 
3. Click Scan to start.
4. Use filters to refine the table.
5. Use the menu bar to export results or manage services.

## Services Export
Custom services can be exported from the Services menu, and custom service sets can be imported as JSON.

JSON schema (each entry in the array is a service):
```json
[
  {
    "name": "My Service",
    "port": 1234,
    "transport": "tcp",
    "isEnabled": true
  }
]
```

Notes:
- `name` is a human-friendly label.
- `port` is the port number.
- `transport` is `tcp` or `udp`.
- `isEnabled` controls whether the service is used during scans.

## Default Services
The app ships with the following default services (name: port, transport):
- http: 80 (tcp)
- https: 443 (tcp)
- ssh: 22 (tcp)
- smb: 445 (tcp)
- netbios: 139 (tcp)
- rdp: 3389 (tcp)
- vnc: 5900 (tcp)
- mqtt: 1883 (tcp)
- mqtts: 8883 (tcp)
- mysql: 3306 (tcp)
- postgres: 5432 (tcp)
- redis: 6379 (tcp)
- dns: 53 (udp)
- ntp: 123 (udp)
- ftp: 21 (tcp)
- smtp: 25 (tcp)
- imap: 143 (tcp)
- imaps: 993 (tcp)

## Build
Open `IP Scanner.xcodeproj` in Xcode and run the `IP Scanner` scheme.
