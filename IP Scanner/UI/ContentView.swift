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
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @EnvironmentObject private var servicesActions: ServicesActionsModel
    @EnvironmentObject private var exportActions: ExportActionsModel
    @AppStorage("inputRange") private var storedRange: String = "192.168.1.1-192.168.1.15"
    @State private var inputRangeText: String = ""
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
    @AppStorage("selectedInterfaceId") private var storedInterfaceId: String = ""
    @State private var interfaces: [NetworkInterface] = []
    @State private var selectedInterfaceId: String?
    @State private var toastMessage: String = ""
    @State private var isToastVisible = false
    private var resultsSnapshot: ResultsTableSnapshot {
        ResultsTableSnapshot(
            results: sortedResults,
            sortOrder: sortOrder,
            isResultsEmpty: viewModel.results.isEmpty,
            shouldShowEmptyState: shouldShowEmptyState
        )
    }
    private var sortOrderBinding: Binding<[KeyPathComparator<IPScanResult>]> {
        Binding(
            get: { sortOrder },
            set: { newValue in
                guard sortOrder != newValue else { return }
                sortOrder = newValue
                updateSortedResults()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            inputRow
            interfacePicker
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
        .overlay(alignment: .topLeading) {
            toastView
        }
        .onTapGesture {
            isRangeFocused = false
        }
        .onAppear {
            viewModel.inputRange = storedRange
            inputRangeText = storedRange
            servicesActions.export = { beginExportServices() }
            servicesActions.import = { beginImportServices() }
            exportActions.export = { beginExport() }
            exportActions.canExport = !viewModel.results.isEmpty
            refreshInterfaces()
            isRangeFocused = false
            updateSortedResults()
        }
        .onChange(of: selectedInterfaceId) { _, newValue in
            storedInterfaceId = newValue ?? ""
        }
        .onChange(of: viewModel.results.count) { _, newValue in
            exportActions.canExport = newValue > 0
            updateSortedResults()
        }
        .onChange(of: hideNoResponse) { _, _ in
            updateSortedResults()
        }
        .onChange(of: onlyWithServices) { _, _ in
            updateSortedResults()
        }
        .onChange(of: isRangeFocused) { _, newValue in
            if !newValue {
                commitRangeInput()
            }
        }
        .onChange(of: viewModel.inputRange) { _, newValue in
            guard inputRangeText != newValue else { return }
            inputRangeText = newValue
            storedRange = newValue
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
            TextField("192.168.1.1-192.168.1.5", text: $inputRangeText)
                .textFieldStyle(.roundedBorder)
                .focused($isRangeFocused)
                .onSubmit {
                    commitRangeInput()
                    isRangeFocused = false
                }
        }
    }

    @ViewBuilder
    private var interfacePicker: some View {
        if !interfaces.isEmpty {
            HStack(spacing: 8) {
                Picker("Interface", selection: $selectedInterfaceId) {
                    ForEach(interfaces) { iface in
                        Text("\(iface.name) • \(iface.ipAddress)")
                            .tag(Optional(iface.id))
                    }
                }
                .pickerStyle(.menu)
                Button {
                    refreshInterfaces()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh interfaces")
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
        if viewModel.isScanning || !viewModel.progressText.isEmpty || shouldShowSummary {
            VStack(alignment: .leading, spacing: 2) {
                if viewModel.isScanning || !viewModel.progressText.isEmpty {
                    Text(viewModel.progressText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if shouldShowSummary {
                    Text("Showing \(sortedResults.count)/\(viewModel.results.count) IPs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var filterButtons: some View {
        HStack(spacing: 8) {
            Button("Hide No Response") {
                hideNoResponse.toggle()
            }
            .buttonStyle(.bordered)
            .tint(hideNoResponse ? .blue : .primary)
            .disabled(!hasResults)

            Button("Only With Services") {
                onlyWithServices.toggle()
            }
            .buttonStyle(.bordered)
            .tint(onlyWithServices ? .blue : .primary)
            .disabled(!hasResults)

            Button("Reset View") {
                hideNoResponse = false
                onlyWithServices = false
            }
            .buttonStyle(.bordered)
            .disabled(!hasResults)
        }
    }

    private var hasResults: Bool {
        !viewModel.results.isEmpty
    }

    private var resultsTable: some View {
        ResultsTableView(
            snapshot: resultsSnapshot,
            results: sortedResults,
            sortOrder: sortOrderBinding,
            resetFilters: {
                hideNoResponse = false
                onlyWithServices = false
            },
            copyToClipboard: copyToClipboard
        )
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

    private var shouldShowSummary: Bool {
        !viewModel.results.isEmpty
    }

    private var shouldShowEmptyState: Bool {
        sortedResults.isEmpty
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
                if let selectedInterface {
                    viewModel.fillWithSubnet(for: selectedInterface)
                } else {
                    viewModel.fillWithCurrentSubnet()
                }
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
        commitRangeInput()
        if let count = viewModel.rangeCount(for: inputRangeText), count > 256 {
            pendingRangeCount = count
            isLargeRangeAlertPresented = true
        } else {
            viewModel.startScan()
        }
    }

    private func commitRangeInput() {
        guard viewModel.inputRange != inputRangeText else { return }
        viewModel.inputRange = inputRangeText
        storedRange = inputRangeText
    }

    private func refreshInterfaces() {
        interfaces = viewModel.networkInterfaces()
        if interfaces.isEmpty {
            selectedInterfaceId = nil
            return
        }
        if let match = interfaces.first(where: { $0.id == storedInterfaceId }) {
            selectedInterfaceId = match.id
        } else {
            selectedInterfaceId = interfaces.first?.id
        }
    }

    private var selectedInterface: NetworkInterface? {
        guard let selectedInterfaceId else { return nil }
        return interfaces.first { $0.id == selectedInterfaceId }
    }

    @ViewBuilder
    private var toastView: some View {
        if isToastVisible {
            Text(toastMessage)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(.thinMaterial, in: Capsule())
                .shadow(radius: 4, x: 0, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 12)
                .padding(.leading, 12)
        }
    }

    private func copyToClipboard(_ value: String, label: String) {
        guard !value.isEmpty else { return }
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        #endif
        showToast(label)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeOut(duration: 0.15)) {
            isToastVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeIn(duration: 0.2)) {
                isToastVisible = false
            }
        }
    }
}

private struct ResultSignature: Equatable {
    let id: UUID
    let ipAddress: String
    let hostname: String?
    let macAddress: String?
    let isAlive: Bool
    let servicesSummary: String

    init(result: IPScanResult) {
        id = result.id
        ipAddress = result.ipAddress
        hostname = result.hostname
        macAddress = result.macAddress
        isAlive = result.isAlive
        servicesSummary = result.servicesSummary
    }
}

private struct ResultsTableSnapshot: Equatable {
    let results: [ResultSignature]
    let sortOrder: [KeyPathComparator<IPScanResult>]
    let isResultsEmpty: Bool
    let shouldShowEmptyState: Bool

    init(
        results: [IPScanResult],
        sortOrder: [KeyPathComparator<IPScanResult>],
        isResultsEmpty: Bool,
        shouldShowEmptyState: Bool
    ) {
        self.results = results.map(ResultSignature.init)
        self.sortOrder = sortOrder
        self.isResultsEmpty = isResultsEmpty
        self.shouldShowEmptyState = shouldShowEmptyState
    }
}

private struct ResultsTableView: View, Equatable {
    let snapshot: ResultsTableSnapshot
    let results: [IPScanResult]
    let sortOrder: Binding<[KeyPathComparator<IPScanResult>]>
    let resetFilters: () -> Void
    let copyToClipboard: (String, String) -> Void

    static func == (lhs: ResultsTableView, rhs: ResultsTableView) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        ZStack {
            Table(results, sortOrder: sortOrder) {
                TableColumn("IP", value: \.ipSortKey) { result in
                    Text(result.ipAddress)
                        .contextMenu {
                            Button("Copy") {
                                copyToClipboard(result.ipAddress, "IP copied")
                            }
                        }
                }
                TableColumn("Hostname", value: \.hostnameSortKey) { result in
                    Text(result.hostname ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contextMenu {
                            Button("Copy") {
                                copyToClipboard(result.hostname ?? "", "Hostname copied")
                            }
                            .disabled(result.hostname?.isEmpty ?? true)
                        }
                }
                TableColumn("MAC", value: \.macSortKey) { result in
                    Text(result.macAddress ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contextMenu {
                            Button("Copy") {
                                copyToClipboard(result.macAddress ?? "", "MAC copied")
                            }
                            .disabled(result.macAddress?.isEmpty ?? true)
                        }
                }
                TableColumn("Status", value: \.statusSortKey) { result in
                    Text(result.isAlive ? "Alive" : "No response")
                        .foregroundStyle(result.isAlive ? .green : .secondary)
                        .contextMenu {
                            Button("Copy") {
                                copyToClipboard(result.isAlive ? "Alive" : "No response", "Status copied")
                            }
                        }
                }
                TableColumn("Services", value: \.servicesSummary) { result in
                    Text(result.servicesSummary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contextMenu {
                            Button("Copy") {
                                copyToClipboard(result.servicesSummary, "Services copied")
                            }
                            .disabled(result.servicesSummary.isEmpty)
                        }
                }
            }
            .tableStyle(.inset)

            if snapshot.shouldShowEmptyState {
                VStack(spacing: 8) {
                    if snapshot.isResultsEmpty {
                        Text("No scan results yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No results match the current filters.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Reset Filters") {
                            resetFilters()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
