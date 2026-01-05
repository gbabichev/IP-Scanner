//
//  ServiceCatalog.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//  Defines default well-known services and port catalog entries.
//  This list feeds the default service configs and UI display.
//

import Foundation

enum ServiceCatalog {
    static let discoveryPorts: [UInt16] = [80, 443, 22, 3389, 5900]
    static let servicePorts: [Service] = [
        Service(name: "dhcp", port: 67, transport: .udp),
        Service(name: "dns", port: 53, transport: .udp),
        Service(name: "ftp", port: 21, transport: .tcp),
        Service(name: "imap", port: 143, transport: .tcp),
        Service(name: "imaps", port: 993, transport: .tcp),
        Service(name: "http", port: 80, transport: .tcp),
        Service(name: "https", port: 443, transport: .tcp),
        Service(name: "ldap", port: 389, transport: .tcp),
        Service(name: "mqtt", port: 1883, transport: .tcp),
        Service(name: "mqtts", port: 8883, transport: .tcp),
        Service(name: "mysql", port: 3306, transport: .tcp),
        Service(name: "netbios", port: 139, transport: .tcp),
        Service(name: "ntp", port: 123, transport: .udp),
        Service(name: "postgres", port: 5432, transport: .tcp),
        Service(name: "rdp", port: 3389, transport: .tcp),
        Service(name: "redis", port: 6379, transport: .tcp),
        Service(name: "smb", port: 445, transport: .tcp),
        Service(name: "smtp", port: 25, transport: .tcp),
        Service(name: "ssh", port: 22, transport: .tcp),
        Service(name: "telnet", port: 23, transport: .tcp),
        Service(name: "tftp", port: 69, transport: .udp),
        Service(name: "vnc", port: 5900, transport: .tcp)
    ]
}
