//
//  AppViewModel.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//  Coordinates scanning workflow and UI state.
//  Owns scan lifecycle, progress/status messages, and result filtering.
//  Provides derived data like CSV export content for the UI layer.
//

import Foundation
import SwiftUI
import Darwin
import Network
import Combine

struct Service: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let port: UInt16
    let transport: ServiceTransport
}

struct IPScanResult: Identifiable, Sendable {
    let id = UUID()
    let ipAddress: String
    var hostname: String?
    var isAlive: Bool
    var openServices: [Service]
    var servicesSummary: String
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var inputRange: String = "192.168.20.1-192.168.20.5"
    @Published var results: [IPScanResult] = []
    @Published var isScanning: Bool = false
    @Published var progressText: String = ""
    @Published var statusMessage: String = ""

    private var scanTask: Task<Void, Never>?
    private let bonjourCache = BonjourCache()
    private lazy var bonjourBrowser = BonjourBrowser(cache: bonjourCache)
    @AppStorage("serviceConfigsJSON") private var serviceConfigsJSON: String = ServiceConfig.defaultJSON()

    nonisolated static let maxParallelScans = 32
    
    init() {
        bonjourBrowser.start()
    }
    

    func startScan() {
        stopScan()
        statusMessage = ""
        results = []

        let ips = parseRange(inputRange)
        guard !ips.isEmpty else {
            statusMessage = "Invalid range. Use format 192.168.1.1-192.168.1.15"
            return
        }

        isScanning = true
        progressText = "Queued 0/\(ips.count)"

        triggerLocalNetworkAccess()

        let ipValues = ips
        let total = ipValues.count
        let enabledServices = activeServices()
        let discoveryPorts = discoveryPorts(from: enabledServices)

        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            var nextIndex = 0
            let progress = ScanProgress()
            var resultMap: [Int: IPScanResult] = [:]

            await withTaskGroup(of: (Int, IPScanResult).self) { group in
                func addNext() {
                    guard nextIndex < total else { return }
                    let index = nextIndex
                    let ipValue = ipValues[index]
                    nextIndex += 1

                    group.addTask {
                        let result = await Scanner.scan(
                            ipValue: ipValue,
                            bonjourCache: self.bonjourCache,
                            discoveryPorts: discoveryPorts,
                            servicePorts: enabledServices
                        )
                        return (index, result)
                    }
                }

                for _ in 0..<min(Self.maxParallelScans, total) {
                    addNext()
                }

                while let (index, result) = await group.next() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    resultMap[index] = result
                    let completed = await progress.increment()

                    let orderedResults = (0..<total).compactMap { resultMap[$0] }
                    await MainActor.run {
                        self.results = orderedResults
                        self.progressText = "Completed \(completed)/\(total)"
                    }

                    addNext()
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.isScanning = false
                    self.progressText = "Done"
                }
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        progressText = ""
    }

    func fillWithCurrentSubnet() {
        if let range = currentSubnetRange() {
            inputRange = range
            statusMessage = ""
        } else {
            statusMessage = "Unable to determine local subnet."
        }
    }

    private func triggerLocalNetworkAccess() {
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard sock >= 0 else { return }
        defer { close(sock) }

        var yes: Int32 = 1
        unsafe setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(9).bigEndian
        dest.sin_addr = in_addr(s_addr: in_addr_t(0xFFFFFFFF).bigEndian)

        let payload: [UInt8] = [0x00]
        unsafe payload.withUnsafeBytes { rawBuffer in
            unsafe withUnsafePointer(to: &dest) {
                unsafe $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    _ = unsafe sendto(
                        sock,
                        rawBuffer.baseAddress,
                        rawBuffer.count,
                        0,
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }

    private func parseRange(_ input: String) -> [UInt32] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let parts = trimmed.split(separator: "-").map { String($0) }
        if parts.count == 1 {
            guard let value = ipv4ToUInt32(parts[0]) else { return [] }
            return [value]
        }
        if parts.count == 2 {
            guard let start = ipv4ToUInt32(parts[0]),
                  let end = ipv4ToUInt32(parts[1]),
                  start <= end else { return [] }
            return Array(start...end)
        }
        return []
    }

    private func ipv4ToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard let byte = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    private func currentSubnetRange() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return nil
        }
        defer { freeifaddrs(firstAddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = pointer?.pointee {
            defer { pointer = addr.ifa_next }
            let flags = addr.ifa_flags
            if (flags & UInt32(IFF_UP)) == 0 || (flags & UInt32(IFF_LOOPBACK)) != 0 {
                continue
            }
            guard let sockaddrPtr = addr.ifa_addr,
                  sockaddrPtr.pointee.sa_family == sa_family_t(AF_INET),
                  let netmaskPtr = addr.ifa_netmask else {
                continue
            }

            let ipAddr = sockaddrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let maskAddr = netmaskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }

            let ip = UInt32(bigEndian: ipAddr.s_addr)
            let mask = UInt32(bigEndian: maskAddr.s_addr)

            let firstOctet = (ip >> 24) & 0xFF
            if firstOctet == 169 {
                continue
            }

            let network = ip & mask
            let broadcast = network | (~mask)
            let start = network + 1
            let end = broadcast - 1
            if start >= end {
                continue
            }

            return "\(Scanner.uint32ToIPv4(start))-\(Scanner.uint32ToIPv4(end))"
        }

        return nil
    }

    func csvString() -> String {
        let header = ["IP", "Hostname", "Alive", "Services"]
        var lines: [String] = [csvLine(header)]

        for result in results {
            let services = result.openServices.map { $0.name }.joined(separator: ";")
            let row = [
                result.ipAddress,
                result.hostname ?? "",
                result.isAlive ? "yes" : "no",
                services
            ]
            lines.append(csvLine(row))
        }

        return lines.joined(separator: "\n")
    }

    private func csvLine(_ fields: [String]) -> String {
        fields.map { field in
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
                return "\"\(escaped)\""
            }
            return escaped
        }
        .joined(separator: ",")
    }

