//
//  ContentView.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @AppStorage("inputRange") private var storedRange: String = "192.168.1.1-192.168.1.15"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter IP or Range")
                .font(.title2)
            Text("Enter an IP range like 192.168.1.1-192.168.1.15 or use the network button to autofill.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
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

            List(viewModel.results) { result in
                HStack {
                    VStack(alignment: .leading) {
                        Text(result.ipAddress)
                            .font(.headline)
                        Text(result.isAlive ? "Alive" : "No response")
                            .foregroundStyle(result.isAlive ? .green : .secondary)
                    }
                    Spacer()
                    if result.isAlive {
                        Text(result.openServices.map { $0.name }.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            viewModel.inputRange = storedRange
        }
        .onChange(of: storedRange) { _,newValue in
            viewModel.inputRange = newValue
        }
        .onChange(of: viewModel.inputRange) { _,newValue in
            if storedRange != newValue {
                storedRange = newValue
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
}
