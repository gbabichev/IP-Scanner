//
//  ContentView.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("IP Scanner")
                .font(.title2)

            HStack {
                TextField("192.168.1.1-192.168.1.15", text: $viewModel.inputRange)
                    .textFieldStyle(.roundedBorder)
                Button(viewModel.isScanning ? "Stop" : "Scan") {
                    if viewModel.isScanning {
                        viewModel.stopScan()
                    } else {
                        viewModel.startScan()
                    }
                }
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
    }
}