    private func activeServices() -> [Service] {
        let configs = ServiceConfig.decode(from: serviceConfigsJSON)
        return configs.compactMap { config in
            guard config.isEnabled, (1...65535).contains(config.port) else { return nil }
            return Service(name: config.name, port: UInt16(config.port), transport: config.transport)
        }
    }

    private func discoveryPorts(from services: [Service]) -> [UInt16] {
        let ports = services.filter { $0.transport == .tcp }.map { $0.port }
        if ports.isEmpty {
            return ServiceCatalog.discoveryPorts
        }
        return Array(Set(ports)).sorted()
    }
}

private enum Scanner {

    static func scan(
        ipValue: UInt32,
        bonjourCache: BonjourCache,
        discoveryPorts: [UInt16],
        servicePorts: [Service]
    ) async -> IPScanResult {
        let ipString = uint32ToIPv4(ipValue)
        let isAlive = await checkAlive(ipString, discoveryPorts: discoveryPorts)
        var openServices: [Service] = []
        var hostname: String? = nil

        if isAlive {
            hostname = await resolveHostname(ipString, bonjourCache: bonjourCache)
            for service in servicePorts {
                if Task.isCancelled { break }
                let status = await checkPortStatus(
                    ip: ipString,
                    port: service.port,
                    transport: service.transport,
                    timeout: 1.0
                )
                if status == .open {
                    openServices.append(service)
                }
            }
        }

        let summary = openServices.map { service in
            service.transport == .udp ? "\(service.name) (udp)" : service.name
        }.joined(separator: ", ")
        return IPScanResult(
            ipAddress: ipString,
            hostname: hostname,
            isAlive: isAlive,
            openServices: openServices,
            servicesSummary: summary
        )
    }

    private static func checkAlive(_ ip: String, discoveryPorts: [UInt16]) async -> Bool {
        if await icmpPing(ip, timeout: 1.0) {
            return true
        }
        for port in discoveryPorts {
            let status = await checkPortStatus(ip: ip, port: port, transport: .tcp, timeout: 0.8)
            if status == .open || status == .closed {
                return true
            }
        }
        return false
    }

    private enum PortStatus {
        case open
        case closed
        case timeoutOrError
    }

    private static func checkPortStatus(
        ip: String,
        port: UInt16,
        transport: ServiceTransport,
        timeout: TimeInterval
    ) async -> PortStatus {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ip)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: .timeoutOrError)
                return
            }

            let connection = NWConnection(host: host, port: nwPort, using: transport == .udp ? .udp : .tcp)
            let queue = DispatchQueue(label: "port-check-\(ip)-\(port)")
            final class FinishState: @unchecked Sendable {
                var didFinish = false
            }
            let state = FinishState()

            let finish: @Sendable (PortStatus) -> Void = { status in
                if state.didFinish { return }
                state.didFinish = true
                connection.cancel()
                continuation.resume(returning: status)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if transport == .udp {
                        let payload = Data([0x00])
                        connection.send(content: payload, completion: .contentProcessed { error in
                            finish(error == nil ? .open : .timeoutOrError)
                        })
                    } else {
                        finish(.open)
                    }
                case .failed(let error):
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        finish(.closed)
                    } else {
                        finish(.timeoutOrError)
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(.timeoutOrError)
            }
        }
    }

    private static func resolveHostname(_ ip: String, bonjourCache: BonjourCache) async -> String? {
        let reverse = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)
                let result = ip.withCString { cstr in
                    inet_pton(AF_INET, cstr, &addr.sin_addr)
                }
                guard result == 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo(
                            $0,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &host,
                            socklen_t(host.count),
                            nil,
                            0,
                            NI_NAMEREQD
                        )
                    }
                }

                if status == 0 {
                    let length = host.firstIndex(of: 0) ?? host.count
                    let bytes = host.prefix(length).map { UInt8(bitPattern: $0) }
                    let name = String(decoding: bytes, as: UTF8.self)
                    continuation.resume(returning: name)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
        if let reverse {
            return reverse
        }
        return await bonjourCache.hostname(for: ip)
    }

    private static func icmpPing(_ ip: String, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                let timeoutMs = Int(max(1, timeout * 1000))
                process.arguments = ["-c", "1", "-W", "\(timeoutMs)", "-n", ip]

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: false)
                    return
                }

                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }

    static func uint32ToIPv4(_ value: UInt32) -> String {
        let b1 = (value >> 24) & 0xFF
        let b2 = (value >> 16) & 0xFF
        let b3 = (value >> 8) & 0xFF
        let b4 = value & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }
}

private actor ScanProgress {
    private var completed = 0

    func increment() -> Int {
        completed += 1
        return completed
    }
}
