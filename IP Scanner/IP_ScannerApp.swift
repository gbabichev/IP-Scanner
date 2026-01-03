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
    
    @FocusedValue(\.exportCSVAction) private var exportCSVAction
    @Environment(\.openWindow) private var openWindow
    @State private var isAboutPresented: Bool = false
    @StateObject private var servicesActions = ServicesActionsModel()
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(servicesActions)
                .sheet(isPresented: $isAboutPresented) {
                    AboutView()
                }
        }
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
                    exportCSVAction?.action()
                } label: {
                    Label("Export CSV…", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e")
                .disabled(exportCSVAction == nil)
                Divider()
            }

            CommandMenu("Services") {
                Button {
                    servicesActions.import?()
                } label: {
                    Label("Import Services…", systemImage: "square.and.arrow.down")
                }

                Button {
                    servicesActions.export?()
                } label: {
                    Label("Export Custom Services…", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}
