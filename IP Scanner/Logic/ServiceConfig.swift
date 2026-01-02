//
//  ServiceConfig.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import Foundation

struct ServiceConfig: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var port: Int
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, port: Int, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.port = port
        self.isEnabled = isEnabled
    }

    static func defaultConfigs() -> [ServiceConfig] {
        ServiceCatalog.servicePorts.map { service in
            ServiceConfig(name: service.name, port: Int(service.port), isEnabled: true)
        }
    }

    static func decode(from json: String) -> [ServiceConfig] {
        guard let data = json.data(using: .utf8) else {
            return defaultConfigs()
        }
        do {
            let decoded = try JSONDecoder().decode([ServiceConfig].self, from: data)
            return mergeDefaults(into: decoded)
        } catch {
            return defaultConfigs()
        }
    }

    static func encode(_ configs: [ServiceConfig]) -> String {
        do {
            let data = try JSONEncoder().encode(configs)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    static func defaultJSON() -> String {
        encode(defaultConfigs())
    }

    private static func mergeDefaults(into existing: [ServiceConfig]) -> [ServiceConfig] {
        let defaultConfigs = defaultConfigs()
        let existingKeys = Set(existing.map { key(for: $0) })
        let missingDefaults = defaultConfigs.filter { !existingKeys.contains(key(for: $0)) }
        let customConfigs = existing.filter { !isDefault($0, defaults: defaultConfigs) }
        let merged = defaultConfigs.map { def in
            existing.first { key(for: $0) == key(for: def) } ?? def
        }
        return merged + customConfigs + missingDefaults
    }

    private static func isDefault(_ config: ServiceConfig, defaults: [ServiceConfig]) -> Bool {
        defaults.contains { key(for: $0) == key(for: config) }
    }

    private static func key(for config: ServiceConfig) -> String {
        "\(config.name.lowercased()):\(config.port)"
    }
}
