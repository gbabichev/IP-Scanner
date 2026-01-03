//
//  SettingsView.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//  Settings UI for managing default and custom service configurations.
//  Edits service enablement, adds/removes custom entries, and persists to AppStorage.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serviceConfigsJSON") private var serviceConfigsJSON: String = ServiceConfig.defaultJSON()
    @State private var configs: [ServiceConfig] = []
    @State private var newServiceName = ""
    @State private var newServicePort = ""
    @State private var newServiceTransport: ServiceTransport = .tcp

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Services")
                .font(.title2)
            Text("Enable or disable services, add new ones, and import or export settings from the File menu.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List {
                Section("Default Services") {
                    ForEach(defaultIndices, id: \.self) { index in
                        HStack {
                            Toggle(isOn: $configs[index].isEnabled) {
                                Text(configs[index].name)
                            }
                            Spacer()
                            Text("\(configs[index].port) \(configs[index].transport.rawValue.uppercased())")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Custom Services") {
                    ForEach(customIndices, id: \.self) { index in
                        HStack {
                            Toggle(isOn: $configs[index].isEnabled) {
                                Text(configs[index].name)
                            }
                            Spacer()
                            Text("\(configs[index].port) \(configs[index].transport.rawValue.uppercased())")
                                .foregroundStyle(.secondary)
                            Button {
                                removeService(at: index)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Remove service")
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button("Check All") {
                        setAllServicesEnabled(true)
                    }
                    .buttonStyle(.bordered)

                    Button("Uncheck All") {
                        setAllServicesEnabled(false)
                    }
                    .buttonStyle(.bordered)

                    Button("Common Services") {
                        selectCommonServices()
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 8) {
                    Button("Delete All Custom Services") {
                        deleteAllCustomServices()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            HStack(spacing: 8) {
                TextField("Service name", text: $newServiceName)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $newServicePort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Picker("Protocol", selection: $newServiceTransport) {
                    ForEach(ServiceTransport.allCases, id: \.self) { transport in
                        Text(transport.rawValue.uppercased())
                            .tag(transport)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Button {
                    addService()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(!canAddService)
                .help("Add service")
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 420)
        .onAppear {
            configs = ServiceConfig.decode(from: serviceConfigsJSON)
        }
        .onChange(of: configs) { _, newValue in
            serviceConfigsJSON = ServiceConfig.encode(newValue)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private var canAddService: Bool {
        guard !newServiceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let port = Int(newServicePort),
              (1...65535).contains(port) else {
            return false
        }
        return true
    }

    private func addService() {
        guard canAddService, let port = Int(newServicePort) else { return }
        let name = newServiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = ServiceConfig(name: name, port: port, transport: newServiceTransport, isEnabled: true)
        configs.append(config)
        newServiceName = ""
        newServicePort = ""
        newServiceTransport = .tcp
    }

    private func removeService(at index: Int) {
        configs.remove(at: index)
    }

    private func setAllServicesEnabled(_ isEnabled: Bool) {
        for index in configs.indices {
            configs[index].isEnabled = isEnabled
        }
    }

    private func deleteAllCustomServices() {
        configs.removeAll { !defaultKeySet.contains(key(for: $0)) }
    }

    private func selectCommonServices() {
        let commonNames = Set(["http", "https", "ssh", "ftp", "smb", "rdp", "vnc"])
        for index in configs.indices {
            let name = configs[index].name.lowercased()
            configs[index].isEnabled = commonNames.contains(name) && configs[index].transport == .tcp
        }
    }

    private var defaultKeySet: Set<String> {
        Set(ServiceCatalog.servicePorts.map { "\($0.name.lowercased()):\($0.port)" })
    }

    private var defaultIndices: [Int] {
        configs.indices.filter { index in
            defaultKeySet.contains(key(for: configs[index]))
        }
    }

    private var customIndices: [Int] {
        configs.indices.filter { index in
            !defaultKeySet.contains(key(for: configs[index]))
        }
    }

    private func key(for config: ServiceConfig) -> String {
        "\(config.name.lowercased()):\(config.port)"
    }
}
