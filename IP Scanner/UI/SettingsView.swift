//
//  SettingsView.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serviceConfigsJSON") private var serviceConfigsJSON: String = ServiceConfig.defaultJSON()
    @State private var configs: [ServiceConfig] = []
    @State private var newServiceName = ""
    @State private var newServicePort = ""

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
                            Text("\(configs[index].port)")
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
                            Text("\(configs[index].port)")
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

            HStack(spacing: 8) {
                TextField("Service name", text: $newServiceName)
                    .textFieldStyle(.roundedBorder)
                TextField("Port", text: $newServicePort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
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
        let config = ServiceConfig(name: name, port: port, isEnabled: true)
        configs.append(config)
        newServiceName = ""
        newServicePort = ""
    }

    private func removeService(at index: Int) {
        configs.remove(at: index)
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
