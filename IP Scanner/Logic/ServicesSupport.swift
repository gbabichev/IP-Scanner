//
//  ServicesSupport.swift
//  IP Scanner
//
//  Consolidated services support types:
//  - ServicesActionsModel bridges the Services menu to view actions across focus changes.
//  - ServiceConfig handles default/custom configs, JSON encoding, and merge rules.
//  - ServiceConfigDocument provides FileDocument import/export for services JSON.
//

import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class ServicesActionsModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var export: (() -> Void)? {
        didSet { objectWillChange.send() }
    }
    var `import`: (() -> Void)? {
        didSet { objectWillChange.send() }
    }
}

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

    private enum CodingKeys: String, CodingKey {
        case name
        case port
        case isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        port = try container.decode(Int.self, forKey: .port)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(port, forKey: .port)
        try container.encode(isEnabled, forKey: .isEnabled)
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

    static func decodeRaw(from json: String) -> [ServiceConfig]? {
        guard let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode([ServiceConfig].self, from: data)
    }

    static func exportCustomJSON(from json: String) -> String {
        let custom = customConfigs(from: json)
        return encodePretty(custom)
    }

    static func exportAllJSON(from json: String) -> String {
        let configs = decode(from: json)
        return encodePretty(configs)
    }

    static func mergeCustom(into existingJSON: String, imported: [ServiceConfig]) -> String {
        let defaults = defaultConfigs()
        let existingAll = decode(from: existingJSON)
        let existingCustom = existingAll.filter { !isDefault($0, defaults: defaults) }
        let importedCustom = imported.filter { !isDefault($0, defaults: defaults) }

        var mergedCustom: [ServiceConfig] = []
        var seen: Set<String> = []

        for config in existingCustom + importedCustom {
            let k = key(for: config)
            if seen.contains(k) { continue }
            seen.insert(k)
            mergedCustom.append(config)
        }

        return encode(defaults + mergedCustom)
    }

    static func customConfigs(from json: String) -> [ServiceConfig] {
        let defaults = defaultConfigs()
        let configs = decode(from: json)
        return configs.filter { !isDefault($0, defaults: defaults) }
    }

    static func encode(_ configs: [ServiceConfig]) -> String {
        do {
            let data = try JSONEncoder().encode(configs)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }

    static func encodePretty(_ configs: [ServiceConfig]) -> String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configs)
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

    static func key(for config: ServiceConfig) -> String {
        "\(config.name.lowercased()):\(config.port)"
    }
}

struct ServiceConfigDocument: FileDocument, Identifiable {
    static var readableContentTypes: [UTType] { [.json] }

    let id = UUID()
    var json: String

    init(json: String) {
        self.json = json
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            json = String(decoding: data, as: UTF8.self)
        } else {
            json = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(json.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
