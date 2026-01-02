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
            return try JSONDecoder().decode([ServiceConfig].self, from: data)
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
}
