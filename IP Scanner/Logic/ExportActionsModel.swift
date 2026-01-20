//
//  ExportActionsModel.swift
//  IP Scanner
//
//  Bridges the File menu export action to the active view.
//

import Combine
import Foundation

final class ExportActionsModel: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    var export: (() -> Void)? {
        didSet { objectWillChange.send() }
    }
    var canExport: Bool = false {
        didSet { objectWillChange.send() }
    }
}
