//
//  BonjourBrowser.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import Foundation
import Darwin

actor BonjourCache {
    private var hostnames: [String: String] = [:]

    func update(ip: String, hostname: String) {
        if hostnames[ip] == nil {
            hostnames[ip] = hostname
        }
    }

    func hostname(for ip: String) -> String? {
        hostnames[ip]
    }
}

final class BonjourBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private let cache: BonjourCache
    private let serviceTypes: [String]
    private var services: [NetService] = []

    init(cache: BonjourCache, serviceTypes: [String] = ["_workstation._tcp.", "_ssh._tcp.", "_smb._tcp.", "_http._tcp."]) {
        self.cache = cache
        self.serviceTypes = serviceTypes
        super.init()
    }

    func start() {
        browser.delegate = self
        for type in serviceTypes {
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    func stop() {
        browser.stop()
        for service in services {
            service.stop()
        }
        services.removeAll()
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        services.append(service)
        service.delegate = self
        service.resolve(withTimeout: 3.0)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let hostname = sender.hostName ?? sender.name
        guard let addresses = sender.addresses else { return }

        for address in addresses {
            address.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                let sockaddrPtr = base.assumingMemoryBound(to: sockaddr.self)
                if sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET) {
                    var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    let result = inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                    guard result != nil else { return }
                    let length = buffer.firstIndex(of: 0) ?? buffer.count
                    let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
                    let ip = String(decoding: bytes, as: UTF8.self)
                    Task { await cache.update(ip: ip, hostname: hostname) }
                }
            }
        }
    }
}
