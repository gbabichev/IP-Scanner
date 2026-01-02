//
//  AppViewModel.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import Foundation
import Darwin
import Network
import Combine

struct Service: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let port: UInt16
}

struct IPScanResult: Identifiable {
    let id = UUID()
    let ipAddress: String
    var isAlive: Bool
    var openServices: [Service]
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var inputRange: String = "192.168.20.1-192.168.20.5"
    @Published var results: [IPScanResult] = []
    @Published var isScanning: Bool = false
    @Published var progressText: String = ""
    @Published var statusMessage: String = ""

    private var scanTask: Task<Void, Never>?

    private let discoveryPorts: [UInt16] = [80, 443, 22]
    private let servicePorts: [Service] = [
        Service(name: "http", port: 80),
        Service(name: "https", port: 443),
        Service(name: "ssh", port: 22),
        Service(name: "smb", port: 445),
        Service(name: "netbios", port: 139)
    ]

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
        progressText = "Starting..."

        scanTask = Task {
            triggerLocalNetworkAccess()
            for (index, ipValue) in ips.enumerated() {
                if Task.isCancelled { break }
                let ipString = uint32ToIPv4(ipValue)
                progressText = "Scanning \(ipString) (\(index + 1)/\(ips.count))"

                let isAlive = await checkAlive(ipString)
                var openServices: [Service] = []
                if isAlive {
                    for service in servicePorts {
                        if Task.isCancelled { break }
                        let status = await checkPortStatus(ip: ipString, port: service.port, timeout: 1.0)
                        if status == .open {
                            openServices.append(service)
                        }
                    }
                }

                let result = IPScanResult(ipAddress: ipString, isAlive: isAlive, openServices: openServices)
                results.append(result)
            }

            isScanning = false
            progressText = "Done"
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        progressText = ""
    }

    private func checkAlive(_ ip: String) async -> Bool {
        for port in discoveryPorts {
            let status = await checkPortStatus(ip: ip, port: port, timeout: 0.8)
            if status == .open || status == .closed {
                return true
            }
        }
        return false
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

    private enum PortStatus {
        case open
        case closed
        case timeoutOrError
    }

    private func checkPortStatus(ip: String, port: UInt16, timeout: TimeInterval) async -> PortStatus {
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

    private func uint32ToIPv4(_ value: UInt32) -> String {
        let b1 = (value >> 24) & 0xFF
        let b2 = (value >> 16) & 0xFF
        let b3 = (value >> 8) & 0xFF
        let b4 = value & 0xFF
        return "\(b1).\(b2).\(b3).\(b4)"
    }
}
