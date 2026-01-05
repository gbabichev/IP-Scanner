//
//  ContentView.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//  Main scanning UI and primary app interaction surface.
//  Handles input range, scan controls, filters, and results table.
//  Owns file import/export state and settings sheet presentation.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @EnvironmentObject private var servicesActions: ServicesActionsModel
    @AppStorage("inputRange") private var storedRange: String = "192.168.1.1-192.168.1.15"
    @AppStorage("serviceConfigsJSON") private var serviceConfigsJSON: String = ServiceConfig.defaultJSON()
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exportServicesDocument = ServiceConfigDocument(json: "")
    @State private var isExporting = false
    @State private var isExportingServices = false
    @State private var isImportingServices = false
    @State private var isSettingsPresented = false
    @State private var pendingServicesExport = false
    @State private var pendingServicesImport = false
    @State private var hideNoResponse = false
    @State private var onlyWithServices = false
    @State private var sortOrder: [KeyPathComparator<IPScanResult>] = []
    @FocusState private var isRangeFocused: Bool
    @State private var isLargeRangeAlertPresented = false
    @State private var pendingRangeCount: Int = 0
    @State private var sortedResults: [IPScanResult] = []
    private var sortOrderBinding: Binding<[KeyPathComparator<IPScanResult>]> {
        Binding(
            get: { sortOrder },
            set: { newValue in
                sortOrder = newValue
                updateSortedResults()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            inputRow
            statusView
            progressView
            filterButtons
            resultsTable
        }
        
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .overlay(alignment: .bottomTrailing) {
            BetaTag()
                .padding(12)
        }
        .onTapGesture {
            isRangeFocused = false
        }
        .onAppear {
            viewModel.inputRange = storedRange
            servicesActions.export = { beginExportServices() }
            servicesActions.import = { beginImportServices() }
            isRangeFocused = false
            updateSortedResults()
        }
        .onReceive(viewModel.$results) { _ in
            updateSortedResults()
        }
        .onChange(of: hideNoResponse) { _, _ in
            updateSortedResults()
        }
        .onChange(of: onlyWithServices) { _, _ in
            updateSortedResults()
        }
        .onChange(of: storedRange) { _, newValue in
            viewModel.inputRange = newValue
        }
        .onChange(of: viewModel.inputRange) { _, newValue in
            if storedRange != newValue {
                storedRange = newValue
            }
        }
        .onChange(of: isSettingsPresented) { _, newValue in
            guard !newValue else { return }
            if pendingServicesExport {
                pendingServicesExport = false
                performExportServices()
            } else if pendingServicesImport {
                pendingServicesImport = false
                beginImportServices()
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
            isExporting = false
        }
        .fileExporter(
            isPresented: $isExportingServices,
            document: exportServicesDocument,
            contentType: .json,
            defaultFilename: "ip-scanner-services"
        ) { result in
            if case .success(let url) = result {
                viewModel.statusMessage = "Exported to \(url.lastPathComponent)"
            }
            isExportingServices = false
        }
        .fileImporter(
            isPresented: $isImportingServices,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                importServices(from: url)
            case .failure:
                viewModel.statusMessage = "Import failed."
            }
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
        }
        .alert("Large range", isPresented: $isLargeRangeAlertPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Continue") {
                viewModel.startScan()
            }
        } message: {
            Text("This range contains \(pendingRangeCount) addresses. Scanning a large range can take a while. Continue?")
        }
        .toolbar {
            settingsToolbarItem
            titleToolbarItem
            networkToolbarItem
            scanToolbarItem
        }
    }

    private func beginExport() {
        exportDocument = CSVDocument(text: viewModel.csvString())
        isExporting = false
        DispatchQueue.main.async {
            isExporting = true
        }
    }

    private func beginExportServices() {
        if isSettingsPresented {
            pendingServicesExport = true
            isSettingsPresented = false
            return
        }
        performExportServices()
    }

    private func performExportServices() {
        let json = ServiceConfig.exportCustomJSON(from: serviceConfigsJSON)
        exportServicesDocument = ServiceConfigDocument(json: json)
        isExportingServices = false
        DispatchQueue.main.async {
            isExportingServices = true
        }
    }

    private func beginImportServices() {
        if isSettingsPresented {
            pendingServicesImport = true
            isSettingsPresented = false
            return
        }
        isImportingServices = true
    }

    private func importServices(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let json = String(decoding: data, as: UTF8.self)
            guard let imported = ServiceConfig.decodeRaw(from: json) else {
                viewModel.statusMessage = "Import failed."
                return
            }
            serviceConfigsJSON = ServiceConfig.mergeCustom(into: serviceConfigsJSON, imported: imported)
            viewModel.statusMessage = "Services imported."
        } catch {
            viewModel.statusMessage = "Import failed."
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Enter IP or Range")
                .font(.title2)
            Text("Enter an IP range like 192.168.1.1-192.168.1.15 or use the network button to autofill.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var inputRow: some View {
        HStack {
            if viewModel.isScanning {
                ProgressView()
                    .help("Scanning")
            }
            TextField("192.168.1.1-192.168.1.5", text: $storedRange)
                .textFieldStyle(.roundedBorder)
                .focused($isRangeFocused)
                .onSubmit {
                    isRangeFocused = false
                }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if !viewModel.statusMessage.isEmpty {
            Text(viewModel.statusMessage)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var progressView: some View {
        if viewModel.isScanning || !viewModel.progressText.isEmpty {
            Text(viewModel.progressText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var filterButtons: some View {
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
    }

    private var resultsTable: some View {
        ZStack {
            Table(sortedResults, sortOrder: sortOrderBinding) {
                TableColumn("IP", value: \.ipSortKey) { result in
                    Text(result.ipAddress)
                        // .textSelection(.enabled)
                }
                TableColumn("Hostname", value: \.hostnameSortKey) { result in
                    Text(result.hostname ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // .textSelection(.enabled)
                }
                TableColumn("MAC", value: \.macSortKey) { result in
                    Text(result.macAddress ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // .textSelection(.enabled)
                }
                TableColumn("Status", value: \.statusSortKey) { result in
                    Text(result.isAlive ? "Alive" : "No response")
                        .foregroundStyle(result.isAlive ? .green : .secondary)
                        // .textSelection(.enabled)
                }
                TableColumn("Services", value: \.servicesSummary) { result in
                    Text(result.servicesSummary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        // .textSelection(.enabled)
                }
            }
            .tableStyle(.inset)

            if shouldShowEmptyState {
                emptyStateView
            }
        }
    }

    private func updateSortedResults() {
        let filtered = viewModel.results.filter { result in
            if hideNoResponse && !result.isAlive {
                return false
            }
            if onlyWithServices && result.openServices.isEmpty {
                return false
            }
            return true
        }
        if sortOrder.isEmpty {
            sortedResults = filtered.sorted { $0.ipSortKey < $1.ipSortKey }
        } else {
            sortedResults = filtered.sorted(using: sortOrder)
        }
    }

    private var shouldShowEmptyState: Bool {
        sortedResults.isEmpty
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            if viewModel.results.isEmpty {
                Text("No scan results yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No results match the current filters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Reset Filters") {
                    hideNoResponse = false
                    onlyWithServices = false
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    private var networkToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.fillWithCurrentSubnet()
            } label: {
                Image(systemName: "network")
            }
            .help("Use current subnet")
        }
    }
    
    private var titleToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Text("IP Scanner")
                .padding(12)
                .bold()
        }
    }

    private var scanToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                if viewModel.isScanning {
                    viewModel.stopScan()
                } else {
                    beginScan()
                }
            } label: {
                Image(systemName: viewModel.isScanning ? "stop.fill" : "play.fill")
            }
            .help(viewModel.isScanning ? "Stop" : "Scan")
        }
    }

    private func beginScan() {
        if let count = viewModel.rangeCount(for: storedRange), count > 256 {
            pendingRangeCount = count
            isLargeRangeAlertPresented = true
        } else {
            viewModel.startScan()
        }
    }
}
