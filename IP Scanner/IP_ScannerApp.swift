//
//  IP_ScannerApp.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//  App entry point and command wiring.
//  Sets up the main window scene, About sheet, and menu commands.
//  Owns the shared ServicesActionsModel used by the Services menu.
//

import SwiftUI

@main
struct IP_ScannerApp: App {
    
    @Environment(\.openWindow) private var openWindow
    @State private var isAboutPresented: Bool = false
    @StateObject private var servicesActions = ServicesActionsModel()
    @StateObject private var exportActions = ExportActionsModel()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(servicesActions)
                .environmentObject(exportActions)
                .sheet(isPresented: $isAboutPresented) {
                    AboutView()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    isAboutPresented = true
                } label: {
                    Label("About IP Scanner", systemImage: "info.circle")
                }
            }
            
            CommandGroup(replacing: .newItem) {
                Button {
                    openWindow(id: "main")
                } label: {
                    Label("New Window", systemImage: "plus.square.on.square")
                }
                .keyboardShortcut("n")
            }
            
            CommandGroup(after: .newItem) {
                Divider()
                Button {
                    exportActions.export?()
                } label: {
                    Label("Export CSV…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e")
                .disabled(!exportActions.canExport)
                Divider()
            }

            CommandMenu("Services") {
                Button {
                    servicesActions.import?()
                } label: {
                    Label("Import Services", systemImage: "square.and.arrow.down")
                }

                Button {
                    servicesActions.export?()
                } label: {
                    Label("Export Services", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
