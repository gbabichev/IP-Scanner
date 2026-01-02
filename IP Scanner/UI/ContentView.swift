//
//  ContentView.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage("inputRange") private var storedRange: String = "192.168.1.1-192.168.1.15"
    @State private var isExporting = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var hideNoResponse = false
    @State private var onlyWithServices = false

    private var filteredResults: [IPScanResult] {
        viewModel.results.filter { result in
            if hideNoResponse && !result.isAlive {
                return false
            }
            if onlyWithServices && result.openServices.isEmpty {
                return false
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter IP or Range")
                .font(.title2)
            Text("Enter an IP range like 192.168.1.1-192.168.1.15 or use the network button to autofill.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if viewModel.isScanning {
                    ProgressView()
                        .help("Scanning")
                }
                TextField("192.168.1.1-192.168.1.5", text: $storedRange)
                    .textFieldStyle(.roundedBorder)
            }

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .foregroundStyle(.red)
            }

            if viewModel.isScanning || !viewModel.progressText.isEmpty {
                Text(viewModel.progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Hide No Response") {
                    hideNoResponse.toggle()
                }
                .buttonStyle(.bordered)
                .tint(hideNoResponse ? .blue : .primary)

                Button("Only With Services") {
                    onlyWithServices.toggle()
                }
                .buttonStyle(.bordered)
                .tint(onlyWithServices ? .blue : .primary)

                Button("Reset View") {
                    hideNoResponse = false
                    onlyWithServices = false
                }
                .buttonStyle(.bordered)
            }

            Table(filteredResults) {
                TableColumn("IP") { result in
                    Text(result.ipAddress)
                }
                TableColumn("Hostname") { result in
                    Text(result.hostname ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                TableColumn("Status") { result in
                    Text(result.isAlive ? "Alive" : "No response")
                        .foregroundStyle(result.isAlive ? .green : .secondary)
                }
                TableColumn("Services") { result in
                    Text(result.servicesSummary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .tableStyle(.inset)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            viewModel.inputRange = storedRange
        }
        .onChange(of: storedRange) { _, newValue in
            viewModel.inputRange = newValue
        }
        .onChange(of: viewModel.inputRange) { _, newValue in
            if storedRange != newValue {
                storedRange = newValue
            }
        }
        .focusedValue(
            \.exportCSVAction,
            viewModel.results.isEmpty ? nil : ExportCSVAction {
                beginExport()
            }
        )
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "ip-scan-results"
        ) { result in
            if case .success(let url) = result {
                viewModel.statusMessage = "Exported to \(url.lastPathComponent)"
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.fillWithCurrentSubnet()
                } label: {
                    Image(systemName: "network")
                }
                .help("Use current subnet")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    if viewModel.isScanning {
                        viewModel.stopScan()
                    } else {
                        viewModel.startScan()
                    }
                } label: {
                    Image(systemName: viewModel.isScanning ? "stop.fill" : "play.fill")
                }
                .help(viewModel.isScanning ? "Stop" : "Scan")
            }
        }
    }

    private func beginExport() {
        exportDocument = CSVDocument(text: viewModel.csvString())
        isExporting = true
    }
}
