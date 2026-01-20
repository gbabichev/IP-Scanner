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

struct NetworkInterface: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let ipAddress: String
    let netmask: UInt32
}

struct Service: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let port: UInt16
}

struct IPScanResult: Identifiable, Sendable {
    let id = UUID()
    let ipAddress: String
    let ipValue: UInt32
    var hostname: String?
    var macAddress: String?
    var isAlive: Bool
    var openServices: [Service]
    var servicesSummary: String
}

extension IPScanResult {
    var ipSortKey: UInt32 {
        ipValue
    }

    var hostnameSortKey: String {
        hostname ?? ""
    }

    var macSortKey: String {
        macAddress ?? ""
    }

    var statusSortKey: String {
        isAlive ? "Alive" : "No response"
    }
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
            var orderedResults = Array<IPScanResult?>(repeating: nil, count: total)
            var publishedResults: [IPScanResult] = []
            var nextPublishIndex = 0

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

                    orderedResults[index] = result
                    let completed = await progress.increment()

                    var appended: [IPScanResult] = []
                    while nextPublishIndex < total, let value = orderedResults[nextPublishIndex] {
                        appended.append(value)
                        nextPublishIndex += 1
                    }
                    if !appended.isEmpty {
                        publishedResults.append(contentsOf: appended)
                    }
                    await MainActor.run {
                        self.results = publishedResults
                        self.progressText = "Completed \(completed)/\(total)"
                    }

                    addNext()
                }
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.isScanning = false
                    self.progressText = "IP Scan Complete"
                }
            }
        }
    }

    func rangeCount(for input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: "-").map { String($0) }
        if parts.count == 1 {
            return ipv4ToUInt32(parts[0]) == nil ? nil : 1
        }
        if parts.count == 2 {
            guard let start = ipv4ToUInt32(parts[0]),
                  let end = ipv4ToUInt32(parts[1]),
                  start <= end else { return nil }
            let count = UInt64(end) - UInt64(start) + 1
            return Int(count)
        }
        return nil
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

    func fillWithSubnet(for interface: NetworkInterface?) {
        guard let interface, let range = subnetRange(for: interface) else {
            statusMessage = "Unable to determine local subnet."
            return
        }
        inputRange = range
        statusMessage = ""
    }

    func networkInterfaces() -> [NetworkInterface] {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return []
        }
        defer { freeifaddrs(firstAddr) }

        var interfaces: [NetworkInterface] = []
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
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addrCopy = ipAddr
            let result = inet_ntop(AF_INET, &addrCopy, &buffer, socklen_t(INET_ADDRSTRLEN))
            guard result != nil else { continue }
            let length = buffer.firstIndex(of: 0) ?? buffer.count
            let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
            let ip = String(decoding: bytes, as: UTF8.self)
            if ip.hasPrefix("169.") {
                continue
            }

            let mask = UInt32(bigEndian: maskAddr.s_addr)
            let name = String(cString: addr.ifa_name)
            let id = "\(name)-\(ip)"
            interfaces.append(NetworkInterface(id: id, name: name, ipAddress: ip, netmask: mask))
        }

        return interfaces.sorted { $0.name < $1.name }
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
        subnetRange(for: networkInterfaces().first)
    }

    private func subnetRange(for interface: NetworkInterface?) -> String? {
        guard let interface,
              let ip = ipv4ToUInt32(interface.ipAddress) else {
            return nil
        }

        let mask = interface.netmask
        let network = ip & mask
        let broadcast = network | (~mask)
        let start = network + 1
        let end = broadcast - 1
        guard start < end else { return nil }
        return "\(Scanner.uint32ToIPv4(start))-\(Scanner.uint32ToIPv4(end))"
    }

    func csvString() -> String {
        let header = ["IP", "Hostname", "MAC", "Alive", "Services"]
        var lines: [String] = [csvLine(header)]

        for result in results {
            let services = result.openServices.map { $0.name }.joined(separator: ";")
            let row = [
                result.ipAddress,
                result.hostname ?? "",
                result.macAddress ?? "",
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
            return Service(name: config.name, port: UInt16(config.port))
        }
    }

    private func discoveryPorts(from services: [Service]) -> [UInt16] {
        let ports = services.map { $0.port }
        return ports.isEmpty ? ServiceCatalog.discoveryPorts : Array(Set(ports)).sorted()
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
        var macAddress: String? = nil

        if isAlive {
            hostname = await resolveHostname(ipString, bonjourCache: bonjourCache)
            macAddress = await resolveMacAddress(ipString)
            for service in servicePorts {
                if Task.isCancelled { break }
                let status = await checkPortStatus(
                    ip: ipString,
                    port: service.port,
                    timeout: 1.0
                )
                if status == .open {
                    openServices.append(service)
                }
            }
        }

        let summary = openServices.map { $0.name }.joined(separator: ", ")
        return IPScanResult(
            ipAddress: ipString,
            ipValue: ipValue,
            hostname: hostname,
            macAddress: macAddress,
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
            let status = await checkPortStatus(ip: ip, port: port, timeout: 0.8)
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
        timeout: TimeInterval
    ) async -> PortStatus {
        await withCheckedContinuation { continuation in
            let host = NWEndpoint.Host(ip)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: .timeoutOrError)
                return
            }

            let connection = NWConnection(host: host, port: nwPort, using: .tcp)
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
                    finish(.open)
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

    private static func resolveMacAddress(_ ip: String) async -> String? {
        let output = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
                process.arguments = ["-n", ip]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                continuation.resume(returning: output)
            }
        }
        guard let output else { return nil }
        return parseMacAddress(from: output)
    }

    private static func parseMacAddress(from output: String) -> String? {
        let pattern = "([0-9a-fA-F]{1,2}:){5}[0-9a-fA-F]{1,2}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              let matchRange = Range(match.range, in: output) else {
            return nil
        }
        return String(output[matchRange]).lowercased()
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
