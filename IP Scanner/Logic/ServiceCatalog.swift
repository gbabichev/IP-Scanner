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
        Service(name: "http", port: 80),
        Service(name: "https", port: 443),
        Service(name: "ssh", port: 22),
        Service(name: "smb", port: 445),
        Service(name: "netbios", port: 139),
        Service(name: "rdp", port: 3389),
        Service(name: "vnc", port: 5900),
        Service(name: "mqtt", port: 1883),
        Service(name: "mqtts", port: 8883),
        Service(name: "mysql", port: 3306),
        Service(name: "postgres", port: 5432),
        Service(name: "redis", port: 6379),
        Service(name: "dns", port: 53),
        Service(name: "ntp", port: 123),
        Service(name: "ftp", port: 21),
        Service(name: "smtp", port: 25),
        Service(name: "imap", port: 143),
        Service(name: "imaps", port: 993)
    ]
}
