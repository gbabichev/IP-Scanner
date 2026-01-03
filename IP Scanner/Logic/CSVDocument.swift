//
//  CSVDocument.swift
//  IP Scanner
//
//  Created by George Babichev on 1/2/26.
//  FileDocument wrapper for exporting scan results as CSV.
//  Encodes the exported string into a FileWrapper for the file exporter.
//

import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument, Identifiable {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let id = UUID()
    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
