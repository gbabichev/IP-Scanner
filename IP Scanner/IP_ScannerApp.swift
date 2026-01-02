//
//  IP_ScannerApp.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import SwiftUI

@main
struct IP_ScannerApp: App {
    @StateObject private var viewModel = AppViewModel()
    @FocusedValue(\.exportCSVAction) private var exportCSVAction

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
        .commands {
            CommandGroup(after: .importExport) {
                Button("Export CSV…") {
                    exportCSVAction?.action()
                }
                .keyboardShortcut("e")
                .disabled(viewModel.results.isEmpty || exportCSVAction == nil)
            }
        }
    }
}
