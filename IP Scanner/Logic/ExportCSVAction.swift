//
//  ExportCSVAction.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//

import SwiftUI

struct ExportCSVAction {
    let action: () -> Void
}

private struct ExportCSVActionKey: FocusedValueKey {
    typealias Value = ExportCSVAction
}

extension FocusedValues {
    var exportCSVAction: ExportCSVAction? {
        get { self[ExportCSVActionKey.self] }
        set { self[ExportCSVActionKey.self] = newValue }
    }
}
